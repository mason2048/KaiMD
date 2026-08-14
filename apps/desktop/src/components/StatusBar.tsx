import type { EditorMetrics, MarkdownDocumentModel } from "../types";

interface StatusBarProps {
  metrics: EditorMetrics;
  document?: MarkdownDocumentModel;
}

export function StatusBar({ metrics, document }: StatusBarProps) {
  return (
    <footer className="status-bar">
      <span>{metrics.words} 词</span>
      <span>{metrics.characters} 字符</span>
      <span className="status-spacer" />
      <span>行 {metrics.line}，列 {metrics.column}</span>
      <span>{document?.newlineStyle === "crlf" ? "CRLF" : "LF"}</span>
      <span>{document?.hasUtf8Bom ? "UTF-8 BOM" : "UTF-8"}</span>
    </footer>
  );
}
