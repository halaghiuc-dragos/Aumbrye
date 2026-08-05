#!/usr/bin/env node
/**
 * Generate distinct procedural placeholder OGG loops per biome from audio profile freqs.
 * Each biome gets unique ambience + boss stems (not byte-identical castle copies).
 */
import { readdirSync, readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { execFileSync } from "node:child_process";

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = join(__dirname, "..", "..");
const profilesDir = join(repoRoot, "content", "audio_profiles");
const clientAudio = join(repoRoot, "apps", "game", "client", "assets", "audio");

const SAMPLE_RATE = 44100;
const AMBIENCE_SEC = 8;
const BOSS_SEC = 6;

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

function generateLoop(seconds, baseFreq, harmonics = []) {
  const total = Math.floor(SAMPLE_RATE * seconds);
  const out = new Float32Array(total);
  for (let i = 0; i < total; i++) {
    const t = i / SAMPLE_RATE;
    const loopEnv = 0.5 + 0.5 * Math.sin((2 * Math.PI * t) / seconds);
    let sample = Math.sin(2 * Math.PI * baseFreq * t) * 0.22;
    for (const h of harmonics) {
      sample += Math.sin(2 * Math.PI * h.freq * t) * h.amp;
    }
    const fade = Math.min(1, i / (SAMPLE_RATE * 0.05), (total - i) / (SAMPLE_RATE * 0.05));
    out[i] = sample * loopEnv * fade;
  }
  return out;
}

function wavToOgg(wavPath, oggPath) {
  execFileSync(
    "ffmpeg",
    ["-y", "-i", wavPath, "-c:a", "libvorbis", "-q:a", "4", oggPath],
    { stdio: "pipe" }
  );
}

const profileFiles = readdirSync(profilesDir).filter((f) => f.endsWith(".json"));
void profileFiles;

const files = profileFiles;
let generated = 0;

for (const file of files) {
  const profile = JSON.parse(readFileSync(join(profilesDir, file), "utf8"));
  const biomeId = profile.biomeId || profile.id;
  const ambienceFreq = Number(profile.ambienceFreq ?? 110);
  const bossFreq = Number(profile.bossFreq ?? 196);
  const exploreFreq = Number(profile.exploreFreq ?? ambienceFreq);
  const outDir = join(clientAudio, biomeId);
  mkdirSync(outDir, { recursive: true });

  const ambienceWav = join(outDir, "_ambience_tmp.wav");
  const bossWav = join(outDir, "_boss_tmp.wav");
  const ambienceOgg = join(outDir, "ambience_loop.ogg");
  const bossOgg = join(outDir, "boss_theme.ogg");

  const ambHarmonics = [
    { freq: exploreFreq * 0.5, amp: 0.08 },
    { freq: ambienceFreq * 1.5, amp: 0.05 },
  ];
  const bossHarmonics = [
    { freq: bossFreq * 0.5, amp: 0.1 },
    { freq: bossFreq * 1.25, amp: 0.06 },
  ];

  writeWav(ambienceWav, generateLoop(AMBIENCE_SEC, ambienceFreq, ambHarmonics));
  writeWav(bossWav, generateLoop(BOSS_SEC, bossFreq, bossHarmonics));
  wavToOgg(ambienceWav, ambienceOgg);
  wavToOgg(bossWav, bossOgg);

  try {
    execFileSync("rm", [ambienceWav, bossWav], { stdio: "ignore" });
  } catch {
    try {
      execFileSync("del", ["/f", "/q", ambienceWav, bossWav], { stdio: "ignore", shell: true });
    } catch {
      /* temp wav cleanup best-effort */
    }
  }

  generated += 2;
  console.log(`OK: ${biomeId} ambience=${ambienceFreq}Hz boss=${bossFreq}Hz`);
}

console.log(`Generated ${generated} distinct OGG loops for ${files.length} biomes.`);
