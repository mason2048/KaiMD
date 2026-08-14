# KaiMD Native macOS Legacy Implementation

This directory preserves KaiMD's original Swift/AppKit implementation for
behavior comparison and regression tests. It is in maintenance mode; new
cross-platform features belong in `apps/desktop/`.

From the repository root:

```bash
swift test --package-path legacy/macos-native --no-parallel
```

The packaging helpers in `scripts/` remain for historical local builds and are
not used by the cross-platform release workflow.
