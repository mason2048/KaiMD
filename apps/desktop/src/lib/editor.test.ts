import { describe, expect, it } from "vitest";
import {
  documentParentPath,
  editorMetrics,
  replaceOrAppendDocument,
  toDocumentModel,
} from "./editor";

describe("editor utilities", () => {
  it("reports words, characters and a unicode-safe cursor position", () => {
    expect(editorMetrics("KaiMD 中文\n🙂 ok", 12)).toEqual({
      words: 3,
      characters: 13,
      line: 2,
      column: 3,
    });
  });

  it("replaces an already opened path instead of duplicating it", () => {
    const original = toDocumentModel({
      path: "/notes/a.md",
      name: "a.md",
      parent: "/notes",
      content: "old",
      newlineStyle: "lf",
      hasUtf8Bom: false,
    });
    const updated = { ...original, content: "new" };

    expect(replaceOrAppendDocument([original], updated)).toEqual([updated]);
  });

  it("selects the containing folder for cold-opened files on both platforms", () => {
    expect(documentParentPath("/Users/demo/Notes/a.md")).toBe("/Users/demo/Notes");
    expect(documentParentPath("C:\\Users\\demo\\Notes\\a.md")).toBe(
      "C:\\Users\\demo\\Notes",
    );
  });
});
