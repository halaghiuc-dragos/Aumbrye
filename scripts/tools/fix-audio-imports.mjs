#!/usr/bin/env node
/** Ensure Godot .import sidecars exist for audio OGGs with correct loop flags. */
import { readdirSync, readFileSync, writeFileSync, existsSync } from "node:fs";
import { join, dirname, relative } from "node:path";
import { fileURLToPath } from "node:url";
import { createHash } from "node:crypto";

const __dirname = dirname(fileURLToPath(import.meta.url));
const clientRoot = join(__dirname, "..", "..", "apps", "game", "client");
const audioRoot = join(clientRoot, "assets", "audio");

function walk(dir, out = []) {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const full = join(dir, entry.name);
    if (entry.isDirectory()) walk(full, out);
    else if (entry.name.endsWith(".ogg")) out.push(full);
  }
  return out;
}

function uidFor(path) {
  return "uid://" + createHash("sha256").update(path).digest("hex").slice(0, 13);
}

function makeImport(oggPath) {
  const rel = "res://" + relative(clientRoot, oggPath).replace(/\\/g, "/");
  const base = oggPath.replace(/\\/g, "/").split("/").pop();
  const hash = createHash("md5").update(rel).digest("hex");
  const imported = `res://.godot/imported/${base}-${hash}.oggvorbisstr`;
  const loop = /_loop\.ogg$/i.test(base);
  return `[remap]

importer="oggvorbisstr"
type="AudioStreamOggVorbis"
uid="${uidFor(rel)}"
path="${imported}"

[deps]

source_file="${rel}"
dest_files=["${imported}"]

[params]

loop=${loop}
loop_offset=0
bpm=0
beat_count=0
bar_beats=4
`;
}

let updated = 0;
for (const ogg of walk(audioRoot)) {
  const importPath = `${ogg}.import`;
  const desired = makeImport(ogg);
  const loopExpected = /_loop\.ogg$/i.test(ogg.split(/[/\\]/).pop()) ? "loop=true" : "loop=false";
  if (!existsSync(importPath) || !readFileSync(importPath, "utf8").includes(loopExpected)) {
    writeFileSync(importPath, desired);
    console.log(`Updated ${relative(audioRoot, importPath)}`);
    updated += 1;
  }
}
console.log(`Processed ${walk(audioRoot).length} OGG files (${updated} imports written).`);
