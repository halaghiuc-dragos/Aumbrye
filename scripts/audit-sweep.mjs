#!/usr/bin/env node
/**
 * AUDIT-01 — a repeatable, whole-tree static sweep.
 *
 * `docs/MVP_DEPTH_PLAN.md` §9 is a per-file audit. A one-off audit rots the day after it is
 * written, so the mechanical half of it lives here and can be re-run. This checks things a
 * reviewer would otherwise have to hold in their head across 1,600 files:
 *
 *   - per-frame allocations and log spam inside `_process` / `_physics_process` / `_draw`
 *   - functions long enough that nobody re-reads them
 *   - user-facing string literals that never reach `tr()`
 *   - private `_method()` calls across a module boundary
 *   - unseeded `randf()`/`randi()` inside the determinism-critical dungeon and loot paths
 *   - `res://` paths handed to `ContentLoader`, which resolves against the content root
 *   - `.tscn` ext_resources and NodePaths that point at nothing
 *   - scripts and scenes reachable from nothing (autoloads and constructed paths excluded)
 *   - content JSON that fails to parse
 *
 * It reports, it does not fail a commit — same contract as every other diagnostic in this repo
 * (see `CLAUDE.md`). Run it deliberately: `node scripts/audit-sweep.mjs [--json]`.
 *
 * Every finding is evidence, not a verdict: a hit here is a place to look, and several categories
 * have legitimate exceptions (a seeded RNG fallback, a debug-only literal). The audit in §9 records
 * which hits were verified and which were dismissed, and why.
 */
import { readFileSync, readdirSync, statSync, existsSync } from "node:fs";
import { join, relative, resolve, dirname, basename } from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const client = join(repoRoot, "apps/game/client");
const SKIP = new Set([".git", ".godot", "node_modules", "obj", "bin", "addons", ".ruff_cache", "artifacts", "reports"]);
const json = process.argv.includes("--json");

function walk(dir, ext, out = []) {
  if (!existsSync(dir)) return out;
  for (const name of readdirSync(dir)) {
    if (SKIP.has(name)) continue;
    const full = join(dir, name);
    if (statSync(full).isDirectory()) walk(full, ext, out);
    else if (ext.some((e) => name.endsWith(e))) out.push(full);
  }
  return out;
}

const findings = [];
const add = (file, line, kind, message) =>
  findings.push({ file: relative(repoRoot, file), line, kind, message });

// ---------------------------------------------------------------- GDScript
const AUTOLOAD_RE = /^[A-Za-z0-9_]+="\*?res:\/\/(scripts\/[^"]+\.gd)"/gm;
const projectGodot = readFileSync(join(client, "project.godot"), "utf8");
const autoloads = new Set([...projectGodot.matchAll(AUTOLOAD_RE)].map((m) => m[1]));

