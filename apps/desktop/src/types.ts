export type EditorMode = "source" | "split" | "preview";
export type SidebarMode = "files" | "search";
export type SaveState = "saved" | "saving" | "error";

export interface MarkdownDocumentModel {
  path: string;
  name: string;
  parent: string;
  content: string;
  savedContent: string;
  newlineStyle: "lf" | "crlf";
  hasUtf8Bom: boolean;
}

export interface MarkdownFilePayload {
  path: string;
  name: string;
  parent: string;
  content: string;
  newlineStyle: "lf" | "crlf";
  hasUtf8Bom: boolean;
}

export interface WorkspaceNode {
  path: string;
  name: string;
  kind: "directory" | "markdown";
  children: WorkspaceNode[];
}

export interface WorkspaceSearchResult {
  path: string;
  name: string;
  relativePath: string;
  line: number | null;
  preview: string;
}

export interface EditorMetrics {
  words: number;
  characters: number;
  line: number;
  column: number;
}
