# KaiMD

[English](README.md) | [简体中文](README.zh-CN.md)

[![Desktop CI](https://github.com/mason2048/KaiMD/actions/workflows/desktop-ci.yml/badge.svg)](https://github.com/mason2048/KaiMD/actions/workflows/desktop-ci.yml)
[![Release](https://img.shields.io/github/v/release/mason2048/KaiMD?include_prereleases)](https://github.com/mason2048/KaiMD/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

KaiMD 是一个面向 Windows 与 macOS 的开源、本地优先 Markdown 编辑器。它把
文稿保留在本机，以单窗口管理多个文件，并提供源码、分栏和预览三种模式。

![KaiMD 分栏编辑和预览界面](docs/assets/kaimd-editor.png)

> KaiMD 目前是尚未签名的 `0.1.x` Alpha 版本，仍可能存在不完善之处。请为重要
> 文稿保留备份。在引入代码签名以前，macOS Gatekeeper 和 Windows SmartScreen
> 可能会对下载的安装包显示警告。

## 功能

- Windows 与 macOS 共用的 Tauri 2 桌面应用
- Markdown 文件、文件夹工作区、文件树和工作区全文搜索
- CodeMirror 编辑器、GitHub Flavored Markdown 即时预览和语法高亮
- 清晰的行内代码及代码块样式，支持语言标识和长行横向滚动
- 650 ms 防抖自动保存，并保留 UTF-8 BOM 与 LF/CRLF 换行格式
- 单窗口文件处理：从系统再次打开 Markdown 时，加入当前侧栏并自动选中
- 会话恢复、本地图片安全预览和源码/分栏/预览快捷键

## 安装 Alpha 版本

预发布安装包会在人工冒烟测试通过后发布到
[Releases 页面](https://github.com/mason2048/KaiMD/releases)：

- macOS：支持 Apple Silicon 与 Intel 的 Universal `.dmg`
- Windows 11 x64：NSIS `.exe` 和 MSI `.msi`

发布文件包含 `SHA256SUMS.txt`。Alpha 安装包暂未进行 Apple 公证或代码签名；
绕过系统警告前，请先阅读对应版本的发布说明。

## 本地开发

需要 Node.js 20、通过 Corepack 使用的 pnpm 9.15.9、Rust 1.96.0，以及对应平台的
[Tauri 系统依赖](https://v2.tauri.app/start/prerequisites/)。

```bash
cd apps/desktop
corepack enable
pnpm install --frozen-lockfile
pnpm tauri dev
```

运行发布检查：

```bash
cd apps/desktop
pnpm check
pnpm check:version
pnpm licenses:check
pnpm tauri build --no-bundle
```

## 仓库结构

```text
apps/desktop/          跨平台应用（当前主线）
legacy/macos-native/   原 Swift/AppKit 实现（维护模式）
docs/                  架构、产品截图与设计资料
scripts/               仓库校验与第三方依赖清单工具
```

进一步信息见[架构说明](docs/ARCHITECTURE.md)、[路线图](ROADMAP.md)与
[更新记录](CHANGELOG.md)。

## 贡献与安全

欢迎提交 Issue 和聚焦的 Pull Request。开始前请阅读[贡献指南](CONTRIBUTING.md)、
[行为准则](CODE_OF_CONDUCT.md)和[安全策略](SECURITY.md)。安全漏洞请通过 GitHub
Private Vulnerability Reporting 私密报告。

KaiMD 使用 [MIT License](LICENSE)，依赖许可记录在
[第三方依赖声明](THIRD_PARTY_NOTICES.md)中。
