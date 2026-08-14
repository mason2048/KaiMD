# 为 KaiMD 贡献

感谢你帮助 KaiMD 变得更稳定、更易用。项目优先接受可验证的小步改进，并尽量保持本地优先、跨平台和界面克制。

## 开始之前

1. 搜索已有 issue，避免重复工作；较大的功能先创建讨论或 issue。
2. 从最新代码创建独立分支，不要在同一变更中混入无关格式化。
3. 安装 Node.js 20+、pnpm 9+、Rust stable 和 Tauri 对应平台依赖。
4. 在 `apps/desktop` 运行 `pnpm install` 和 `pnpm check`。

## 代码约定

- React/TypeScript 负责界面和交互，Rust 负责本地文件、系统事件和安全边界。
- Windows 与 macOS 使用同一功能语义；平台差异集中在 Tauri/Rust 层。
- 不上传真实文稿、凭据、绝对用户路径或构建产物。
- 文件写入必须保留换行风格和 UTF-8 BOM；预览不得任意读取工作区外资源。
- 新行为需要测试；涉及界面的改动附上截图，涉及系统打开的改动说明实际生命周期验证方法。

## 提交 Pull Request

PR 请说明：问题、实现、验证结果、平台差异与已知限制。合并前至少应通过：

```bash
cd apps/desktop
pnpm check
pnpm tauri build --no-bundle
```

macOS 原生实现如有改动，还需运行：

```bash
swift test --package-path legacy/macos-native --no-parallel
```
