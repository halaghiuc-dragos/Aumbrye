#!/usr/bin/env node
/**
 * Generate short authored combat SFX under apps/game/client/assets/audio/sfx/.
 * Distinct envelopes per cue (not runtime AudioStreamGenerator beeps).
 */
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { execFileSync } from "node:child_process";
import { createSeededRandom, readSeed } from "./seeded_rng.mjs";
import { publishGeneratedAssetSet } from "./generated_asset_set.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = join(__dirname, "..", "..");
const sfxDir = join(repoRoot, "apps", "game", "client", "assets", "audio", "sfx");

const SAMPLE_RATE = 44100;
const GENERATION_SEED = readSeed(process.argv, 0x0c0b47);
const random = createSeededRandom(GENERATION_SEED);

function requireFfmpeg() {
  try {
    execFileSync("ffmpeg", ["-version"], { stdio: "pipe" });
  } catch (error) {
    console.error(`ERROR: could not launch ffmpeg: ${error.message}`);
    process.exit(1);
  }
}

function encodeWav(samples) {
  const numChannels = 1;
  const bitsPerSample = 16;
  const byteRate = (SAMPLE_RATE * numChannels * bitsPerSample) / 8;
  const blockAlign = (numChannels * bitsPerSample) / 8;
  const dataSize = samples.length * 2;
  const buffer = Buffer.alloc(44 + dataSize);
  buffer.write("RIFF", 0);
  buffer.writeUInt32LE(36 + dataSize, 4);
  buffer.write("WAVE", 8);
  buffer.write("fmt ", 12);
  buffer.writeUInt32LE(16, 16);
  buffer.writeUInt16LE(1, 20);
  buffer.writeUInt16LE(numChannels, 22);
  buffer.writeUInt32LE(SAMPLE_RATE, 24);
  buffer.writeUInt32LE(byteRate, 28);
  buffer.writeUInt16LE(blockAlign, 32);
  buffer.writeUInt16LE(bitsPerSample, 34);
  buffer.write("data", 36);
  buffer.writeUInt32LE(dataSize, 40);
  for (let i = 0; i < samples.length; i++) {
    const clamped = Math.max(-1, Math.min(1, samples[i]));
    buffer.writeInt16LE(Math.round(clamped * 32767), 44 + i * 2);
  }
  return buffer;
}

function wavToOgg(wavBuffer) {
  return execFileSync(
    "ffmpeg",
    ["-hide_banner", "-loglevel", "error", "-f", "wav", "-i", "pipe:0", "-c:a", "libvorbis", "-q:a", "4", "-f", "ogg", "pipe:1"],
    { input: wavBuffer, maxBuffer: 16 * 1024 * 1024 }
  );
}

function writeAudio(baseName, samples) {
  const wavPath = join(sfxDir, `${baseName}.wav`);
  const oggPath = join(sfxDir, `${baseName}.ogg`);
  const wavBuffer = encodeWav(samples);
  const oggBuffer = wavToOgg(wavBuffer);
  if (oggBuffer.subarray(0, 4).toString("ascii") !== "OggS") {
    throw new Error(`ffmpeg returned an invalid Ogg stream for ${baseName}`);
  }
  return [
    { path: wavPath, buffer: wavBuffer },
    { path: oggPath, buffer: oggBuffer },
  ];
}

function toneBurst(seconds, freq, { attack = 0.008, decay = 0.12, amp = 0.35, noise = 0 } = {}) {
  const total = Math.floor(SAMPLE_RATE * seconds);
  const out = new Float32Array(total);
  for (let i = 0; i < total; i++) {
    const t = i / SAMPLE_RATE;
    const env =
      Math.min(1, t / attack) *
      Math.exp(-((t - attack) / decay) * 6);
    let sample = Math.sin(2 * Math.PI * freq * t) * amp * env;
    if (noise > 0) {
      sample += (random() * 2 - 1) * noise * env;
    }
    out[i] = sample;
  }
  return out;
}

function layeredBurst(seconds, layers) {
  const total = Math.floor(SAMPLE_RATE * seconds);
  const out = new Float32Array(total);
  for (const layer of layers) {
    const partial = toneBurst(seconds, layer.freq, layer);
    for (let i = 0; i < total; i++) out[i] += partial[i];
  }
  return out;
}

