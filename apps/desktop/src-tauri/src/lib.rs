use base64::{Engine as _, engine::general_purpose::STANDARD as BASE64};
use percent_encoding::percent_decode_str;
use serde::Serialize;
use std::{
    ffi::OsStr,
    fs,
    io::Write,
    path::{Path, PathBuf},
    sync::{
        Mutex,
        atomic::{AtomicBool, Ordering},
    },
};
use tauri::{Emitter, Manager, State};
use url::Url;
use walkdir::WalkDir;

const MAX_SEARCH_FILE_BYTES: u64 = 2 * 1024 * 1024;
const MAX_ASSET_BYTES: u64 = 10 * 1024 * 1024;

#[derive(Default)]
struct PendingOpenFiles {
    paths: Mutex<Vec<String>>,
    frontend_ready: AtomicBool,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct MarkdownFile {
    path: String,
    name: String,
    parent: String,
    content: String,
    newline_style: String,
    has_utf8_bom: bool,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct WorkspaceNode {
    path: String,
    name: String,
    kind: &'static str,
    children: Vec<WorkspaceNode>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct SearchResult {
    path: String,
    name: String,
    relative_path: String,
    line: Option<usize>,
    preview: String,
}

#[tauri::command]
fn read_markdown(path: String) -> Result<MarkdownFile, String> {
    read_markdown_file(Path::new(&path))
}

#[tauri::command]
fn write_markdown(
    path: String,
    content: String,
    newline_style: String,
    has_utf8_bom: bool,
) -> Result<(), String> {
    let path = canonical_markdown_path(Path::new(&path))?;
    let serialized = if newline_style == "crlf" {
        content.replace('\n', "\r\n")
    } else {
        content
    };

    let mut bytes = Vec::with_capacity(serialized.len() + 3);
    if has_utf8_bom {
        bytes.extend_from_slice(&[0xEF, 0xBB, 0xBF]);
    }
    bytes.extend_from_slice(serialized.as_bytes());

    let mut file = fs::OpenOptions::new()
        .write(true)
        .truncate(true)
        .open(&path)
        .map_err(|error| format!("无法保存 {}：{error}", path.display()))?;
    file.write_all(&bytes)
        .and_then(|_| file.sync_all())
        .map_err(|error| format!("无法保存 {}：{error}", path.display()))
}

#[tauri::command]
fn scan_workspace(root: String) -> Result<Vec<WorkspaceNode>, String> {
    let root = canonical_directory(Path::new(&root))?;
    scan_directory(&root)
}

#[tauri::command]
fn search_workspace(root: String, query: String) -> Result<Vec<SearchResult>, String> {
    let root = canonical_directory(Path::new(&root))?;
    let query = query.trim().to_lowercase();
    if query.is_empty() {
        return Ok(Vec::new());
    }

    let mut results = Vec::new();
    for entry in WalkDir::new(&root)
        .follow_links(false)
        .max_depth(16)
        .into_iter()
        .filter_entry(|entry| !is_ignored(entry.file_name()))
        .filter_map(Result::ok)
    {
        let path = entry.path();
        if !path.is_file() || !is_markdown_path(path) {
            continue;
        }

        let relative_path = path
            .strip_prefix(&root)
            .unwrap_or(path)
            .to_string_lossy()
            .into_owned();
        let name = path
            .file_name()
            .and_then(OsStr::to_str)
            .unwrap_or_default()
            .to_owned();
        if relative_path.to_lowercase().contains(&query) {
            results.push(SearchResult {
                path: path.to_string_lossy().into_owned(),
                name,
                relative_path,
                line: None,
                preview: "文件名匹配".to_owned(),
            });
            if results.len() >= 100 {
                break;
            }
            continue;
        }

        if entry
            .metadata()
            .map(|value| value.len())
            .unwrap_or(u64::MAX)
            > MAX_SEARCH_FILE_BYTES
        {
            continue;
        }
        let Ok(contents) = fs::read_to_string(path) else {
            continue;
        };
        if let Some((index, line)) = contents
            .lines()
            .enumerate()
            .find(|(_, line)| line.to_lowercase().contains(&query))
        {
            results.push(SearchResult {
                path: path.to_string_lossy().into_owned(),
                name,
                relative_path,
                line: Some(index + 1),
                preview: line.trim().chars().take(160).collect(),
            });
            if results.len() >= 100 {
                break;
            }
        }
    }

    Ok(results)
}

#[tauri::command]
fn load_markdown_asset(
    source: String,
    document_path: String,
    workspace_root: String,
) -> Result<String, String> {
    if source.starts_with("http://")
        || source.starts_with("https://")
        || source.starts_with("data:")
    {
        return Ok(source);
    }

    let workspace_root = canonical_directory(Path::new(&workspace_root))?;
    let document_path = canonical_markdown_path(Path::new(&document_path))?;
    let decoded = percent_decode_str(source.split(['#', '?']).next().unwrap_or_default())
        .decode_utf8()
        .map_err(|_| "图片路径编码无效。".to_owned())?;
    let relative = Path::new(decoded.as_ref());
    if relative.is_absolute() {
        return Err("不允许读取绝对图片路径。".to_owned());
    }
    let candidate = document_path
        .parent()
        .ok_or_else(|| "无法确定文稿目录。".to_owned())?
        .join(relative)
        .canonicalize()
        .map_err(|error| format!("无法读取图片：{error}"))?;
    if !candidate.starts_with(&workspace_root) || !candidate.is_file() {
        return Err("不允许读取工作区之外的图片。".to_owned());
    }
    let metadata = candidate
        .metadata()
        .map_err(|error| format!("无法读取图片信息：{error}"))?;
    if metadata.len() > MAX_ASSET_BYTES {
        return Err("图片超过 10 MB 预览上限。".to_owned());
    }
    let mime = mime_guess::from_path(&candidate)
        .first()
        .filter(|value| value.type_() == mime_guess::mime::IMAGE)
        .ok_or_else(|| "仅允许预览常见图片格式。".to_owned())?;
    let data = fs::read(&candidate).map_err(|error| format!("无法读取图片：{error}"))?;
    Ok(format!("data:{mime};base64,{}", BASE64.encode(data)))
}

#[tauri::command]
fn drain_initial_open_files(state: State<'_, PendingOpenFiles>) -> Vec<String> {
    let mut pending = state
        .paths
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    let paths = std::mem::take(&mut *pending);
    state.frontend_ready.store(true, Ordering::Release);
    paths
}

fn read_markdown_file(path: &Path) -> Result<MarkdownFile, String> {
    let path = canonical_markdown_path(path)?;
    let bytes = fs::read(&path).map_err(|error| format!("无法读取 {}：{error}", path.display()))?;
    let (has_utf8_bom, source) = if bytes.starts_with(&[0xEF, 0xBB, 0xBF]) {
        (true, &bytes[3..])
    } else {
        (false, bytes.as_slice())
    };
    let decoded = std::str::from_utf8(source)
        .map_err(|_| "KaiMD 当前只支持 UTF-8 Markdown 文件。".to_owned())?;
    let crlf_count = decoded.matches("\r\n").count();
    let lf_count = decoded.matches('\n').count();
    let newline_style = if crlf_count > 0 && crlf_count == lf_count {
        "crlf"
    } else {
        "lf"
    };
    let content = decoded.replace("\r\n", "\n").replace('\r', "\n");
    let parent = path
        .parent()
        .ok_or_else(|| "无法确定文稿目录。".to_owned())?;

    Ok(MarkdownFile {
        path: path.to_string_lossy().into_owned(),
        name: path
            .file_name()
            .and_then(OsStr::to_str)
            .unwrap_or("Untitled.md")
            .to_owned(),
        parent: parent.to_string_lossy().into_owned(),
        content,
        newline_style: newline_style.to_owned(),
        has_utf8_bom,
    })
}

fn canonical_markdown_path(path: &Path) -> Result<PathBuf, String> {
    if !is_markdown_path(path) {
        return Err("KaiMD 仅打开 .md 和 .markdown 文件。".to_owned());
    }
    let canonical = path
        .canonicalize()
        .map_err(|error| format!("文件不存在或无法访问：{error}"))?;
    if !canonical.is_file() {
        return Err("所选项目不是文件。".to_owned());
    }
    Ok(canonical)
}

fn canonical_directory(path: &Path) -> Result<PathBuf, String> {
    let canonical = path
        .canonicalize()
        .map_err(|error| format!("文件夹不存在或无法访问：{error}"))?;
    if !canonical.is_dir() {
        return Err("所选项目不是文件夹。".to_owned());
    }
    Ok(canonical)
}

fn scan_directory(directory: &Path) -> Result<Vec<WorkspaceNode>, String> {
    let mut entries = fs::read_dir(directory)
        .map_err(|error| format!("无法扫描 {}：{error}", directory.display()))?
        .filter_map(Result::ok)
        .filter(|entry| !is_ignored(&entry.file_name()))
        .collect::<Vec<_>>();
    entries.sort_by_key(|entry| entry.file_name().to_string_lossy().to_lowercase());

    let mut nodes = Vec::new();
    for entry in entries {
        let path = entry.path();
        let Ok(file_type) = entry.file_type() else {
            continue;
        };
        if file_type.is_symlink() {
            continue;
        }
        let name = entry.file_name().to_string_lossy().into_owned();
        if file_type.is_dir() {
            let children = scan_directory(&path)?;
            if !children.is_empty() {
                nodes.push(WorkspaceNode {
                    path: path.to_string_lossy().into_owned(),
                    name,
                    kind: "directory",
                    children,
                });
            }
        } else if file_type.is_file() && is_markdown_path(&path) {
            nodes.push(WorkspaceNode {
                path: path.to_string_lossy().into_owned(),
                name,
                kind: "markdown",
                children: Vec::new(),
            });
        }
    }
    Ok(nodes)
}

fn is_ignored(name: &OsStr) -> bool {
    let value = name.to_string_lossy();
    value.starts_with('.')
        || matches!(
            value.as_ref(),
            "node_modules" | "target" | ".git" | ".build" | "dist"
        )
}

fn is_markdown_path(path: &Path) -> bool {
    path.extension()
        .and_then(OsStr::to_str)
        .is_some_and(|extension| matches!(extension.to_lowercase().as_str(), "md" | "markdown"))
}

fn normalize_open_argument(raw: &str, cwd: &Path) -> Option<String> {
    let raw_path = PathBuf::from(raw);
    let candidate = if raw_path.is_absolute() {
        raw_path
    } else if let Ok(url) = Url::parse(raw) {
        if url.scheme() != "file" {
            return None;
        }
        url.to_file_path().ok()?
    } else {
        cwd.join(raw_path)
    };
    canonical_markdown_path(&candidate)
        .ok()
        .map(|path| path.to_string_lossy().into_owned())
}

fn collect_open_arguments<I, S>(arguments: I, cwd: &Path) -> Vec<String>
where
    I: IntoIterator<Item = S>,
    S: AsRef<str>,
{
    let mut paths = Vec::new();
    for argument in arguments {
        if let Some(path) = normalize_open_argument(argument.as_ref(), cwd)
            && !paths.contains(&path)
        {
            paths.push(path);
        }
    }
    paths
}

fn queue_open_files(app: &tauri::AppHandle, paths: Vec<String>) {
    if paths.is_empty() {
        return;
    }
    let state = app.state::<PendingOpenFiles>();
    if state.frontend_ready.load(Ordering::Acquire) {
        let _ = app.emit("open-files", paths);
        return;
    }
    let mut pending = state
        .paths
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    for path in &paths {
        if !pending.contains(path) {
            pending.push(path.clone());
        }
    }
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let cwd = std::env::current_dir().unwrap_or_default();
    let startup_arguments = std::env::args_os()
        .skip(1)
        .filter_map(|value| value.into_string().ok())
        .collect::<Vec<_>>();
    let pending = collect_open_arguments(startup_arguments, &cwd);

    let mut builder = tauri::Builder::default().manage(PendingOpenFiles {
        paths: Mutex::new(pending),
        frontend_ready: AtomicBool::new(false),
    });

    #[cfg(desktop)]
    {
        builder = builder.plugin(tauri_plugin_single_instance::init(|app, args, cwd| {
            let paths = collect_open_arguments(args.iter().skip(1), Path::new(&cwd));
            queue_open_files(app, paths);
            if let Some(window) = app.get_webview_window("main") {
                let _ = window.unminimize();
                let _ = window.show();
                let _ = window.set_focus();
            }
        }));
    }

    let app = builder
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_opener::init())
        .invoke_handler(tauri::generate_handler![
            read_markdown,
            write_markdown,
            scan_workspace,
            search_workspace,
            load_markdown_asset,
            drain_initial_open_files
        ])
        .build(tauri::generate_context!())
        .expect("error while building KaiMD");

    app.run(|_app, _event| {
        #[cfg(target_os = "macos")]
        if let tauri::RunEvent::Opened { urls } = _event {
            let cwd = std::env::current_dir().unwrap_or_default();
            let paths = collect_open_arguments(urls.iter().map(Url::as_str), &cwd);
            queue_open_files(_app, paths);
        }
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_utf8_bom_and_crlf() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("note.md");
        fs::write(
            &path,
            [b"\xEF\xBB\xBF".as_slice(), b"# Title\r\nBody\r\n"].concat(),
        )
        .unwrap();

        let document = read_markdown_file(&path).unwrap();
        assert!(document.has_utf8_bom);
        assert_eq!(document.newline_style, "crlf");
        assert_eq!(document.content, "# Title\nBody\n");
    }

    #[test]
    fn collects_only_existing_markdown_arguments() {
        let directory = tempfile::tempdir().unwrap();
        let markdown = directory.path().join("note.md");
        let text = directory.path().join("note.txt");
        fs::write(&markdown, "# Note").unwrap();
        fs::write(&text, "plain").unwrap();

        let markdown_argument = markdown.to_string_lossy().into_owned();
        let text_argument = text.to_string_lossy().into_owned();
        let values = collect_open_arguments(
            [markdown_argument.as_str(), text_argument.as_str()],
            directory.path(),
        );
        assert_eq!(
            values,
            vec![markdown.canonicalize().unwrap().to_string_lossy()]
        );
    }

    #[test]
    fn collects_file_urls_and_removes_duplicates() {
        let directory = tempfile::tempdir().unwrap();
        let markdown = directory.path().join("file url.md");
        fs::write(&markdown, "# Note").unwrap();
        let url = Url::from_file_path(&markdown).unwrap().to_string();
        let path = markdown.to_string_lossy().into_owned();

        let values = collect_open_arguments([url.as_str(), path.as_str()], directory.path());

        assert_eq!(values.len(), 1);
        assert_eq!(
            values[0],
            markdown.canonicalize().unwrap().to_string_lossy()
        );
    }

    #[test]
    fn scanner_ignores_hidden_and_non_markdown_files() {
        let directory = tempfile::tempdir().unwrap();
        fs::write(directory.path().join("README.md"), "# Readme").unwrap();
        fs::write(directory.path().join("notes.txt"), "ignore").unwrap();
        fs::write(directory.path().join(".hidden.md"), "ignore").unwrap();

        let nodes = scan_directory(directory.path()).unwrap();
        assert_eq!(nodes.len(), 1);
        assert_eq!(nodes[0].name, "README.md");
    }
}
