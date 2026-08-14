import { invoke } from "@tauri-apps/api/core";
import type {
  MarkdownFilePayload,
  WorkspaceNode,
  WorkspaceSearchResult,
} from "../types";

export const isTauri = () => "__TAURI_INTERNALS__" in window;

export async function readMarkdown(path: string) {
  return invoke<MarkdownFilePayload>("read_markdown", { path });
}

export async function writeMarkdown(document: MarkdownFilePayload) {
  return invoke<void>("write_markdown", {
    path: document.path,
    content: document.content,
    newlineStyle: document.newlineStyle,
    hasUtf8Bom: document.hasUtf8Bom,
  });
}

export async function scanWorkspace(root: string) {
  return invoke<WorkspaceNode[]>("scan_workspace", { root });
}

export async function searchWorkspace(root: string, query: string) {
  return invoke<WorkspaceSearchResult[]>("search_workspace", { root, query });
}

export async function drainInitialOpenFiles() {
  return invoke<string[]>("drain_initial_open_files");
}

export async function loadMarkdownAsset(
  source: string,
  documentPath: string,
  workspaceRoot: string,
) {
  return invoke<string>("load_markdown_asset", {
    source,
    documentPath,
    workspaceRoot,
  });
}
