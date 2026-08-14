import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { listen } from "@tauri-apps/api/event";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { open } from "@tauri-apps/plugin-dialog";
import "highlight.js/styles/github.css";
import "./App.css";
import { MarkdownEditor } from "./components/MarkdownEditor";
import { MarkdownPreview } from "./components/MarkdownPreview";
import { Sidebar } from "./components/Sidebar";
import { StatusBar } from "./components/StatusBar";
import { Toolbar } from "./components/Toolbar";
import { Welcome } from "./components/Welcome";
import {
  drainInitialOpenFiles,
  isTauri,
  readMarkdown,
  scanWorkspace,
  searchWorkspace,
  writeMarkdown,
} from "./lib/bridge";
import { demoDocument, demoWorkspace } from "./lib/demo";
import {
  documentParentPath,
  editorMetrics,
  replaceOrAppendDocument,
  toDocumentModel,
} from "./lib/editor";
import type {
  EditorMode,
  MarkdownDocumentModel,
  SaveState,
  SidebarMode,
  WorkspaceNode,
  WorkspaceSearchResult,
} from "./types";

const SESSION_KEY = "kaimd.desktop.session.v1";
const MARKDOWN_FILTER = [{ name: "Markdown", extensions: ["md", "markdown"] }];

interface PersistedSession {
  paths: string[];
  currentPath?: string;
  workspaceRoot?: string;
  mode?: EditorMode;
  sidebarVisible?: boolean;
}

function parseSession(): PersistedSession {
  try {
    return JSON.parse(localStorage.getItem(SESSION_KEY) ?? "{}") as PersistedSession;
  } catch {
    return { paths: [] };
  }
}

function relativePath(path: string, root?: string) {
  if (!root || !path.startsWith(root)) return path;
  return path.slice(root.length).replace(/^[\\/]/, "") || path;
}

