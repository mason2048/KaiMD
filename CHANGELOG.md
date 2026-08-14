# Changelog

All notable changes to KaiMD are documented in this file. The project follows
[Semantic Versioning](https://semver.org/), with pre-1.0 compatibility described
in each release note.

## [Unreleased]

## [0.1.0-alpha.1] - 2026-08-14

### Added

- Cross-platform Tauri 2 desktop application for Windows and macOS.
- Markdown editing, split preview, syntax-highlighted code blocks, workspaces,
  search, autosave, and session restoration.
- Single-instance operating-system file opening that routes additional Markdown
  files into the existing window.
- Cross-platform CI and draft pre-release packaging for macOS Universal and
  Windows x64 installers.

### Changed

- Moved the original Swift/AppKit implementation to `legacy/macos-native/` and
  placed it in maintenance mode.

### Known limitations

- Alpha installers are not signed or notarized.
- Windows installer and real Intel Mac smoke tests are required before promoting
  the draft pre-release.

[Unreleased]: https://github.com/mason2048/KaiMD/compare/v0.1.0-alpha.1...HEAD
[0.1.0-alpha.1]: https://github.com/mason2048/KaiMD/releases/tag/v0.1.0-alpha.1