const gd = walk(join(client, "scripts"), [".gd"]);
for (const file of gd) {
  const src = readFileSync(file, "utf8");
  const lines = src.split("\n");

  // per-frame function bodies
  const frame = [];
  lines.forEach((l, i) => {
    if (/^func _(process|physics_process|draw)\(/.test(l)) {
      let j = i + 1;
      while (j < lines.length && (lines[j].startsWith("\t") || lines[j].trim() === "")) j++;
      frame.push([i, j]);
    }
  });
  const inFrame = (n) => frame.some(([a, b]) => n >= a && n < b);

  // function body length
  let fn = null, start = 0, body = 0;
  const closeFn = (n) => { if (fn && body > 80) add(file, start + 1, "LONG", `\`${fn}\` is ${body} body lines`); };

  lines.forEach((l, n) => {
    const s = l.trim();
    if (inFrame(n)) {
      if (s.includes("find_children(")) add(file, n + 1, "PERF", "`find_children()` in a per-frame function");
      if (s.includes("get_nodes_in_group(")) add(file, n + 1, "PERF", "`get_nodes_in_group()` in a per-frame function");
      if (s.includes("duplicate(true)")) add(file, n + 1, "PERF", "deep `duplicate(true)` in a per-frame function");
      if (/\b(push_error|push_warning)\(/.test(s)) add(file, n + 1, "PERF", "`push_error`/`push_warning` in a per-frame function — unbounded log spam");
      if (s.includes("ContentLoader.load_json")) add(file, n + 1, "PERF", "`ContentLoader.load_json()` in a per-frame function");
      if (/\bload\("res:\/\//.test(s)) add(file, n + 1, "PERF", "resource `load()` in a per-frame function");
    }
    if (/\.text\s*=\s*"[A-Z][a-z]{2,}/.test(s) && !s.includes("tr(")) add(file, n + 1, "L10N", "English literal assigned to `.text`");
    const cl = s.match(/ContentLoader\.load_json\(\s*([A-Za-z0-9_"'.\/:]+)/);
    if (cl) {
      const arg = cl[1];
      const isResLiteral = /^["']res:\/\//.test(arg);
      // a const argument: resolve it in this file
      const constDef = arg.match(/^[A-Z][A-Z0-9_]*$/)
        ? src.match(new RegExp("^const\\s+" + arg + "\\s*:?=\\s*\"([^\"]+)\"", "m"))
        : null;
      if (isResLiteral || (constDef && constDef[1].startsWith("res://")))
        add(file, n + 1, "BUG", "`res://` path handed to `ContentLoader`, which resolves against the content root — the file is never read");
    }
    const priv = s.match(/\b([A-Z][A-Za-z0-9]+)\._[a-z_]+\(/);
    if (priv && !["Engine", "Input", "Time", "OS", "JSON", "ProjectSettings", "DisplayServer"].includes(priv[1]))
      add(file, n + 1, "ENH", `calls a private \`_method()\` on \`${priv[1]}\` across a module boundary`);
    if (/#\s*(TODO|FIXME|HACK|XXX)\b/.test(s)) add(file, n + 1, "ENH", `carries a ${s.match(/(TODO|FIXME|HACK|XXX)/)[1]} marker`);
    if (/(?<![A-Za-z_.])(randf|randi)(_range)?\(/.test(s) && !/rng\./.test(s) && /(dungeon|procgen|loot|items)\//.test(file))
      add(file, n + 1, "SEED", "unseeded `randf()`/`randi()` in a determinism-critical path — verify it is a deliberate seed source");

    if (/^(static )?func /.test(l)) { closeFn(n); fn = l.replace(/^(static )?func ([A-Za-z0-9_]+).*/, "$2"); start = n; body = 0; }
    else if (fn && l.startsWith("\t") && l.trim() !== "") body++;
    else if (fn && l && !l.startsWith("\t") && !l.startsWith("#")) { closeFn(n); fn = null; }
  });
  closeFn(lines.length);
}

// ---------------------------------------------------------------- scenes
const scenes = walk(join(client, "scenes"), [".tscn"]);
for (const file of scenes) {
  const src = readFileSync(file, "utf8");
  const nodes = new Set([...src.matchAll(/\[node name="([^"]+)"/g)].map((m) => m[1]));
  for (const m of src.matchAll(/path="(res:\/\/[^"]+)"/g)) {
    if (!existsSync(join(client, m[1].replace("res://", "")))) add(file, 0, "BUG", `ext_resource missing: ${m[1]}`);
  }
  for (const m of src.matchAll(/= NodePath\("([^"]*)"\)/g)) {
    const p = m[1];
    if (!p || p.startsWith("..")) continue;
    if (!nodes.has(p.split("/")[0])) add(file, 0, "BUG", `NodePath points at a node not in this scene: ${p}`);
  }
}

// ---------------------------------------------------------------- reachability
let all = "";
for (const f of [...walk(client, [".tscn", ".gd", ".tres"]), ...walk(join(repoRoot, "content"), [".json"])])
  all += readFileSync(f, "utf8");
for (const file of gd) {
  const rel = relative(client, file);
  if (autoloads.has(rel)) continue;
  const src = readFileSync(file, "utf8");
  if (all.includes(`res://${rel}`)) continue;
  const cn = src.match(/^class_name\s+([A-Za-z0-9_]+)/m);
  if (cn && all.split(src).join("").includes(cn[1])) continue;
  add(file, 0, "DEAD", "script reachable from no scene, preload, class_name use or autoload");
}
for (const file of scenes) {
  const rel = relative(client, file);
  if (all.includes(`res://${rel}`)) continue;
  // room scenes are loaded by a constructed path (BiomeRegistry.get_room_scenes)
  if (rel.startsWith("scenes/rooms/")) continue;
  // debug scenes are launched by hand, per CLAUDE.md
  if (rel.startsWith("scenes/debug/")) continue;
  add(file, 0, "DEAD", "scene instantiated by nothing");
}

// ---------------------------------------------------------------- content
for (const file of walk(join(repoRoot, "content"), [".json"])) {
  try { JSON.parse(readFileSync(file, "utf8")); }
  catch (e) { add(file, 0, "BUG", `JSON does not parse: ${e.message}`); }
}

// ---------------------------------------------------------------- report
if (json) { console.log(JSON.stringify(findings, null, 1)); process.exit(0); }
const byKind = {};
for (const f of findings) (byKind[f.kind] ??= []).push(f);
const order = ["BUG", "PERF", "SEED", "DEAD", "L10N", "LONG", "ENH"];
console.log(`AUDIT-01: ${gd.length} scripts, ${scenes.length} scenes, ${findings.length} findings\n`);
for (const kind of order) {
  const rows = byKind[kind];
  if (!rows?.length) continue;
  console.log(`== ${kind} (${rows.length})`);
  for (const r of rows) console.log(`   ${r.file}${r.line ? ":" + r.line : ""}  ${r.message}`);
  console.log();
}
for (const kind of Object.keys(byKind)) if (!order.includes(kind)) console.log(`== ${kind}: ${byKind[kind].length}`);
