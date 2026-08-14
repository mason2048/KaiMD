import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const files = execFileSync("git", ["ls-files", "-z"], {
  cwd: root,
  encoding: "utf8",
}).split("\0").filter(Boolean);

const patterns = [
  ["private key", /-----BEGIN (?:RSA |EC |OPENSSH |DSA |PGP )?PRIVATE KEY-----/],
  ["GitHub token", /(?:ghp_|github_pat_)[A-Za-z0-9_]{20,}/],
  ["OpenAI-style secret", /(?:sk-live-|sk-proj-)[A-Za-z0-9_-]{20,}/],
  ["AWS access key", /AKIA[0-9A-Z]{16}/],
];

const findings = [];
for (const file of files) {
  const contents = readFileSync(resolve(root, file));
  if (contents.length > 2_000_000 || contents.includes(0)) continue;
  const text = contents.toString("utf8");
  for (const [label, pattern] of patterns) {
    if (pattern.test(text)) findings.push(`${file}: possible ${label}`);
  }
}

if (findings.length) {
  console.error(findings.join("\n"));
  process.exit(1);
}

console.log(`High-confidence secret scan passed for ${files.length} tracked files.`);
