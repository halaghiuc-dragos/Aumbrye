import fs from "fs";
import path from "path";
import { fileURLToPath } from "node:url";
import { publishGeneratedAssetSet } from "../scripts/tools/generated_asset_set.mjs";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const DIR = path.join(ROOT, "content/characters");

const BASE_FOR = {
  player_warden_heavy: "player_warden",
  player_warden_lean: "player_warden",
  player_warden_compact_heavy: "player_warden_compact",
  player_warden_compact_lean: "player_warden_compact",
  player_warden_tall_heavy: "player_warden_tall",
  player_warden_tall_lean: "player_warden_tall",
};

function readJson(p) {
  return JSON.parse(fs.readFileSync(p, "utf8"));
}

let filled = 0;
const outputs = [];
for (const [variant, base] of Object.entries(BASE_FOR)) {
  const vPath = path.join(DIR, variant + ".json");
  const bPath = path.join(DIR, base + ".json");
  if (!fs.existsSync(vPath) || !fs.existsSync(bPath)) {
    console.log("SKIP missing file:", variant);
    continue;
  }
  const v = readJson(vPath);
  const b = readJson(bPath);
  if (v.extras && Object.keys(v.extras).length > 0) {
    console.log("SKIP already has extras:", variant);
    continue;
  }
  if (!b.extras || Object.keys(b.extras).length === 0) {
    console.log("SKIP base has no extras:", base);
    continue;
  }
  const parts = Object.keys(v.parts || {});
  const extras = {};
  for (const [name, def] of Object.entries(b.extras)) {
    if (!parts.includes(String(def.parent))) {
      console.log("  SKIP extra", name, "- parent", def.parent, "not in", variant);
      continue;
    }
    const meshPath = String(def.mesh);
    const rel = meshPath.replace("res://", "apps/game/client/");
    if (!fs.existsSync(path.join(ROOT, rel))) {
      console.log("  SKIP extra", name, "- mesh missing:", meshPath);
      continue;
    }
    extras[name] = JSON.parse(JSON.stringify(def));
  }
  if (Object.keys(extras).length === 0) {
    console.log("SKIP no usable extras:", variant);
    continue;
  }
  v.extras = extras;
  outputs.push({ path: vPath, buffer: Buffer.from(`${JSON.stringify(v, null, 2)}\n`) });
  filled++;
  console.log("filled", variant, "->", Object.keys(extras).join(", "));
}
if (outputs.length > 0) {
  const sources = [...new Set(outputs.flatMap(({ path: outputPath }) => {
    const variant = path.basename(outputPath, ".json");
    const base = BASE_FOR[variant];
    return [outputPath, path.join(DIR, `${base}.json`)];
  }))];
  const published = publishGeneratedAssetSet({
    repoRoot: ROOT,
    manifestPath: path.join(ROOT, "tools/.generated-manifest.json"),
    generatorPath: fileURLToPath(import.meta.url),
    sourcePaths: sources,
    outputs,
    force: process.argv.includes("--force"),
    dryRun: process.argv.includes("--dry-run"),
  });
  console.log(process.argv.includes("--dry-run") ? "outputs validated:" : "outputs published:", published.length);
}
console.log("manifests updated:", filled);
