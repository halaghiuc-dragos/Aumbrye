#!/usr/bin/env node
/**
 * Generate procedural OGG stems and SFX for Aumbrye audio profiles and sfx bank.
 * Usage: node scripts/tools/generate-game-audio.mjs [--check]
 */
import {
  readdirSync,
  readFileSync,
  existsSync,
} from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { execFileSync } from "node:child_process";
import { createSeededRandom, readSeed } from "./seeded_rng.mjs";
import { publishGeneratedAssetSet } from "./generated_asset_set.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = join(__dirname, "..", "..");
const profilesDir = join(repoRoot, "content", "audio_profiles");
const clientAudio = join(repoRoot, "apps", "game", "client", "assets", "audio");
const sfxBankPath = join(repoRoot, "content", "audio", "sfx.json");

const SAMPLE_RATE = 44100;
const CHECK_ONLY = process.argv.includes("--check");
const GENERATION_SEED = readSeed(process.argv, 0x0a11d10);
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

function writeOggFromSamples(oggPath, samples) {
  const oggBuffer = wavToOgg(encodeWav(samples));
  if (oggBuffer.subarray(0, 4).toString("ascii") !== "OggS") {
    throw new Error(`ffmpeg returned an invalid Ogg stream for ${oggPath}`);
  }
  return { path: oggPath, buffer: oggBuffer };
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
      sample += (random() * 2 - 1) * noiseAmp * loopEnv;
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
    out[i] = (random() * 2 - 1) * amp * env;
  }
  return out;
}

// The game deliberately uses synthesis instead of a generic music bed so every generated stem
// has a readable melodic identity: dark orchestral harmony, a restrained tracker-like pulse and
// a little quantisation that sits naturally beside the pixel-diorama presentation.
const BIOME_SCORES = {
  forgotten_castle: { root: 38, scale: [0, 2, 3, 5, 7, 8, 10], bpm: 72, progression: [0, 5, 3, 4] },
  dark_cathedral: { root: 38, scale: [0, 1, 3, 5, 7, 8, 10], bpm: 60, progression: [0, 5, 1, 4] },
  crystal_caverns: { root: 40, scale: [0, 2, 4, 6, 7, 9, 11], bpm: 84, progression: [0, 3, 4, 1] },
  poison_swamp: { root: 33, scale: [0, 2, 3, 5, 7, 8, 11], bpm: 68, progression: [0, 5, 6, 4] },
  frozen_fortress: { root: 35, scale: [0, 2, 3, 5, 7, 9, 10], bpm: 76, progression: [0, 3, 5, 1] },
  prism_depths: { root: 42, scale: [0, 2, 4, 6, 7, 9, 11], bpm: 90, progression: [0, 4, 1, 5] },
  venom_mire: { root: 37, scale: [0, 1, 3, 5, 7, 8, 10], bpm: 70, progression: [0, 4, 5, 1] },
  glacial_hollow: { root: 41, scale: [0, 2, 3, 5, 7, 9, 10], bpm: 80, progression: [0, 5, 3, 1] },
  iron_vault: { root: 31, scale: [0, 1, 3, 5, 7, 8, 10], bpm: 96, progression: [0, 4, 1, 5] },
  umbral_chapel: { root: 35, scale: [0, 1, 3, 5, 6, 8, 10], bpm: 66, progression: [0, 4, 5, 1] },
};

function midiToFreq(midi) {
  return 440 * Math.pow(2, (midi - 69) / 12);
}

function saw(phase) {
  return 2 * (phase - Math.floor(phase + 0.5));
}

function voiceSample(voice, phase, vibrato) {
  if (voice === "brass") return Math.tanh((Math.sin(phase) * 0.72 + saw(phase) * 0.42) * 1.35);
  if (voice === "choir") return Math.sin(phase) * 0.68 + Math.sin(phase * 2) * 0.18 + Math.sin(phase * 3) * 0.08;
  if (voice === "bell") return Math.sin(phase) * 0.8 + Math.sin(phase * 2.71) * 0.28 + Math.sin(phase * 4.08) * 0.12;
  if (voice === "bass") return Math.sin(phase) * 0.76 + Math.sin(phase * 0.5) * 0.22;
  // Slightly detuned saw/triangle blend: orchestral string motion, rendered with tracker clarity.
  return saw(phase + vibrato) * 0.34 + Math.sin(phase) * 0.66;
}

