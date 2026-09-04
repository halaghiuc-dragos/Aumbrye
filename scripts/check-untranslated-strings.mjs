#!/usr/bin/env node
/**
 * SY-07 — warn on a user-facing string literal that never went through `tr()`.
 *
 * `strings.csv` has 740 keys and every `tr()` call in code resolves — the gap SY-07 found was
 * narrower: `Label.text`, `Label3D.text` and `Button.text` assignments built as plain string
 * literals (`room_locked_door_content.gd`'s `"Unlock (%s)" % key_label`, `stair_lever.gd`'s
 * `"Sealed — defeat the floor boss"`, `FloorKeyring.COLORS`' English-only labels). Switching to
 * Romanian left those untouched. This is the cheap heuristic half of catching that shape again:
 * it cannot see through a helper function that builds text elsewhere, and short technical strings
 * ("", "OK", node names) are exactly what "longer than two characters" is there to filter out.
 *
 * Warn-only, per the plan text — some literals below the threshold are legitimately debug-only or
 * pre-formatted from data (not prose a player reads), and a heuristic this cheap will always have
 * some of those. Never fails the build.
 */
import { readFileSync, readdirSync, statSync } from "node:fs";
import { join, relative, resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const scriptsRoot = join(repoRoot, "apps/game/client/scripts");

const TEXT_PROPS = ["text", "tooltip_text"];
const MIN_LENGTH = 2;

// A literal assignment whose right-hand side is one of these is not prose a player reads.
const SKIP_PATTERNS = [
  /^\s*$/, // empty
  /^[A-Z_][A-Z0-9_]*$/, // ALL_CAPS constant-looking id, e.g. node names
  /^[a-z_]+$/, // bare lowercase identifier-looking string, e.g. "player"
  /^\d+(\.\d+)?$/, // a bare number
  /^%[sd.]/, // a format placeholder alone
  /^res:\/\//, // a resource path
];

function collectGdFiles(dir) {
  const out = [];
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry);
    const st = statSync(full);
    if (st.isDirectory()) {
      out.push(...collectGdFiles(full));
    } else if (entry.endsWith(".gd")) {
      out.push(full);
    }
  }
  return out;
}

function checkFile(path) {
  const warnings = [];
  const lines = readFileSync(path, "utf8").split("\n");
  const assignRe = new RegExp(
    `\\.(?:${TEXT_PROPS.join("|")})\\s*=\\s*"([^"]*)"`,
  );
  lines.forEach((line, index) => {
    const trimmed = line.trim();
    if (trimmed.startsWith("#") || trimmed.startsWith("##")) return;
    if (line.includes("tr(") || line.includes("TranslationServer.translate")) return;
    const match = assignRe.exec(line);
    if (!match) return;
    const literal = match[1];
    if (literal.length <= MIN_LENGTH) return;
    if (SKIP_PATTERNS.some((re) => re.test(literal))) return;
    warnings.push({ line: index + 1, text: literal });
  });
  return warnings;
}

function main() {
  const files = collectGdFiles(scriptsRoot);
  let total = 0;
  for (const file of files) {
    const warnings = checkFile(file);
    if (warnings.length === 0) continue;
    const relPath = relative(repoRoot, file);
    for (const warning of warnings) {
      console.warn(`WARN: ${relPath}:${warning.line} untranslated literal: "${warning.text}"`);
      total++;
    }
  }
  if (total === 0) {
    console.log("OK: no untranslated Label/Label3D/Button text literals found");
  } else {
    console.log(`WARN: ${total} untranslated text literal(s) found (see above) -- not a failure`);
  }
  process.exit(0);
}

main();
