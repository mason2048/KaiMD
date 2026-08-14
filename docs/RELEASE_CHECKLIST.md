# Alpha Release Checklist

Use one tagged commit for every check. Do not publish the draft GitHub release
until all applicable boxes are complete.

## Automated evidence

- [ ] `CI Gate` is green on the exact tag commit.
- [ ] Draft release workflow completed on macOS and Windows.
- [ ] macOS DMG contains a Universal binary with `arm64` and `x86_64`.
- [ ] Windows x64 NSIS EXE and MSI artifacts are present.
- [ ] `SHA256SUMS.txt` verifies every downloadable file.
- [ ] Dependency license, production audit, and high-confidence secret checks pass.

## macOS smoke test

- [ ] Install and launch on Apple Silicon.
- [ ] Install and launch on Intel hardware or an independent Intel environment.
- [ ] Record the expected unsigned Gatekeeper warning in the release notes.
- [ ] Open Markdown from Finder and Open With while KaiMD is closed.
- [ ] With KaiMD running, open a second file and confirm it appears in the
      existing window sidebar, becomes selected, and no second window remains.
- [ ] Edit, autosave, reopen, search, switch files, preview code blocks, and
      horizontally scroll a long code line.
- [ ] Uninstall and reinstall the same candidate.

## Windows 11 x64 smoke test

- [ ] Install both NSIS and MSI packages independently.
- [ ] Record the expected unsigned SmartScreen warning in the release notes.
- [ ] Open Markdown from Explorer and Open With while KaiMD is closed.
- [ ] With KaiMD running, open a second file and confirm it appears in the
      existing window sidebar, becomes selected, and no second window remains.
- [ ] Edit, autosave, reopen, search, switch files, preview code blocks, and
      horizontally scroll a long code line.
- [ ] Uninstall each package and confirm user documents remain untouched.

## Publication

- [ ] Download the draft assets and verify their SHA-256 checksums.
- [ ] Confirm no source paths, credentials, private documents, or debug data are included.
- [ ] Add platform-specific limitations and evidence to the release notes.
- [ ] Manually publish the GitHub Draft Pre-release.