const cues = {
  hit: layeredBurst(0.09, [
    { freq: 280, amp: 0.28, decay: 0.06, noise: 0.08 },
    { freq: 520, amp: 0.12, decay: 0.04 },
  ]),
  hit_flesh_01: layeredBurst(0.08, [
    { freq: 220, amp: 0.28, decay: 0.06, noise: 0.08 },
    { freq: 440, amp: 0.08, decay: 0.04 },
  ]),
  hit_flesh_02: layeredBurst(0.09, [
    { freq: 245, amp: 0.27, decay: 0.06, noise: 0.07 },
    { freq: 490, amp: 0.07, decay: 0.04 },
  ]),
  hit_flesh_03: layeredBurst(0.07, [
    { freq: 198, amp: 0.29, decay: 0.05, noise: 0.09 },
    { freq: 396, amp: 0.09, decay: 0.03 },
  ]),
  hit_armor: layeredBurst(0.1, [
    { freq: 180, amp: 0.32, decay: 0.08, noise: 0.04 },
    { freq: 340, amp: 0.1, decay: 0.05 },
  ]),
  block: layeredBurst(0.11, [
    { freq: 140, amp: 0.3, decay: 0.09 },
    { freq: 220, amp: 0.15, decay: 0.07 },
  ]),
  block_01: layeredBurst(0.1, [
    { freq: 160, amp: 0.3, decay: 0.09 },
    { freq: 320, amp: 0.06, decay: 0.07 },
  ]),
  block_02: layeredBurst(0.11, [
    { freq: 145, amp: 0.28, decay: 0.09 },
    { freq: 290, amp: 0.05, decay: 0.07 },
  ]),
  parry: layeredBurst(0.14, [
    { freq: 520, amp: 0.32, decay: 0.05 },
    { freq: 880, amp: 0.18, decay: 0.08 },
  ]),
  parry_01: layeredBurst(0.12, [
    { freq: 440, amp: 0.32, decay: 0.05 },
    { freq: 880, amp: 0.1, decay: 0.08 },
  ]),
  swing_01: toneBurst(0.06, 130, { amp: 0.3, decay: 0.05, noise: 0.12 }),
  swing_02: toneBurst(0.07, 118, { amp: 0.28, decay: 0.05, noise: 0.14 }),
  death_01: layeredBurst(0.35, [
    { freq: 90, amp: 0.32, decay: 0.2 },
    { freq: 45, amp: 0.12, decay: 0.25 },
  ]),
  step_stone_01: toneBurst(0.05, 80, { amp: 0.22, decay: 0.04, noise: 0.06 }),
  step_stone_02: toneBurst(0.055, 72, { amp: 0.2, decay: 0.04, noise: 0.06 }),
  step_wood_01: toneBurst(0.05, 95, { amp: 0.2, decay: 0.04, noise: 0.04 }),
  step_water_01: toneBurst(0.06, 110, { amp: 0.18, decay: 0.06, noise: 0.1 }),
  windup_01: layeredBurst(0.22, [
    { freq: 72, amp: 0.25, decay: 0.18 },
    { freq: 144, amp: 0.06, decay: 0.14 },
  ]),
  heal_raise: toneBurst(0.1, 180, { amp: 0.25, decay: 0.08 }),
  heal_gulp: toneBurst(0.12, 300, { amp: 0.3, decay: 0.09, noise: 0.05 }),
  heal_commit: layeredBurst(0.22, [
    { freq: 520, amp: 0.28, decay: 0.14 },
    { freq: 780, amp: 0.12, decay: 0.1 },
  ]),
  ui_click_01: toneBurst(0.04, 520, { amp: 0.25, decay: 0.03 }),
};

requireFfmpeg();
if (process.argv.includes("--self-test")) {
  const wav = encodeWav(toneBurst(0.02, 440, { noise: 0.03 }));
  const ogg = wavToOgg(wav);
  if (ogg.subarray(0, 4).toString("ascii") !== "OggS") throw new Error("Ogg self-test failed");
  console.log(`AUDIO SFX SELF-TEST PASS (seed ${GENERATION_SEED}; no files written)`);
  process.exit(0);
}
const outputs = Object.entries(cues).flatMap(([name, samples]) => writeAudio(name, samples));
const published = publishGeneratedAssetSet({
  repoRoot,
  manifestPath: join(repoRoot, "tools", ".generated-manifest.json"),
  generatorPath: fileURLToPath(import.meta.url),
  sourcePaths: [fileURLToPath(import.meta.url)],
  seed: GENERATION_SEED,
  outputs,
  force: process.argv.includes("--force"),
});
console.log(`Published ${published.length} combat audio assets.`);
console.log(`Generation seed: ${GENERATION_SEED}`);
