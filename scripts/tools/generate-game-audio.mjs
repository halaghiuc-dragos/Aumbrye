#!/usr/bin/env node
/**
 * Generate procedural OGG stems and SFX for Aumbrye audio profiles and sfx bank.
 * Usage: node scripts/tools/generate-game-audio.mjs [--check]
 */
import {
  readdirSync,
  readFileSync,
  writeFileSync,
  mkdirSync,
  existsSync,
  rmSync,
} from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { execFileSync, execSync } from "node:child_process";

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = join(__dirname, "..", "..");
const profilesDir = join(repoRoot, "content", "audio_profiles");
const clientAudio = join(repoRoot, "apps", "game", "client", "assets", "audio");
const sfxBankPath = join(repoRoot, "content", "audio", "sfx.json");

const SAMPLE_RATE = 44100;
const CHECK_ONLY = process.argv.includes("--check");

function requireFfmpeg() {
  try {
    execSync("ffmpeg -version", { stdio: "pipe" });
  } catch {
    console.error("ERROR: ffmpeg is required on PATH. Install ffmpeg and retry.");
    process.exit(1);
  }
}

function writeWav(filePath, samples) {
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
  writeFileSync(filePath, buffer);
}

function wavToOgg(wavPath, oggPath) {
  execFileSync(
    "ffmpeg",
    ["-y", "-i", wavPath, "-c:a", "libvorbis", "-q:a", "4", oggPath],
    { stdio: "pipe" }
  );
}

function writeOggFromSamples(oggPath, samples) {
  const dir = dirname(oggPath);
  mkdirSync(dir, { recursive: true });
  const wavPath = oggPath.replace(/\.ogg$/, "_tmp.wav");
  writeWav(wavPath, samples);
  wavToOgg(wavPath, oggPath);
  rmSync(wavPath, { force: true });
}

function generateLoop(seconds, baseFreq, harmonics = [], noiseAmp = 0.0) {
  const total = Math.floor(SAMPLE_RATE * seconds);
  const out = new Float32Array(total);
  for (let i = 0; i < total; i++) {
    const t = i / SAMPLE_RATE;
    const loopEnv = 0.5 + 0.5 * Math.sin((2 * Math.PI * t) / seconds);
    let sample = Math.sin(2 * Math.PI * baseFreq * t) * 0.22;
    for (const h of harmonics) {
      sample += Math.sin(2 * Math.PI * h.freq * t) * h.amp;
    }
    if (noiseAmp > 0) {
      sample += (Math.random() * 2 - 1) * noiseAmp * loopEnv;
    }
    const fade = Math.min(1, i / (SAMPLE_RATE * 0.05), (total - i) / (SAMPLE_RATE * 0.05));
    out[i] = sample * loopEnv * fade;
  }
  return out;
}

function generateBurst(seconds, baseFreq, harmonics = [], amp = 0.35) {
  const total = Math.max(1, Math.floor(SAMPLE_RATE * seconds));
  const out = new Float32Array(total);
  for (let i = 0; i < total; i++) {
    const t = i / SAMPLE_RATE;
    const env = 1.0 - i / total;
    let sample = Math.sin(2 * Math.PI * baseFreq * t) * amp;
    for (const h of harmonics) {
      sample += Math.sin(2 * Math.PI * h.freq * t) * h.amp * env;
    }
    out[i] = sample * env;
  }
  return out;
}

function generateNoiseBurst(seconds, amp = 0.25) {
  const total = Math.max(1, Math.floor(SAMPLE_RATE * seconds));
  const out = new Float32Array(total);
  for (let i = 0; i < total; i++) {
    const env = 1.0 - i / total;
    out[i] = (Math.random() * 2 - 1) * amp * env;
  }
  return out;
}

