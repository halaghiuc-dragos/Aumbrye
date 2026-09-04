#!/usr/bin/env node
/**
 * DOC-01 — fail when a repo path cited in docs or source comments does not exist.
 *
 * `DOC-CONVENTIONS.md` §5 proposed this and it was never built. Two real defects in this repo were
 * exactly this shape and both shipped:
 *
 *   - C-261: `game_facade.gd` pointed at `godot-export` / `smoke-test` jobs in `.github/workflows/`
 *     that had never existed.
 *   - C-265: `content_loader.gd` named `.github/workflows/release.yml` as the pipeline that copies
 *     `content/` next to the exported binary. It did not exist — and because `content/` lives
 *     outside `res://`, an export without that copy ships with no catalogues at all.
 *
 * A wrong comment is not cosmetic when the thing it describes is load-bearing. This check is the
 * cheap half of the problem: it cannot catch a confidently-worded false statement, but it catches
 * every citation of a file that is not there.
 */
import { readFileSync, existsSync, readdirSync, statSync } from "node:fs";
import { join, relative, resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");

const SCAN_DIRS = ["docs", "apps/game/client/scripts", "tools", "scripts"];
const SCAN_EXT = [".md", ".gd", ".py", ".mjs"];
const SKIP_DIRS = new Set([".git", ".godot", "node_modules", "addons", "artifacts", "reports"]);

/**
 * `CORE_GAMEPLAY_REVIEW.md` is a historical record: it quotes paths as they were when each finding
 * was written, including files the review itself then had deleted. Striking through every such
 * citation across 14k lines would be noise, and rewriting them would falsify the record. Exempted
 * deliberately rather than by omission — the tradeoff is that this check does not cover the repo's
 * largest document, and that is the right call for a file whose job is to say what *used* to be true.
 */
const SKIP_FILES = new Set(["docs/CORE_GAMEPLAY_REVIEW.md"]);

// Paths that look like repo references. `res://` maps to the Godot client root.
const PATH_RE =
  /(?:res:\/\/|\b)((?:apps|scripts|content|tools|docs|packages|services|art-source|\.github|scenes|assets|translations)\/[A-Za-z0-9_./-]*\.[A-Za-z0-9]+)/g;

// Placeholders and examples that are deliberately not real files.
const IGNORE_RE = [
  /\.\.\./, /\byour\b/i, /\bexample\b/i, /path\/to\//, /<[^>]+>/,
  /^scenes\/main\.tscn$/, /^docs\/design\//,
];

function walk(dir, out = []) {
  for (const name of readdirSync(dir)) {
    if (SKIP_DIRS.has(name)) continue;
    const full = join(dir, name);
    const st = statSync(full);
    if (st.isDirectory()) walk(full, out);
    else if (SCAN_EXT.some((e) => name.endsWith(e))) out.push(full);
  }
  return out;
}

const failures = [];
for (const dir of SCAN_DIRS) {
  const abs = join(repoRoot, dir);
  if (!existsSync(abs)) continue;
  for (const file of walk(abs)) {
    if (SKIP_FILES.has(relative(repoRoot, file))) continue;
    const text = readFileSync(file, "utf8");
    // Strikethrough marks a citation deliberately kept as history.
    const lines = text.split("\n");
    lines.forEach((line, i) => {
      if (line.includes("~~")) return;
      // A planning document has to cite files it is asking someone to create. `*(new)*` on the
      // line marks that deliberately, the same way `~~strikethrough~~` marks deliberate history.
      // Without this, a plan can only be written by lying about what it wants built.
      if (line.includes("*(new)*")) return;
      for (const m of line.matchAll(PATH_RE)) {
        const ref = m[1];
        if (IGNORE_RE.some((re) => re.test(ref))) continue;
        const asClient = join(repoRoot, "apps/game/client", ref);
        if (existsSync(join(repoRoot, ref)) || existsSync(asClient)) continue;
        failures.push(`${relative(repoRoot, file)}:${i + 1}  ${ref}`);
      }
    });
  }
}

if (failures.length > 0) {
  console.error(`DOC-01: ${failures.length} citation(s) point at files that do not exist:\n`);
  for (const f of failures) console.error("  " + f);
  console.error(
    "\nEither fix the path, delete the claim, mark it ~~struck through~~ if it is deliberate history,\n" +
    "or mark the line *(new)* if it is a file a plan is asking to be created."
  );
  process.exit(1);
}
console.log("DOC-01: every cited repo path exists.");
