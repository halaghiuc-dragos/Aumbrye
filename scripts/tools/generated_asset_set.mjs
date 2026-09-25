import {
  existsSync,
  mkdirSync,
  readFileSync,
  renameSync,
  writeFileSync,
} from "node:fs";
import { createHash, randomUUID } from "node:crypto";
import { basename, dirname, relative, resolve, sep } from "node:path";

const digest = (buffer) => createHash("sha256").update(buffer).digest("hex");

function repoRelative(repoRoot, path) {
  const absolute = resolve(path);
  const result = relative(repoRoot, absolute);
  if (result === ".." || result.startsWith(`..${sep}`) || resolve(repoRoot, result) !== absolute) {
    throw new Error(`Generated asset path must stay inside the repository: ${path}`);
  }
  return result.split(sep).join("/");
}

function validateBuffer(path, buffer) {
  if (!Buffer.isBuffer(buffer) || buffer.length === 0) {
    throw new Error(`Generated output is empty or not a Buffer: ${path}`);
  }
  if (path.endsWith(".json")) JSON.parse(buffer.toString("utf8"));
  if (path.endsWith(".png") && (buffer.length < 24
    || buffer.subarray(0, 8).toString("hex") !== "89504e470d0a1a0a"
    || buffer.subarray(12, 16).toString("ascii") !== "IHDR")) {
    throw new Error(`Generated PNG output has an invalid header: ${path}`);
  }
  if (path.endsWith(".ogg") && (buffer.length < 28 || buffer.subarray(0, 4).toString("ascii") !== "OggS")) {
    throw new Error(`Generated Ogg output has an invalid container header: ${path}`);
  }
  if (path.endsWith(".wav") && (buffer.length < 44
    || buffer.subarray(0, 4).toString("ascii") !== "RIFF"
    || buffer.subarray(8, 12).toString("ascii") !== "WAVE")) {
    throw new Error(`Generated WAV output has an invalid container header: ${path}`);
  }
}

/** Stage and validate the complete set before publishing; existing manual bytes require --force. */
export function publishGeneratedAssetSet({
  repoRoot,
  manifestPath,
  generatorPath,
  sourcePaths,
  seed,
  outputs,
  force = false,
  dryRun = false,
}) {
  const root = resolve(repoRoot);
  const manifestFile = resolve(manifestPath);
  const generatorFile = resolve(generatorPath);
  const generatorKey = repoRelative(root, generatorFile);
  const generatorBytes = readFileSync(generatorFile);
  const sourceHashes = {};
  for (const sourcePath of sourcePaths) {
    const sourceFile = resolve(sourcePath);
    sourceHashes[repoRelative(root, sourceFile)] = digest(readFileSync(sourceFile));
  }
  if (outputs.length === 0) throw new Error("Refusing to publish an empty generated asset set");

  const manifest = existsSync(manifestFile) ? JSON.parse(readFileSync(manifestFile, "utf8")) : {};
  const prepared = [];
  const outputKeys = new Set();
  for (const output of outputs) {
    const outputFile = resolve(output.path);
    const key = repoRelative(root, outputFile);
    if (outputKeys.has(key)) throw new Error(`Duplicate generated output path: ${key}`);
    outputKeys.add(key);
    validateBuffer(key, output.buffer);
    const existing = existsSync(outputFile) ? readFileSync(outputFile) : null;
    const existingHash = existing === null ? "" : digest(existing);
    const previous = manifest[key];
    const owned = typeof previous === "string"
      ? previous === existingHash
      : previous && previous.outputSha256 === existingHash;
    const differs = existing !== null && !existing.equals(output.buffer);
    if (differs && !owned && !force) {
      throw new Error(`Refusing to replace unregistered/manual asset ${key}; inspect it or pass --force`);
    }
    prepared.push({
      key,
      outputFile,
      buffer: output.buffer,
      manualOverride: differs && !owned && force,
    });
  }

  if (dryRun) return prepared.map((item) => item.key);

  const stagedOutputs = [];
  let stagedManifest = "";
  try {
    for (const item of prepared) {
      mkdirSync(dirname(item.outputFile), { recursive: true });
      const stagePath = `${item.outputFile}.${randomUUID()}.stage`;
      writeFileSync(stagePath, item.buffer, { flag: "wx" });
      if (!readFileSync(stagePath).equals(item.buffer)) {
        throw new Error(`Staged output verification failed: ${item.key}`);
      }
      stagedOutputs.push({ ...item, stagePath });
    }

    const nextManifest = { ...manifest };
    for (const item of prepared) {
      nextManifest[item.key] = {
        outputSha256: digest(item.buffer),
        generator: generatorKey,
        generatorSha256: digest(generatorBytes),
        sources: sourceHashes,
        seed,
        manualOverride: item.manualOverride,
      };
    }
    mkdirSync(dirname(manifestFile), { recursive: true });
    stagedManifest = `${manifestFile}.${randomUUID()}.stage`;
    writeFileSync(stagedManifest, `${JSON.stringify(nextManifest, null, 2)}\n`, { flag: "wx" });
    JSON.parse(readFileSync(stagedManifest, "utf8"));

    for (const item of stagedOutputs) renameSync(item.stagePath, item.outputFile);
    renameSync(stagedManifest, manifestFile);
    return prepared.map((item) => item.key);
  } catch (error) {
    // Keep any stage file for inspection/recovery; no cleanup command is issued here.
    throw error;
  }
}
