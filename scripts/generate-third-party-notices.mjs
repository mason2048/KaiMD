import { execFileSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const desktop = resolve(root, "apps/desktop");
const outputPath = resolve(root, "THIRD_PARTY_NOTICES.md");
const checkOnly = process.argv.includes("--check");

const allowedRustLicenses = new Set([
  "(MIT OR Apache-2.0) AND Unicode-3.0",
  "0BSD OR MIT OR Apache-2.0",
  "Apache-2.0",
  "Apache-2.0 / MIT",
  "Apache-2.0 AND MIT",
  "Apache-2.0 OR MIT",
  "Apache-2.0 WITH LLVM-exception",
  "Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT",
  "Apache-2.0/MIT",
  "BSD-3-Clause",
  "BSD-3-Clause AND MIT",
  "BSD-3-Clause OR MIT OR Apache-2.0",
  "BSD-3-Clause/MIT",
  "CC0-1.0 OR MIT-0 OR Apache-2.0",
  "ISC",
  "MIT",
  "MIT OR Apache-2.0",
  "MIT OR Apache-2.0 OR LGPL-2.1-or-later",
  "MIT OR Apache-2.0 OR Zlib",
  "MIT OR Zlib OR Apache-2.0",
  "MIT/Apache-2.0",
  "MPL-2.0",
  "Unicode-3.0",
  "Unlicense OR MIT",
  "Unlicense/MIT",
  "Zlib",
  "Zlib OR Apache-2.0 OR MIT",
]);
const allowedJavaScriptLicenses = new Set([
  "Apache-2.0 OR MIT",
  "BSD-3-Clause",
  "ISC",
  "MIT",
  "MIT OR Apache-2.0",
]);

const comparePackages = (a, b) => {
  const left = `${a.name}@${a.version}`;
  const right = `${b.name}@${b.version}`;
  return left < right ? -1 : left > right ? 1 : 0;
};
const pnpmExecPath = process.env.npm_execpath;
const pnpmCommand = pnpmExecPath ? process.execPath : "pnpm";
const pnpmArguments = [
  ...(pnpmExecPath ? [pnpmExecPath] : []),
  "licenses",
  "list",
  "--prod",
  "--json",
];
const jsByLicense = JSON.parse(
  execFileSync(pnpmCommand, pnpmArguments, {
    cwd: desktop,
    encoding: "utf8",
    shell: !pnpmExecPath && process.platform === "win32",
  }),
);
const jsPackages = Object.values(jsByLicense)
  .flat()
  .flatMap((item) => item.versions.map((version) => ({
    name: item.name,
    version,
    license: item.license,
  })))
  .sort(comparePackages);

const metadata = JSON.parse(
  execFileSync("cargo", [
    "metadata",
    "--locked",
    "--format-version",
    "1",
    "--manifest-path",
    "src-tauri/Cargo.toml",
  ], { cwd: desktop, encoding: "utf8", maxBuffer: 20 * 1024 * 1024 }),
);
const rustPackages = metadata.packages
  .filter((item) => item.source !== null)
  .map((item) => ({ name: item.name, version: item.version, license: item.license }))
  .sort(comparePackages);

const rejected = [
  ...jsPackages.filter((item) => !allowedJavaScriptLicenses.has(item.license)),
  ...rustPackages.filter((item) => !item.license || !allowedRustLicenses.has(item.license)),
];
if (rejected.length) {
  console.error("Review these new or changed dependency licenses before release:");
  for (const item of rejected) console.error(`- ${item.name}@${item.version}: ${item.license ?? "missing"}`);
  process.exit(1);
}

const escapeCell = (value) => String(value).replaceAll("|", "\\|");
const rows = (items) => items.map(
  (item) => `| ${escapeCell(item.name)} | ${escapeCell(item.version)} | ${escapeCell(item.license)} |`,
);
const notice = [
  "# Third-Party Notices",
  "",
  "KaiMD is distributed under the MIT License. It includes open-source dependencies",
  "listed below. Copyright and license terms remain with their respective authors.",
  "The authoritative license text for each dependency is included in its source package",
  "and linked package metadata. This inventory is generated from the committed lockfiles.",
  "",
  "## JavaScript production dependencies",
  "",
  "| Package | Version | License |",
  "| --- | --- | --- |",
  ...rows(jsPackages),
  "",
  "## Rust dependencies",
  "",
  "| Crate | Version | License |",
  "| --- | --- | --- |",
  ...rows(rustPackages),
  "",
].join("\n");

if (checkOnly) {
  const current = readFileSync(outputPath, "utf8");
  if (current !== notice) {
    console.error("THIRD_PARTY_NOTICES.md is stale. Run pnpm licenses:generate.");
    process.exit(1);
  }
  console.log("Third-party notice inventory is current and license expressions are approved.");
} else {
  writeFileSync(outputPath, notice);
  console.log(`Wrote ${outputPath}.`);
}