function addOrchestralNote(out, start, seconds, freq, amp, voice = "strings") {
  const startFrame = Math.max(0, Math.floor(start * SAMPLE_RATE));
  const frames = Math.max(1, Math.floor(seconds * SAMPLE_RATE));
  const attack = Math.max(1, Math.floor(Math.min(0.035, seconds * 0.15) * SAMPLE_RATE));
  const release = Math.max(1, Math.floor(Math.min(0.16, seconds * 0.42) * SAMPLE_RATE));
  for (let i = 0; i < frames && startFrame + i < out.length; i++) {
    const progress = i / frames;
    const env = Math.min(1, i / attack, (frames - i) / release) * (voice === "bell" ? Math.exp(-progress * 2.6) : 1);
    const phase = 2 * Math.PI * freq * i / SAMPLE_RATE;
    const vibrato = voice === "strings" || voice === "choir" ? Math.sin(2 * Math.PI * 4.1 * i / SAMPLE_RATE) * 0.012 : 0;
    out[startFrame + i] += voiceSample(voice, phase, vibrato) * amp * env;
  }
}

function addDrum(out, start, type, amp) {
  const seconds = type === "kick" ? 0.22 : 0.075;
  const startFrame = Math.floor(start * SAMPLE_RATE);
  const frames = Math.floor(seconds * SAMPLE_RATE);
  for (let i = 0; i < frames && startFrame + i < out.length; i++) {
    const t = i / SAMPLE_RATE;
    const env = Math.exp(-t * (type === "kick" ? 18 : 50));
    const tone = Math.sin(2 * Math.PI * (type === "kick" ? 94 - t * 230 : 1600) * t);
    const noise = random() * 2 - 1;
    out[startFrame + i] += (type === "kick" ? tone * 0.82 + noise * 0.08 : noise * 0.82 + tone * 0.15) * amp * env;
  }
}

function scoreMidi(score, degree, octave = 0) {
  const scaleLength = score.scale.length;
  const wrapped = ((degree % scaleLength) + scaleLength) % scaleLength;
  return score.root + score.scale[wrapped] + 12 * (octave + Math.floor(degree / scaleLength));
}

function generateOrchestralStem(biomeId, layer) {
  const score = BIOME_SCORES[biomeId] ?? BIOME_SCORES.forgotten_castle;
  const seconds = layer === "ambience" ? 12 : layer === "explore" ? 14 : layer === "combat" ? 12 : 16;
  const out = new Float32Array(Math.floor(seconds * SAMPLE_RATE));
  const beat = 60 / score.bpm;
  const bar = beat * 4;
  const bars = Math.ceil(seconds / bar);
  const motif = [0, 2, 4, 2, 5, 4, 2, 1];

  for (let measure = 0; measure < bars; measure++) {
    const chordDegree = score.progression[measure % score.progression.length];
    const at = measure * bar;
    // Low strings and choir supply the dark orchestral bed in every layer.
    addOrchestralNote(out, at, bar * 0.98, midiToFreq(scoreMidi(score, chordDegree, -1)), 0.11, "bass");
    addOrchestralNote(out, at, bar * 0.96, midiToFreq(scoreMidi(score, chordDegree + 2, 0)), 0.045, "choir");
    addOrchestralNote(out, at, bar * 0.96, midiToFreq(scoreMidi(score, chordDegree + 4, 0)), 0.04, "choir");
    if (layer === "ambience") {
      if (measure % 2 === 0) addOrchestralNote(out, at + beat * 2.5, beat * 1.25, midiToFreq(scoreMidi(score, chordDegree + 4, 2)), 0.04, "bell");
      continue;
    }
    for (let step = 0; step < 8; step++) {
      const note = chordDegree + motif[(step + measure * 2) % motif.length];
      const start = at + step * beat * 0.5;
      const explore = layer === "explore";
      addOrchestralNote(out, start, beat * (explore ? 0.52 : 0.35), midiToFreq(scoreMidi(score, note, 1)), explore ? 0.052 : 0.065, explore ? "bell" : "strings");
    }
    if (layer === "combat" || layer === "boss") {
      for (let pulse = 0; pulse < 4; pulse++) {
        const start = at + pulse * beat;
        addDrum(out, start, "kick", layer === "boss" ? 0.19 : 0.13);
        addOrchestralNote(out, start, beat * 0.28, midiToFreq(scoreMidi(score, chordDegree + (pulse % 2 ? 4 : 2), 1)), layer === "boss" ? 0.12 : 0.085, "brass");
        addDrum(out, start + beat * 0.5, "snare", layer === "boss" ? 0.1 : 0.065);
      }
    }
    if (layer === "boss") {
      addOrchestralNote(out, at + beat * 2, beat * 1.6, midiToFreq(scoreMidi(score, chordDegree + 5, 2)), 0.09, "brass");
    }
  }
  let peak = 0;
  for (const sample of out) peak = Math.max(peak, Math.abs(sample));
  const gain = peak > 0 ? 0.76 / peak : 1;
  for (let i = 0; i < out.length; i++) {
    // Mild 12-bit quantisation retains a pixel-game edge without crushing the orchestral body.
    out[i] = Math.round(Math.max(-1, Math.min(1, out[i] * gain)) * 2048) / 2048;
  }
  return out;
}

