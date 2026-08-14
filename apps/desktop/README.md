# KaiMD Desktop

KaiMD 的 Windows/macOS 共用桌面应用，技术栈为 Tauri 2、React、TypeScript、CodeMirror 和 Rust。

```bash
pnpm install
pnpm tauri dev
pnpm check
pnpm tauri build
```

前端位于 `src/`，本地文件和系统生命周期位于 `src-tauri/src/`。架构及安全边界见仓库根目录的 `docs/ARCHITECTURE.md`。
