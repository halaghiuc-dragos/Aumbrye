#!/usr/bin/env node
/**
 * Generate distinct procedural placeholder OGG loops per biome from audio profile freqs.
 * Each biome gets unique ambience + boss stems (not byte-identical castle copies).
 * Usage: node scripts/tools/generate-biome-audio.mjs [--check]
 */
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const __dirname = dirname(fileURLToPath(import.meta.url));
const forwardedArgs = process.argv.slice(2);

execFileSync(
  process.execPath,
  [join(__dirname, "generate-game-audio.mjs"), ...forwardedArgs],
  { stdio: "inherit" }
);
