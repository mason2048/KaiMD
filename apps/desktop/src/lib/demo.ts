import type { MarkdownDocumentModel, WorkspaceNode } from "../types";

export const demoDocument: MarkdownDocumentModel = {
  path: "/demo/README.md",
  name: "README.md",
  parent: "/demo",
  newlineStyle: "lf",
  hasUtf8Bom: false,
  savedContent: "",
  content: `# KaiMD Preview

一个原生、快速、本地优先的 **Markdown** 编辑器。

> 打开文件夹即可开始写作，文件始终留在本地。

## 今日清单

- [x] 跨平台 Markdown 编辑
- [x] GFM 即时预览
- [ ] 写下一篇好文档

### 能力

| 能力 | 状态 |
| --- | ---: |
| 自动保存 | ✅ |
| 工作区搜索 | ✅ |
| 安全预览 | ✅ |

### 示例代码

\`\`\`typescript
type Todo = { id: string; title: string; done: boolean };

function toggle(todo: Todo): Todo {
  return { ...todo, done: !todo.done };
}

const todos: Todo[] = [
  { id: "1", title: "学习 KaiMD", done: false },
  { id: "2", title: "写一篇文档", done: true },
];

console.log(todos.map(toggle));
\`\`\`
`,
};

demoDocument.savedContent = demoDocument.content;

export const demoWorkspace: WorkspaceNode[] = [
  { path: "/demo/README.md", name: "README.md", kind: "markdown", children: [] },
  { path: "/demo/Notes.md", name: "Notes.md", kind: "markdown", children: [] },
];