function generateThematicStinger(kind) {
  const seconds = kind === "boss" ? 1.35 : kind === "clear" ? 1.05 : 0.65;
  const out = new Float32Array(Math.floor(seconds * SAMPLE_RATE));
  const notes = kind === "boss" ? [38, 41, 45, 50] : kind === "clear" ? [62, 65, 69, 74] : [69, 72, 76];
  notes.forEach((note, index) => addOrchestralNote(out, index * 0.075, seconds - index * 0.075, midiToFreq(note), index === 0 ? 0.22 : 0.12, kind === "boss" ? "brass" : "bell"));
  return out;
}

function generateMenuStem(kind) {
  const biome = kind === "title" ? "dark_cathedral" : "forgotten_castle";
  const layer = kind === "title" ? "boss" : "explore";
  const stem = generateOrchestralStem(biome, layer);
  // Menu themes should linger rather than arrive at combat volume.
  for (let i = 0; i < stem.length; i++) stem[i] *= kind === "title" ? 0.74 : 0.68;
  return stem;
}

function generateFoley(kind, variation = 0) {
  const seconds = kind.includes("windup") ? 0.34 : kind === "execution" ? 0.46 : kind === "dodge" ? 0.2 : 0.18;
  const out = new Float32Array(Math.floor(seconds * SAMPLE_RATE));
  const base = kind === "execution" ? 196 : kind.includes("armor") ? 235 : kind.includes("stone") ? 118 : kind === "dodge" ? 310 : 160;
  const start = variation * 0.03;
  addOrchestralNote(out, 0, seconds * 0.88, base * (1 + variation * 0.035), kind === "execution" ? 0.28 : 0.18, kind.includes("armor") || kind === "execution" ? "brass" : "strings");
  for (let i = 0; i < out.length; i++) {
    const t = i / SAMPLE_RATE;
    const env = Math.exp(-t * (kind.includes("windup") ? 4.5 : 16));
    const noise = (random() * 2 - 1) * (kind === "dodge" ? 0.13 : 0.08) * env;
    const sweep = Math.sin(2 * Math.PI * (base * (kind === "dodge" ? 2.2 - t * 4 : 1 + t * 0.8)) * t) * 0.08 * env;
    out[i] = Math.max(-1, Math.min(1, out[i] + noise + sweep + start * 0));
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
	const outputs = [];
  for (const file of readdirSync(profilesDir).filter((f) => f.endsWith(".json"))) {
    const profile = JSON.parse(readFileSync(join(profilesDir, file), "utf8"));
    const biomeId = profile.biomeId || profile.id;
    const layers = profile.layers ?? {};
	const specs = [
	  { name: "ambience_loop.ogg", layer: "ambience" },
	  { name: "explore_loop.ogg", layer: "explore" },
	  { name: "combat_loop.ogg", layer: "combat" },
	  { name: "boss_theme.ogg", layer: "boss" },
	];

    const outDir = join(clientAudio, biomeId);
    for (const spec of specs) {
      const oggPath = join(outDir, spec.name);
	  const samples = generateOrchestralStem(biomeId, spec.layer);
	  outputs.push(writeOggFromSamples(oggPath, samples));
    }
  }
  return outputs;
}

function generateSharedStingers() {
	const sharedDir = join(clientAudio, "shared");
	const specs = [
	  { file: "sting_boss.ogg", kind: "boss" },
	  { file: "sting_clear.ogg", kind: "clear" },
	  { file: "sting_secret.ogg", kind: "secret" },
	  { file: "sting_key.ogg", kind: "key" },
	  { file: "sting_lock.ogg", kind: "lock" },
	  { file: "sting_shortcut.ogg", kind: "shortcut" },
	  { file: "sting_rare_drop.ogg", kind: "rare" },
	  { file: "sting_personal_best.ogg", kind: "best" },
	  { file: "sting_poise_break.ogg", kind: "poise" },
	];
	for (const spec of specs) {
	  spec.output = writeOggFromSamples(
		join(sharedDir, spec.file),
		generateThematicStinger(spec.kind),
	  );
  }
  return specs.map((spec) => spec.output);
}

function generateSfx() {
	const sfxDir = join(clientAudio, "sfx");
	const specs = [
	  { file: "swing_03.ogg", kind: "swing", variation: 2 },
	  { file: "swing_04.ogg", kind: "swing", variation: 3 },
	  { file: "windup_02.ogg", kind: "windup", variation: 1 },
	  { file: "hit_armor_02.ogg", kind: "armor", variation: 1 },
	  { file: "hit_armor_03.ogg", kind: "armor", variation: 2 },
	  { file: "hit_stone_02.ogg", kind: "stone", variation: 1 },
	  { file: "hit_stone_03.ogg", kind: "stone", variation: 2 },
	  { file: "hit_crystal_02.ogg", kind: "crystal", variation: 1 },
	  { file: "hit_crystal_03.ogg", kind: "crystal", variation: 2 },
	  { file: "hit_bone_02.ogg", kind: "bone", variation: 1 },
	  { file: "hit_bone_03.ogg", kind: "bone", variation: 2 },
	  { file: "hit_ooze_02.ogg", kind: "ooze", variation: 1 },
	  { file: "hit_ooze_03.ogg", kind: "ooze", variation: 2 },
	  { file: "parry_02.ogg", kind: "armor", variation: 3 },
	  { file: "death_02.ogg", kind: "death", variation: 1 },
	  { file: "death_03.ogg", kind: "death", variation: 2 },
	  { file: "dodge_01.ogg", kind: "dodge", variation: 1 },
	  { file: "dodge_02.ogg", kind: "dodge", variation: 2 },
	  { file: "execution_01.ogg", kind: "execution", variation: 1 },
	  { file: "execution_02.ogg", kind: "execution", variation: 2 },
	];
	const outputs = [];
	for (const spec of specs) {
	  const samples = generateFoley(spec.kind, spec.variation);
    outputs.push(writeOggFromSamples(join(sfxDir, spec.file), samples));
  }
  return outputs;
}

if (CHECK_ONLY) {
  runCheck();
}

requireFfmpeg();
if (process.argv.includes("--self-test")) {
  const ogg = wavToOgg(encodeWav(generateLoop(0.02, 440, [], 0.03)));
  if (ogg.subarray(0, 4).toString("ascii") !== "OggS") throw new Error("Ogg self-test failed");
  console.log(`AUDIO STEM SELF-TEST PASS (seed ${GENERATION_SEED}; no files written)`);
  process.exit(0);
}
const biomeCount = generateBiomeStems();
const stingerCount = generateSharedStingers();
const sfxCount = generateSfx();
const menuCount = [
  writeOggFromSamples(join(clientAudio, "shared", "title_theme.ogg"), generateMenuStem("title")),
  writeOggFromSamples(join(clientAudio, "shared", "hub_theme.ogg"), generateMenuStem("hub")),
];
const outputs = [...biomeCount, ...stingerCount, ...sfxCount, ...menuCount];
const sourcePaths = [
  ...readdirSync(profilesDir)
    .filter((file) => file.endsWith(".json"))
    .map((file) => join(profilesDir, file)),
  sfxBankPath,
	join(repoRoot, "apps", "game", "client", "scripts", "audio", "audio_director.gd"),
];
const published = publishGeneratedAssetSet({
  repoRoot,
  manifestPath: join(repoRoot, "tools", ".generated-manifest.json"),
  generatorPath: fileURLToPath(import.meta.url),
  sourcePaths,
  seed: GENERATION_SEED,
  outputs,
  force: process.argv.includes("--force"),
});
console.log(`Published ${published.length} audio assets from ${sourcePaths.length} tracked inputs.`);
console.log(`Generation seed: ${GENERATION_SEED}`);
