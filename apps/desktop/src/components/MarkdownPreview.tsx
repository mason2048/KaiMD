import { isValidElement, useEffect, useState, type ReactElement } from "react";
import ReactMarkdown, { type Components } from "react-markdown";
import rehypeHighlight from "rehype-highlight";
import remarkGfm from "remark-gfm";
import { openUrl } from "@tauri-apps/plugin-opener";
import { isTauri, loadMarkdownAsset } from "../lib/bridge";

interface MarkdownPreviewProps {
  source: string;
  documentPath: string;
  workspaceRoot: string;
}

const localImagePattern = /(!\[[^\]]*\]\()([^\s)]+)([^)]*\))/g;

async function resolveLocalImages(
  source: string,
  documentPath: string,
  workspaceRoot: string,
) {
  if (!isTauri()) return source;
  const matches = [...source.matchAll(localImagePattern)];
  if (!matches.length) return source;

  const replacements = await Promise.all(
    matches.map(async (match) => {
      const raw = match[2];
      if (/^(?:https?:|data:)/i.test(raw)) return [raw, raw] as const;
      try {
        return [raw, await loadMarkdownAsset(raw, documentPath, workspaceRoot)] as const;
      } catch {
        return [raw, raw] as const;
      }
    }),
  );
  const resolved = new Map(replacements);
  return source.replace(localImagePattern, (_match, prefix, raw, suffix) =>
    `${prefix}${resolved.get(raw) ?? raw}${suffix}`,
  );
}

const components: Components = {
  pre({ children, ...props }) {
    const child = isValidElement(children)
      ? (children as ReactElement<{ className?: string }>)
      : null;
    const language = child?.props.className
      ?.split(/\s+/)
      .find((name) => name.startsWith("language-"))
      ?.replace("language-", "");
    return (
      <pre {...props} className="preview-code-block" data-language={language}>
        {children}
      </pre>
    );
  },
  a({ href, children, ...props }) {
    return (
      <a
        {...props}
        href={href}
        onClick={(event) => {
          if (!href) return;
          event.preventDefault();
          if (/^https?:\/\//i.test(href)) {
            if (isTauri()) void openUrl(href);
            else window.open(href, "_blank", "noopener,noreferrer");
          }
        }}
      >
        {children}
      </a>
    );
  },
};

export function MarkdownPreview({
  source,
  documentPath,
  workspaceRoot,
}: MarkdownPreviewProps) {
  const [resolvedSource, setResolvedSource] = useState(source);

  useEffect(() => {
    let cancelled = false;
    void resolveLocalImages(source, documentPath, workspaceRoot).then((next) => {
      if (!cancelled) setResolvedSource(next);
    });
    return () => {
      cancelled = true;
    };
  }, [documentPath, source, workspaceRoot]);

  return (
    <article className="markdown-preview" aria-label="Markdown 预览">
      <ReactMarkdown
        remarkPlugins={[remarkGfm]}
        rehypePlugins={[[rehypeHighlight, { detect: false, ignoreMissing: true }]]}
        components={components}
      >
        {resolvedSource}
      </ReactMarkdown>
    </article>
  );
}
