#!/usr/bin/env node
/**
 * Stages the repository's versioned `content/` tree beside an exported executable.
 *
 * ContentLoader deliberately resolves `content/` from the executable's base directory outside
 * the editor.  Godot cannot export resources located above its project root, so release staging
 * owns that explicit copy instead of relying on an editor-only working-directory coincidence.
 *
 * Usage:
 *   node scripts/package-release-content.mjs --platform linux --release-dir /path/to/release
 *   node scripts/package-release-content.mjs --platform windows --release-dir /path/to/release
 *   node scripts/package-release-content.mjs --platform macos --release-dir /path/Aumbrye.app
 *
 * The macOS argument is the `.app` bundle; content is placed in `Contents/MacOS/content`, the
 * same directory returned by `OS.get_executable_path().get_base_dir()` at runtime.
 */
import { cpSync, existsSync, mkdirSync, readFileSync, readdirSync, statSync } from "node:fs";
import { createHash } from "node:crypto";
import { basename, dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const sourceContent = join(repoRoot, "content");
const args = process.argv.slice(2);

function value(flag) {
  const index = args.indexOf(flag);
  return index >= 0 ? args[index + 1] ?? "" : "";
}

function fail(message) {
  console.error(`FAIL: ${message}`);
  process.exit(1);
}

const platform = value("--platform").toLowerCase();
const releaseArg = value("--release-dir");
if (!new Set(["linux", "windows", "macos"]).has(platform)) {
  fail("--platform must be linux, windows, or macos");
}
if (!releaseArg) fail("--release-dir is required");
if (!existsSync(sourceContent)) fail(`source content is missing: ${sourceContent}`);

const releaseDir = resolve(releaseArg);
const executableDir = platform === "macos" ? join(releaseDir, "Contents", "MacOS") : releaseDir;
if (!existsSync(executableDir)) {
  fail(`expected executable directory is missing: ${executableDir}`);
}

const destination = join(executableDir, "content");
mkdirSync(executableDir, { recursive: true });
cpSync(sourceContent, destination, { recursive: true, force: true, errorOnExist: false });

const required = [
  "items/catalog.json",
  "enemies/castle_grunt.json",
  "biomes/forgotten_castle.json",
  "classes/knight.json",
  "schemas/item-definition.v1.json",
];
for (const relativePath of required) {
  const path = join(destination, relativePath);
  if (!existsSync(path)) fail(`staged bundle is incomplete: ${path}`);
}

function countJson(directory) {
  let count = 0;
  for (const entry of readdirSync(directory)) {
    const path = join(directory, entry);
    const info = statSync(path);
    if (info.isDirectory()) count += countJson(path);
    else if (entry.endsWith(".json")) count += 1;
  }
  return count;
}

function inventory(directory, prefix = "", output = new Map()) {
  for (const entry of readdirSync(directory).sort()) {
    const path = join(directory, entry);
    const relativePath = prefix ? `${prefix}/${entry}` : entry;
    const info = statSync(path);
    if (info.isDirectory()) {
      inventory(path, relativePath, output);
      continue;
    }
    const digest = createHash("sha256").update(readFileSync(path)).digest("hex");
    output.set(relativePath, digest);
  }
  return output;
}

const sourceCount = countJson(sourceContent);
const stagedCount = countJson(destination);
if (stagedCount !== sourceCount) {
  fail(`staged JSON count ${stagedCount} does not match source ${sourceCount}`);
}
const sourceFiles = inventory(sourceContent);
const stagedFiles = inventory(destination);
const missing = [...sourceFiles.keys()].filter((path) => !stagedFiles.has(path));
const extra = [...stagedFiles.keys()].filter((path) => !sourceFiles.has(path));
const changed = [...sourceFiles.keys()].filter((path) =>
  stagedFiles.has(path) && sourceFiles.get(path) !== stagedFiles.get(path));
if (missing.length || extra.length || changed.length) {
  fail(
    `staged content differs from source: ${missing.length} missing, `
      + `${extra.length} extra, ${changed.length} changed`,
  );
}
console.log(
  `OK: staged ${sourceFiles.size} exact content files (${stagedCount} JSON) beside ${platform} executable at ${destination}`,
);
