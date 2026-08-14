import { FileText, FolderOpen } from "lucide-react";

interface WelcomeProps {
  onOpenFile: () => void;
  onOpenFolder: () => void;
}

export function Welcome({ onOpenFile, onOpenFolder }: WelcomeProps) {
  return (
    <section className="welcome-state">
      <div className="welcome-mark" aria-hidden="true">
        K
      </div>
      <h1>开始使用 KaiMD</h1>
      <p>打开本地 Markdown 文件或文件夹，内容始终保存在你的设备上。</p>
      <div className="welcome-actions">
        <button className="primary-button" type="button" onClick={onOpenFile}>
          <FileText size={17} />
          打开 Markdown
        </button>
        <button className="secondary-button" type="button" onClick={onOpenFolder}>
          <FolderOpen size={17} />
          打开文件夹
        </button>
      </div>
      <p className="welcome-shortcuts">Ctrl/⌘ O 打开文件 · Ctrl/⌘ 1–3 切换模式</p>
    </section>
  );
}
