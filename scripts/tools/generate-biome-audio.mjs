#!/usr/bin/env node
/**
 * Generate distinct procedural placeholder OGG loops per biome from audio profile freqs.
 * Each biome gets unique ambience + boss stems (not byte-identical castle copies).
 * Usage: node scripts/tools/generate-biome-audio.mjs [--check]
 */
import { execSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const __dirname = dirname(fileURLToPath(import.meta.url));

if (process.argv.includes("--check")) {
  execSync(`node "${join(__dirname, "generate-game-audio.mjs")}" --check`, {
    stdio: "inherit",
  });
  process.exit(0);
}

execSync(`node "${join(__dirname, "generate-game-audio.mjs")}"`, { stdio: "inherit" });
