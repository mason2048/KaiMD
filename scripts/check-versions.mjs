import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const desktop = resolve(root, "apps/desktop");
const packageJson = JSON.parse(readFileSync(resolve(desktop, "package.json"), "utf8"));
const tauriConfig = JSON.parse(
  readFileSync(resolve(desktop, "src-tauri/tauri.conf.json"), "utf8"),
);
const cargoToml = readFileSync(resolve(desktop, "src-tauri/Cargo.toml"), "utf8");
const cargoVersion = cargoToml.match(/^version\s*=\s*"([^"]+)"/m)?.[1];

const versions = new Map([
  ["package.json", packageJson.version],
  ["Cargo.toml", cargoVersion],
  ["tauri.conf.json", tauriConfig.version],
]);
const uniqueVersions = new Set(versions.values());

if (uniqueVersions.size !== 1 || uniqueVersions.has(undefined)) {
  console.error("KaiMD version mismatch:");
  for (const [file, version] of versions) console.error(`- ${file}: ${version ?? "missing"}`);
  process.exit(1);
}

const tagIndex = process.argv.indexOf("--tag");
if (tagIndex !== -1) {
  const tag = process.argv[tagIndex + 1];
  const expectedTag = `v${packageJson.version}`;
  if (tag !== expectedTag) {
    console.error(`Release tag ${tag ?? "missing"} does not match ${expectedTag}.`);
    process.exit(1);
  }
}

if (packageJson.packageManager !== "pnpm@9.15.9") {
  console.error("packageManager must remain pinned to pnpm@9.15.9.");
  process.exit(1);
}

console.log(`KaiMD version ${packageJson.version} is consistent.`);