function App() {
  const browserDemo = !isTauri();
  const session = useMemo(parseSession, []);
  const [documents, setDocuments] = useState<MarkdownDocumentModel[]>(
    browserDemo ? [demoDocument] : [],
  );
  const [currentPath, setCurrentPath] = useState<string | undefined>(
    browserDemo ? demoDocument.path : undefined,
  );
  const [workspaceRoot, setWorkspaceRoot] = useState<string | undefined>(
    browserDemo ? demoDocument.parent : session.workspaceRoot,
  );
  const [nodes, setNodes] = useState<WorkspaceNode[]>(browserDemo ? demoWorkspace : []);
  const [mode, setMode] = useState<EditorMode>(session.mode ?? "split");
  const [sidebarMode, setSidebarMode] = useState<SidebarMode>("files");
  const [sidebarVisible, setSidebarVisible] = useState(session.sidebarVisible ?? true);
  const [saveStates, setSaveStates] = useState<Record<string, SaveState>>({});
  const [cursorOffset, setCursorOffset] = useState(0);
  const [searchResults, setSearchResults] = useState<WorkspaceSearchResult[]>([]);
  const [searchPending, setSearchPending] = useState(false);
  const [notice, setNotice] = useState<string | undefined>();
  const documentsRef = useRef(documents);
  const workspaceRootRef = useRef(workspaceRoot);
  const saveTimers = useRef(new Map<string, number>());
  const saveQueues = useRef(new Map<string, Promise<void>>());
  const saveVersions = useRef(new Map<string, number>());
  const searchSequence = useRef(0);

  const currentDocument = useMemo(
    () => documents.find((document) => document.path === currentPath),
    [currentPath, documents],
  );
  const metrics = useMemo(
    () => editorMetrics(currentDocument?.content ?? "", cursorOffset),
    [currentDocument?.content, cursorOffset],
  );

  useEffect(() => {
    documentsRef.current = documents;
  }, [documents]);

  useEffect(() => {
    workspaceRootRef.current = workspaceRoot;
  }, [workspaceRoot]);

  const refreshWorkspace = useCallback(async (root: string) => {
    if (!isTauri()) return;
    try {
      setNodes(await scanWorkspace(root));
    } catch (error) {
      setNotice(`无法读取工作区：${String(error)}`);
    }
  }, []);

  const openPaths = useCallback(
    async (paths: string[], root?: string) => {
      if (!paths.length || !isTauri()) return;
      const loaded = await Promise.allSettled(paths.map((path) => readMarkdown(path)));
      const readable = loaded.flatMap((result) =>
        result.status === "fulfilled" ? [toDocumentModel(result.value)] : [],
      );
      if (!readable.length) {
        setNotice("没有可读取的 Markdown 文件。");
        return;
      }
      setDocuments((current) => readable.reduce(replaceOrAppendDocument, current));
      const selected = readable.at(-1)!;
      const nextRoot = root ?? workspaceRootRef.current ?? selected.parent;
      setCurrentPath(selected.path);
      setWorkspaceRoot(nextRoot);
      setCursorOffset(0);
      setSidebarMode("files");
      setNotice(undefined);
      await refreshWorkspace(nextRoot);
    },
    [refreshWorkspace],
  );

  const saveDocument = useCallback((document: MarkdownDocumentModel) => {
    if (!isTauri()) return Promise.resolve();
    const version = (saveVersions.current.get(document.path) ?? 0) + 1;
    saveVersions.current.set(document.path, version);
    setSaveStates((states) => ({ ...states, [document.path]: "saving" }));
    const previous = saveQueues.current.get(document.path) ?? Promise.resolve();
    let operation: Promise<void>;
    operation = previous
      .catch(() => undefined)
      .then(async () => {
        try {
          await writeMarkdown(document);
          setDocuments((current) =>
            current.map((item) =>
              item.path === document.path && item.content === document.content
                ? { ...item, savedContent: document.content }
                : item,
            ),
          );
          if (saveVersions.current.get(document.path) === version) {
            setSaveStates((states) => ({ ...states, [document.path]: "saved" }));
          }
        } catch (error) {
          if (saveVersions.current.get(document.path) === version) {
            setSaveStates((states) => ({ ...states, [document.path]: "error" }));
            setNotice(`保存失败：${String(error)}`);
          }
        }
      })
      .finally(() => {
        if (saveQueues.current.get(document.path) === operation) {
          saveQueues.current.delete(document.path);
        }
      });
    saveQueues.current.set(document.path, operation);
    return operation;
  }, []);

  const scheduleSave = useCallback(
    (document: MarkdownDocumentModel) => {
      const previous = saveTimers.current.get(document.path);
      if (previous) window.clearTimeout(previous);
      setSaveStates((states) => ({ ...states, [document.path]: "saving" }));
      const timer = window.setTimeout(() => {
        saveTimers.current.delete(document.path);
        void saveDocument(document);
      }, 650);
      saveTimers.current.set(document.path, timer);
    },
    [saveDocument],
  );

  const updateContent = useCallback(
    (content: string) => {
      if (!currentDocument) return;
      const next = { ...currentDocument, content };
      setDocuments((current) =>
        current.map((document) => (document.path === next.path ? next : document)),
      );
      scheduleSave(next);
    },
    [currentDocument, scheduleSave],
  );

  const chooseFiles = useCallback(async () => {
    if (!isTauri()) return;
    const selected = await open({ multiple: true, filters: MARKDOWN_FILTER });
    const paths = Array.isArray(selected) ? selected : selected ? [selected] : [];
    await openPaths(paths);
  }, [openPaths]);

  const chooseFolder = useCallback(async () => {
    if (!isTauri()) return;
    const selected = await open({ directory: true, multiple: false });
    if (typeof selected !== "string") return;
    setWorkspaceRoot(selected);
    setSidebarMode("files");
    await refreshWorkspace(selected);
  }, [refreshWorkspace]);

  const closeDocument = useCallback(
    (path: string) => {
      const timer = saveTimers.current.get(path);
      if (timer) {
        window.clearTimeout(timer);
        saveTimers.current.delete(path);
      }
      const closing = documentsRef.current.find((item) => item.path === path);
      if (closing && closing.content !== closing.savedContent) void saveDocument(closing);
      setDocuments((current) => {
        const index = current.findIndex((document) => document.path === path);
        const next = current.filter((document) => document.path !== path);
        if (currentPath === path) {
          setCurrentPath(next[Math.min(Math.max(index, 0), next.length - 1)]?.path);
        }
        return next;
      });
    },
    [currentPath, saveDocument],
  );

  const search = useCallback(
    async (query: string) => {
      const sequence = ++searchSequence.current;
      if (!query.trim() || !workspaceRoot || !isTauri()) {
        setSearchResults([]);
        setSearchPending(false);
        return;
      }
      setSearchPending(true);
      await new Promise((resolve) => window.setTimeout(resolve, 180));
      try {
        const results = await searchWorkspace(workspaceRoot, query);
        if (sequence === searchSequence.current) setSearchResults(results);
      } catch (error) {
        if (sequence === searchSequence.current) setNotice(`搜索失败：${String(error)}`);
      } finally {
        if (sequence === searchSequence.current) setSearchPending(false);
      }
    },
    [workspaceRoot],
  );

  useEffect(() => {
    if (!isTauri()) return;
    let cancelled = false;
    let stopListening: (() => void) | undefined;
    void (async () => {
      stopListening = await listen<string[]>("open-files", (event) => {
        void openPaths(event.payload);
      });
      if (cancelled) {
        stopListening();
        return;
      }
      const systemPaths = await drainInitialOpenFiles();
      if (cancelled) return;
      if (systemPaths.length) {
        await openPaths(systemPaths, documentParentPath(systemPaths.at(-1)!));
      } else if (session.paths?.length) {
        await openPaths(session.paths, session.workspaceRoot);
        if (session.currentPath) setCurrentPath(session.currentPath);
      }
    })();
    return () => {
      cancelled = true;
      stopListening?.();
    };
  }, [openPaths, session.currentPath, session.paths, session.workspaceRoot]);

  useEffect(() => {
    const next: PersistedSession = {
      paths: documents.map((document) => document.path),
      currentPath,
      workspaceRoot,
      mode,
      sidebarVisible,
    };
    localStorage.setItem(SESSION_KEY, JSON.stringify(next));
  }, [currentPath, documents, mode, sidebarVisible, workspaceRoot]);

  useEffect(() => {
    if (!isTauri()) return;
    const title = currentDocument ? `${currentDocument.name} — KaiMD` : "KaiMD";
    void getCurrentWindow().setTitle(title);
  }, [currentDocument]);

  useEffect(() => {
    const handleKeyDown = (event: KeyboardEvent) => {
      const command = event.metaKey || event.ctrlKey;
      if (!command) return;
      if (event.key.toLowerCase() === "o") {
        event.preventDefault();
        void chooseFiles();
      } else if (event.key.toLowerCase() === "s") {
        event.preventDefault();
        if (currentDocument) void saveDocument(currentDocument);
      } else if (["1", "2", "3"].includes(event.key)) {
        event.preventDefault();
        const modes: Record<string, EditorMode> = {
          "1": "source",
          "2": "split",
          "3": "preview",
        };
        setMode(modes[event.key]);
      }
    };
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [chooseFiles, currentDocument, saveDocument]);

  useEffect(
    () => () => {
      saveTimers.current.forEach((timer) => window.clearTimeout(timer));
    },
    [],
  );

  const saveState = currentDocument
    ? saveStates[currentDocument.path] ??
      (currentDocument.content === currentDocument.savedContent ? "saved" : "saving")
    : "saved";

  return (
    <main className="app-shell">
      {sidebarVisible ? (
        <Sidebar
          documents={documents}
          currentPath={currentPath}
          workspaceRoot={workspaceRoot}
          nodes={nodes}
          mode={sidebarMode}
          searchResults={searchResults}
          searchPending={searchPending}
          onModeChange={setSidebarMode}
          onSearch={(query) => void search(query)}
          onOpenPath={(path) => {
            if (documents.some((document) => document.path === path)) setCurrentPath(path);
            else void openPaths([path]);
          }}
          onCloseDocument={closeDocument}
          onOpenFile={() => void chooseFiles()}
          onOpenFolder={() => void chooseFolder()}
        />
      ) : null}

      <section className="workspace">
        <Toolbar
          documentName={currentDocument?.name}
          relativePath={
            currentDocument ? relativePath(currentDocument.path, workspaceRoot) : undefined
          }
          mode={mode}
          saveState={saveState}
          sidebarVisible={sidebarVisible}
          onModeChange={setMode}
          onToggleSidebar={() => setSidebarVisible((visible) => !visible)}
        />

        {notice ? (
          <button className="notice" type="button" onClick={() => setNotice(undefined)}>
            {notice}
          </button>
        ) : null}

        <div className={`editor-stage editor-stage--${mode}`}>
          {currentDocument ? (
            <>
              {mode !== "preview" ? (
                <section className="source-pane">
                  <MarkdownEditor
                    value={currentDocument.content}
                    onChange={updateContent}
                    onCursorChange={setCursorOffset}
                  />
                </section>
              ) : null}
              {mode !== "source" ? (
                <section className="preview-pane">
                  <MarkdownPreview
                    source={currentDocument.content}
                    documentPath={currentDocument.path}
                    workspaceRoot={workspaceRoot ?? documentParentPath(currentDocument.path)}
                  />
                </section>
              ) : null}
            </>
          ) : (
            <Welcome
              onOpenFile={() => void chooseFiles()}
              onOpenFolder={() => void chooseFolder()}
            />
          )}
        </div>

        <StatusBar metrics={metrics} document={currentDocument} />
      </section>
    </main>
  );
}

export default App;
