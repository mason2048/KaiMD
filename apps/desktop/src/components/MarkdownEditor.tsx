import { useMemo } from "react";
import CodeMirror from "@uiw/react-codemirror";
import { markdown } from "@codemirror/lang-markdown";
import { EditorView } from "@codemirror/view";

interface MarkdownEditorProps {
  value: string;
  onChange: (value: string) => void;
  onCursorChange: (offset: number) => void;
}

export function MarkdownEditor({
  value,
  onChange,
  onCursorChange,
}: MarkdownEditorProps) {
  const extensions = useMemo(
    () => [
      markdown(),
      EditorView.updateListener.of((update) => {
        if (update.selectionSet || update.docChanged) {
          onCursorChange(update.state.selection.main.head);
        }
      }),
      EditorView.theme({
        "&": { height: "100%", fontSize: "13px" },
        ".cm-scroller": {
          fontFamily:
            'ui-monospace, "SFMono-Regular", "Cascadia Code", Consolas, monospace',
          lineHeight: "1.68",
          overflow: "auto",
        },
        ".cm-content": { padding: "18px 0 72px" },
        ".cm-gutters": {
          backgroundColor: "#fbfbfc",
          borderRight: "1px solid #ececf0",
          color: "#92929a",
        },
        ".cm-activeLine, .cm-activeLineGutter": {
          backgroundColor: "#f4f7fd",
        },
        ".cm-focused": { outline: "none" },
      }),
    ],
    [onCursorChange],
  );

  return (
    <CodeMirror
      aria-label="Markdown 源码编辑器"
      className="source-editor"
      value={value}
      height="100%"
      extensions={extensions}
      onChange={onChange}
      basicSetup={{
        bracketMatching: true,
        closeBrackets: true,
        foldGutter: false,
        highlightActiveLine: true,
        highlightSelectionMatches: true,
        indentOnInput: true,
        lineNumbers: true,
      }}
    />
  );
}