function resPathToDisk(resPath) {
  const rel = resPath.replace(/^res:\/\//, "");
  return join(repoRoot, "apps", "game", "client", rel);
}

function collectRequiredPaths() {
  const required = new Set();

  for (const file of readdirSync(profilesDir).filter((f) => f.endsWith(".json"))) {
    const profile = JSON.parse(readFileSync(join(profilesDir, file), "utf8"));
    const layers = profile.layers ?? {};
    for (const layer of Object.values(layers)) {
      if (layer?.path) required.add(layer.path);
    }
    if (profile.ambiencePath) required.add(profile.ambiencePath);
    if (profile.bossPath) required.add(profile.bossPath);
    const stingers = profile.stingers ?? {};
    for (const path of Object.values(stingers)) {
      if (typeof path === "string" && path) required.add(path);
    }
  }

  if (existsSync(sfxBankPath)) {
    const bank = JSON.parse(readFileSync(sfxBankPath, "utf8"));
    for (const entry of Object.values(bank.sfx ?? {})) {
      for (const path of entry.variants ?? []) required.add(path);
      for (const paths of Object.values(entry.surface_variants ?? {})) {
        for (const path of paths) required.add(path);
      }
    }
  }

  return [...required];
}

function runCheck() {
  const missing = collectRequiredPaths().filter((p) => !existsSync(resPathToDisk(p)));
  if (missing.length > 0) {
    console.error("Missing audio stems:");
    for (const path of missing) console.error(`  ${path}`);
    process.exit(1);
  }
  console.log(`OK: all ${missing.length === 0 ? collectRequiredPaths().length : 0} required audio files present`);
  process.exit(0);
}

function generateBiomeStems() {
  let count = 0;
  for (const file of readdirSync(profilesDir).filter((f) => f.endsWith(".json"))) {
    const profile = JSON.parse(readFileSync(join(profilesDir, file), "utf8"));
    const biomeId = profile.biomeId || profile.id;
    const layers = profile.layers ?? {};
    const ambienceFreq = Number(layers.ambience?.fallback_freq ?? profile.ambienceFreq ?? 110);
    const exploreFreq = Number(layers.explore?.fallback_freq ?? profile.exploreFreq ?? ambienceFreq);
    const combatFreq = Number(layers.combat?.fallback_freq ?? profile.combatFreq ?? 130);
    const bossFreq = Number(layers.boss?.fallback_freq ?? profile.bossFreq ?? 196);

    const specs = [
      { name: "ambience_loop.ogg", freq: ambienceFreq, sec: 8, harmonics: [{ freq: exploreFreq * 0.5, amp: 0.08 }] },
      { name: "explore_loop.ogg", freq: exploreFreq, sec: 8, harmonics: [{ freq: ambienceFreq, amp: 0.06 }] },
      { name: "combat_loop.ogg", freq: combatFreq, sec: 6, harmonics: [{ freq: combatFreq * 1.5, amp: 0.1 }], noise: 0.02 },
      { name: "boss_theme.ogg", freq: bossFreq, sec: 6, harmonics: [{ freq: bossFreq * 0.5, amp: 0.1 }, { freq: bossFreq * 1.25, amp: 0.06 }] },
    ];

    const outDir = join(clientAudio, biomeId);
    mkdirSync(outDir, { recursive: true });
    for (const spec of specs) {
      const oggPath = join(outDir, spec.name);
      const samples = generateLoop(spec.sec, spec.freq, spec.harmonics, spec.noise ?? 0);
      writeOggFromSamples(oggPath, samples);
      count += 1;
      console.log(`OK: ${biomeId}/${spec.name}`);
    }
  }
  return count;
}

function generateSharedStingers() {
  const sharedDir = join(clientAudio, "shared");
  mkdirSync(sharedDir, { recursive: true });
  const specs = [
    { file: "sting_boss.ogg", seconds: 1.2, freq: 196, harmonics: [{ freq: 392, amp: 0.12 }] },
    { file: "sting_clear.ogg", seconds: 0.9, freq: 330, harmonics: [{ freq: 495, amp: 0.08 }] },
  ];
  for (const spec of specs) {
    writeOggFromSamples(join(sharedDir, spec.file), generateBurst(spec.seconds, spec.freq, spec.harmonics, 0.3));
    console.log(`OK: shared/${spec.file}`);
  }
  return specs.length;
}

function generateSfx() {
  const sfxDir = join(clientAudio, "sfx");
  mkdirSync(sfxDir, { recursive: true });
  const specs = [
    { file: "hit_flesh_01.ogg", seconds: 0.08, freq: 220, harmonics: [{ freq: 440, amp: 0.08 }] },
    { file: "hit_flesh_02.ogg", seconds: 0.09, freq: 245, harmonics: [{ freq: 490, amp: 0.07 }] },
    { file: "hit_flesh_03.ogg", seconds: 0.07, freq: 198, harmonics: [{ freq: 396, amp: 0.09 }] },
    { file: "block_01.ogg", seconds: 0.1, freq: 160, harmonics: [{ freq: 320, amp: 0.06 }] },
    { file: "block_02.ogg", seconds: 0.11, freq: 145, harmonics: [{ freq: 290, amp: 0.05 }] },
    { file: "parry_01.ogg", seconds: 0.12, freq: 440, harmonics: [{ freq: 880, amp: 0.1 }] },
    { file: "swing_01.ogg", seconds: 0.06, freq: 130, harmonics: [{ freq: 260, amp: 0.04 }] },
    { file: "swing_02.ogg", seconds: 0.07, freq: 118, harmonics: [{ freq: 236, amp: 0.05 }] },
    { file: "death_01.ogg", seconds: 0.35, freq: 90, harmonics: [{ freq: 45, amp: 0.12 }] },
    { file: "step_stone_01.ogg", seconds: 0.05, freq: 80, harmonics: [] },
    { file: "step_stone_02.ogg", seconds: 0.055, freq: 72, harmonics: [] },
    { file: "step_wood_01.ogg", seconds: 0.05, freq: 95, harmonics: [{ freq: 190, amp: 0.03 }] },
    { file: "step_water_01.ogg", seconds: 0.06, freq: 110, harmonics: [] },
    { file: "windup_01.ogg", seconds: 0.22, freq: 72, harmonics: [{ freq: 144, amp: 0.06 }] },
    { file: "ui_click_01.ogg", seconds: 0.04, freq: 520, harmonics: [{ freq: 1040, amp: 0.05 }] },
    { file: "brazier_loop.ogg", seconds: 4, freq: 55, harmonics: [], noise: 0.08 },
    { file: "fountain_loop.ogg", seconds: 5, freq: 88, harmonics: [{ freq: 176, amp: 0.04 }], noise: 0.03 },
  ];
  for (const spec of specs) {
    const samples =
      spec.noise != null && spec.noise > 0
        ? generateLoop(spec.seconds, spec.freq, spec.harmonics, spec.noise)
        : generateBurst(spec.seconds, spec.freq, spec.harmonics);
    writeOggFromSamples(join(sfxDir, spec.file), samples);
    console.log(`OK: sfx/${spec.file}`);
  }
  return specs.length;
}

if (CHECK_ONLY) {
  runCheck();
}

requireFfmpeg();
const biomeCount = generateBiomeStems();
const stingerCount = generateSharedStingers();
const sfxCount = generateSfx();
console.log(`Generated ${biomeCount} biome stems, ${stingerCount} stingers, ${sfxCount} SFX samples.`);
