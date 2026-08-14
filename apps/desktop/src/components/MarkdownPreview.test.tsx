import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { MarkdownPreview } from "./MarkdownPreview";

describe("MarkdownPreview", () => {
  it("renders GFM and labels fenced code without wrapping long lines", () => {
    const html = renderToStaticMarkup(
      <MarkdownPreview
        source={"| A | B |\n| - | - |\n| 1 | 2 |\n\n```typescript\nconst answer = 42;\n```"}
        documentPath="/demo/README.md"
        workspaceRoot="/demo"
      />,
    );

    expect(html).toContain("<table>");
    expect(html).toContain('class="preview-code-block"');
    expect(html).toContain('data-language="typescript"');
    expect(html).toContain("hljs-keyword");
  });
});
