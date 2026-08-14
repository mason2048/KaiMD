# KaiMD 跨平台架构

## 目标

KaiMD 使用一套界面和业务语义覆盖 Windows 与 macOS，并把平台差异限制在 Tauri/Rust 系统层。文稿始终是用户可直接访问的普通 Markdown 文件。

## 分层

- `apps/desktop/src/`：React、TypeScript、CodeMirror、Markdown 预览、工作区和会话状态。
- `apps/desktop/src-tauri/src/`：文件读取/保存、目录扫描、搜索、本地图片安全加载、进程与系统打开事件。
- `legacy/macos-native/Sources/KaiMD/`：原 macOS 原生实现。维护期用于行为对照，不与跨平台版本共享运行时。

前端不能直接读取任意文件。所有本地访问经 Tauri command 进入 Rust 层，后者校验文件扩展名、路径、大小和工作区边界。

## 系统打开链路

```text
Finder / Windows Explorer / Open With / 命令行第二次启动
                         │
                         ▼
             Tauri single-instance / Opened
                         │
                         ▼
            Rust 规范化并校验 Markdown 路径
                         │
                         ▼
        open-files 事件 → React 已有主窗口文件列表
                         │
                         ▼
              去重、加入列表、选中并显示
```

冷启动时路径先进入 `PendingOpenFiles`，WebView 完成初始化后主动取走；热启动时事件直接送到已有窗口。第二个进程只负责转交参数并退出。

## 文稿完整性

读取时统一为前端 LF 文本，同时记录原始 LF/CRLF 和 UTF-8 BOM。保存时恢复这些属性。当前只支持 UTF-8；遇到其他编码会明确报错，不做有损猜测。

## 预览安全

Markdown HTML 由 React 组件生成，不执行文稿中的脚本。外部 URL 交给系统浏览器；本地图片必须是相对路径、位于当前工作区、属于图片 MIME，且不超过 10 MB。

## 后续演进原则

新增文件系统能力优先放在 Rust 命令中并测试边界；新增平台分支必须附 Windows/macOS 验证。大型能力先写 RFC，避免把插件、云同步或账号系统直接耦合到编辑器核心。
