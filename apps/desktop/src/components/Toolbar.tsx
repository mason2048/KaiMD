import { PanelLeft } from "lucide-react";
import type { EditorMode, SaveState } from "../types";

interface ToolbarProps {
  documentName?: string;
  relativePath?: string;
  mode: EditorMode;
  saveState: SaveState;
  sidebarVisible: boolean;
  onModeChange: (mode: EditorMode) => void;
  onToggleSidebar: () => void;
}

const modes: { value: EditorMode; label: string }[] = [
  { value: "source", label: "源码" },
  { value: "split", label: "分栏" },
  { value: "preview", label: "预览" },
];

export function Toolbar({
  documentName,
  relativePath,
  mode,
  saveState,
  sidebarVisible,
  onModeChange,
  onToggleSidebar,
}: ToolbarProps) {
  const saveLabel =
    saveState === "saving" ? "保存中…" : saveState === "error" ? "保存失败" : "已保存";

  return (
    <header className="toolbar">
      <button
        className="icon-button"
        type="button"
        aria-label={sidebarVisible ? "隐藏侧栏" : "显示侧栏"}
        title={sidebarVisible ? "隐藏侧栏" : "显示侧栏"}
        onClick={onToggleSidebar}
      >
        <PanelLeft size={17} strokeWidth={1.8} />
      </button>

      <div className="document-heading">
        <strong>{documentName ?? "KaiMD"}</strong>
        {relativePath ? <span>{relativePath}</span> : null}
      </div>

      <div className="mode-switch" aria-label="编辑器模式">
        {modes.map((item) => (
          <button
            key={item.value}
            type="button"
            className={mode === item.value ? "is-active" : ""}
            aria-pressed={mode === item.value}
            onClick={() => onModeChange(item.value)}
          >
            {item.label}
          </button>
        ))}
      </div>

      <span className={`save-state save-state--${saveState}`}>{saveLabel}</span>
    </header>
  );
}
