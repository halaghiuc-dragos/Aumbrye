#!/usr/bin/env node
/**
 * SY-07 — reject a user-facing string literal that never went through `tr()`.
 *
 * `strings.csv` has 740 keys and every `tr()` call in code resolves — the gap SY-07 found was
 * narrower: `Label.text`, `Label3D.text` and `Button.text` assignments built as plain string
 * literals (`room_locked_door_content.gd`'s `"Unlock (%s)" % key_label`, `stair_lever.gd`'s
 * `"Sealed — defeat the floor boss"`, `FloorKeyring.COLORS`' English-only labels). Switching to
 * Romanian left those untouched. This is the cheap heuristic half of catching that shape again:
 * it cannot see through a helper function that builds text elsewhere, and short technical strings
 * ("", "OK", node names) are exactly what "longer than two characters" is there to filter out.
 *
 * Formatting-only separators and debug-only names are allowlisted below. Every remaining match is
 * a player-facing phrase and fails the content gate, so a new screen cannot silently bypass the
 * English/Romanian tables.
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
  /^[\s|·→\[\]%.0-9sd]+$/u, // punctuation/separators and format-only fragments
  /^ProbeFlow(?:\d+|%d)$/, // debug probe node name
  /^x%d$/, // compact status-stack counter; the number itself is locale-neutral
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
    console.error(`FAIL: ${total} untranslated text literal(s) found (see above)`);
  }
  process.exit(total === 0 ? 0 : 1);
}

main();
