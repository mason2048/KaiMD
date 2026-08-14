import { useMemo, useState } from "react";
import {
  ChevronDown,
  ChevronRight,
  FileText,
  Folder,
  FolderOpen,
  Plus,
  Search,
  X,
} from "lucide-react";
import type {
  MarkdownDocumentModel,
  SidebarMode,
  WorkspaceNode,
  WorkspaceSearchResult,
} from "../types";

interface SidebarProps {
  documents: MarkdownDocumentModel[];
  currentPath?: string;
  workspaceRoot?: string;
  nodes: WorkspaceNode[];
  mode: SidebarMode;
  searchResults: WorkspaceSearchResult[];
  searchPending: boolean;
  onModeChange: (mode: SidebarMode) => void;
  onSearch: (query: string) => void;
  onOpenPath: (path: string) => void;
  onCloseDocument: (path: string) => void;
  onOpenFile: () => void;
  onOpenFolder: () => void;
}

function lastPathComponent(path?: string) {
  if (!path) return "工作区";
  return path.split(/[\\/]/).filter(Boolean).at(-1) ?? path;
}

function TreeRow({
  node,
  depth,
  currentPath,
  onOpen,
}: {
  node: WorkspaceNode;
  depth: number;
  currentPath?: string;
  onOpen: (path: string) => void;
}) {
  const [expanded, setExpanded] = useState(true);
  if (node.kind === "directory") {
    return (
      <>
        <button
          type="button"
          className="tree-row"
          style={{ paddingLeft: 9 + depth * 14 }}
          onClick={() => setExpanded((value) => !value)}
        >
          {expanded ? <ChevronDown size={13} /> : <ChevronRight size={13} />}
          {expanded ? <FolderOpen size={15} /> : <Folder size={15} />}
          <span>{node.name}</span>
        </button>
        {expanded
          ? node.children.map((child) => (
              <TreeRow
                key={child.path}
                node={child}
                depth={depth + 1}
                currentPath={currentPath}
                onOpen={onOpen}
              />
            ))
          : null}
      </>
    );
  }

  return (
    <button
      type="button"
      className={`tree-row tree-row--file ${currentPath === node.path ? "is-selected" : ""}`}
      style={{ paddingLeft: 24 + depth * 14 }}
      onClick={() => onOpen(node.path)}
    >
      <FileText size={15} />
      <span>{node.name}</span>
    </button>
  );
}

export function Sidebar({
  documents,
  currentPath,
  workspaceRoot,
  nodes,
  mode,
  searchResults,
  searchPending,
  onModeChange,
  onSearch,
  onOpenPath,
  onCloseDocument,
  onOpenFile,
  onOpenFolder,
}: SidebarProps) {
  const [query, setQuery] = useState("");
  const workspaceName = useMemo(
    () => lastPathComponent(workspaceRoot),
    [workspaceRoot],
  );

  return (
    <aside className="sidebar">
      <div className="sidebar-brand">KaiMD</div>

      <div className="workspace-heading">
        <Folder size={17} />
        <strong>{workspaceName}</strong>
        <button type="button" title="打开文件夹" aria-label="打开文件夹" onClick={onOpenFolder}>
          <FolderOpen size={15} />
        </button>
        <button type="button" title="打开 Markdown" aria-label="打开 Markdown" onClick={onOpenFile}>
          <Plus size={16} />
        </button>
      </div>

      <div className="sidebar-switch" aria-label="侧栏内容">
        <button
          type="button"
          className={mode === "files" ? "is-active" : ""}
          onClick={() => onModeChange("files")}
        >
          文件
        </button>
        <button
          type="button"
          className={mode === "search" ? "is-active" : ""}
          onClick={() => onModeChange("search")}
        >
          搜索
        </button>
      </div>

      <div className="sidebar-scroll">
        {mode === "files" ? (
          <>
            <section className="sidebar-section">
              <h2>已打开</h2>
              {documents.length ? (
                documents.map((document) => (
                  <div
                    key={document.path}
                    className={`open-file-row ${currentPath === document.path ? "is-selected" : ""}`}
                  >
                    <button type="button" onClick={() => onOpenPath(document.path)}>
                      <FileText size={15} />
                      <span>{document.name}</span>
                    </button>
                    <button
                      type="button"
                      className="close-file"
                      aria-label={`关闭 ${document.name}`}
                      title={`关闭 ${document.name}`}
                      onClick={() => onCloseDocument(document.path)}
                    >
                      <X size={13} />
                    </button>
                  </div>
                ))
              ) : (
                <p className="sidebar-empty">尚未打开文件</p>
              )}
            </section>

            {nodes.length ? <div className="sidebar-divider" /> : null}
            <section className="file-tree" aria-label="工作区文件">
              {nodes.map((node) => (
                <TreeRow
                  key={node.path}
                  node={node}
                  depth={0}
                  currentPath={currentPath}
                  onOpen={onOpenPath}
                />
              ))}
            </section>
          </>
        ) : (
          <section className="search-panel">
            <label className="search-box">
              <Search size={15} />
              <input
                autoFocus
                value={query}
                placeholder="搜索文件和正文"
                onChange={(event) => {
                  const next = event.currentTarget.value;
                  setQuery(next);
                  onSearch(next);
                }}
              />
              {query ? (
                <button
                  type="button"
                  aria-label="清除搜索"
                  onClick={() => {
                    setQuery("");
                    onSearch("");
                  }}
                >
                  <X size={13} />
                </button>
              ) : null}
            </label>

            {searchPending ? <p className="sidebar-empty">正在搜索…</p> : null}
            {!searchPending && query && !searchResults.length ? (
              <p className="sidebar-empty">没有找到结果</p>
            ) : null}
            <div className="search-results">
              {searchResults.map((result) => (
                <button key={`${result.path}:${result.line ?? 0}`} type="button" onClick={() => onOpenPath(result.path)}>
                  <span className="search-result-title">
                    <FileText size={14} />
                    {result.relativePath}
                    {result.line ? <small>L{result.line}</small> : null}
                  </span>
                  <span className="search-result-preview">{result.preview}</span>
                </button>
              ))}
            </div>
          </section>
        )}
      </div>

      <div className="sidebar-footer" title={workspaceRoot}>
        <span className="drive-dot" />
        <span>{workspaceRoot ?? "未选择工作区"}</span>
      </div>
    </aside>
  );
}
