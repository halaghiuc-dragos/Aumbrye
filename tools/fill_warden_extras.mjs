import fs from "fs";
import path from "path";

const ROOT = path.resolve(
  path.dirname(new URL(import.meta.url).pathname).replace(/^\/([A-Za-z]:)/, "$1"),
  ".."
);
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

function writeJson(p, obj) {
  const raw = fs.readFileSync(p, "utf8");
  const eol = raw.includes("\r\n") ? "\r\n" : "\n";
  fs.writeFileSync(p, JSON.stringify(obj, null, 2).replace(/\n/g, eol) + eol);
}

let filled = 0;
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
  writeJson(vPath, v);
  filled++;
  console.log("filled", variant, "->", Object.keys(extras).join(", "));
}
console.log("manifests updated:", filled);
