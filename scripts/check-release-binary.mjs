import { readFileSync } from "node:fs";

const markers = [
  { label: "macOS user path", pattern: /\/Users\//i },
  { label: "Linux runner path", pattern: /\/home\/runner\//i },
  { label: "Windows user or workspace path", pattern: /[a-z]:\\(?:Users|a)\\/i },
  { label: "GitHub token", pattern: /(?:gho_|ghp_|github_pat_)[a-z0-9_]+/i },
  { label: "private key", pattern: /BEGIN [A-Z ]*PRIVATE KEY/i },
];

function findMarker(buffer) {
  const views = [buffer.toString("latin1"), buffer.toString("utf16le")];
  for (const text of views) {
    for (const marker of markers) {
      if (marker.pattern.test(text)) return marker.label;
    }
  }
  return undefined;
}

if (process.argv[2] === "--self-test") {
  const unsafeSamples = [
    Buffer.from("/Users/runner/.cargo/source.rs"),
    Buffer.from("D:\\a\\KaiMD\\src\\main.rs"),
    Buffer.from("github_pat_example", "utf16le"),
  ];
  if (unsafeSamples.some((sample) => !findMarker(sample))) {
    console.error("Release binary scanner failed to detect a test marker.");
    process.exit(1);
  }
  if (findMarker(Buffer.from("workspace/kaimd/release"))) {
    console.error("Release binary scanner rejected a safe relative path.");
    process.exit(1);
  }
  console.log("Release binary scanner self-test passed.");
  process.exit(0);
}

const paths = process.argv.slice(2);
if (paths.length === 0) {
  console.error("Pass at least one release binary to scan.");
  process.exit(1);
}

for (const path of paths) {
  const marker = findMarker(readFileSync(path));
  if (marker) {
    console.error(`${path}: found ${marker}.`);
    process.exitCode = 1;
  }
}

if (!process.exitCode) {
  console.log(`Release binary scan passed for ${paths.length} file(s).`);
}
