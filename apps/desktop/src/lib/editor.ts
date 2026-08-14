import type { EditorMetrics, MarkdownDocumentModel } from "../types";

export function editorMetrics(
  content: string,
  cursorOffset: number,
): EditorMetrics {
  const safeOffset = Math.max(0, Math.min(cursorOffset, content.length));
  const beforeCursor = content.slice(0, safeOffset);
  const lines = beforeCursor.split("\n");
  const words =
    content.match(/[\p{L}\p{N}_]+(?:['’-][\p{L}\p{N}_]+)*/gu)?.length ?? 0;

  return {
    words,
    characters: Array.from(content).length,
    line: lines.length,
    column: Array.from(lines.at(-1) ?? "").length + 1,
  };
}

export function toDocumentModel(
  payload: Omit<MarkdownDocumentModel, "savedContent">,
): MarkdownDocumentModel {
  return { ...payload, savedContent: payload.content };
}

export function replaceOrAppendDocument(
  documents: MarkdownDocumentModel[],
  next: MarkdownDocumentModel,
) {
  const index = documents.findIndex((document) => document.path === next.path);
  if (index === -1) return [...documents, next];
  return documents.map((document, currentIndex) =>
    currentIndex === index ? next : document,
  );
}

export function documentParentPath(path: string) {
  const normalized = path.replace(/[\\/]+$/, "");
  const separator = Math.max(
    normalized.lastIndexOf("/"),
    normalized.lastIndexOf("\\"),
  );
  return separator > 0 ? normalized.slice(0, separator) : normalized;
}
