import fs from "fs";
import path from "path";

const ROOT = path.resolve(path.dirname(new URL(import.meta.url).pathname).replace(/^\/([A-Za-z]:)/, "$1"), "..");
const ITEM_DIRS = ["equipment", "consumables", "materials", "quest"];
const SLOTS = ["treasure", "secret", "side", "armory"];

const TIER_BIOME = {
  pitiron: "forgotten_castle",
  graysteel: "iron_vault",
  mirebrass: "poison_swamp",
  hoarfrost: "frozen_fortress",
  reliquary: "dark_cathedral",
  spellglass: "crystal_caverns",
};

const PAIRED = {
  venom_mire: "poison_swamp",
  glacial_hollow: "frozen_fortress",
  prism_depths: "crystal_caverns",
  umbral_chapel: "dark_cathedral",
};

const RARITY_WEIGHT = {
  common: 10,
  uncommon: 7,
  magic: 6,
  rare: 4,
  epic: 2,
  legendary: 1,
  aumbral: 1,
};

function readJson(p) {
  return JSON.parse(fs.readFileSync(p, "utf8"));
}

function writeJson(p, obj) {
  const eol = fs.existsSync(p) && fs.readFileSync(p, "utf8").includes("\r\n") ? "\r\n" : "\n";
  fs.writeFileSync(p, JSON.stringify(obj, null, 2).replace(/\n/g, eol) + eol);
}

function loadItems() {
  const items = {};
  for (const dir of ITEM_DIRS) {
    const full = path.join(ROOT, "content/items", dir);
    for (const f of fs.readdirSync(full)) {
      if (!f.endsWith(".json")) continue;
      const o = readJson(path.join(full, f));
      items[o.id] = { ...o, _dir: dir };
    }
  }
  return items;
}

function biomeIds() {
  return fs
    .readdirSync(path.join(ROOT, "content/biomes"))
    .filter((f) => f.endsWith(".json"))
    .map((f) => f.replace(".json", ""));
}

function reachableToday(items) {
  const reach = new Set();
  const tablesDir = path.join(ROOT, "content/loot/tables");
  for (const f of fs.readdirSync(tablesDir)) {
    const t = readJson(path.join(tablesDir, f));
    for (const slot of Object.keys(t.lootTables || {})) {
      for (const e of t.lootTables[slot]) reach.add(e.itemId);
    }
  }
  for (const e of readJson(path.join(ROOT, "content/loot/global_drops.json")).skipItems) reach.add(e.itemId);
  for (const sub of ["recipes", "merchant"]) {
    const dir = path.join(ROOT, "content", sub);
    if (!fs.existsSync(dir)) continue;
    for (const f of fs.readdirSync(dir)) {
      const raw = fs.readFileSync(path.join(dir, f), "utf8");
      for (const id of Object.keys(items)) if (raw.includes('"' + id + '"')) reach.add(id);
    }
  }
  return reach;
}

function homeBiome(item, biomes) {
  if (item.biomeId && biomes.includes(item.biomeId)) return item.biomeId;
  if (item.materialTier && TIER_BIOME[item.materialTier]) return TIER_BIOME[item.materialTier];
  return null;
}

function quantityFor(item) {
  if (item._dir === "materials") return [1, 3];
  if (item._dir === "consumables") return item.stackSize > 4 ? [1, 3] : [1, 1];
  return [1, 1];
}

function slotFor(item) {
  const rarity = item.rarity || "common";
  if (item.id.startsWith("unique_")) return "secret";
  if (item._dir === "equipment") return rarity === "epic" || rarity === "legendary" || rarity === "aumbral" ? "secret" : "armory";
  if (item._dir === "materials") return "side";
  return "treasure";
}

function build() {
  const items = loadItems();
  const biomes = biomeIds();
  const reach = reachableToday(items);
  const orphans = Object.keys(items).filter((id) => !reach.has(id));

  const tables = {};
  for (const b of biomes) tables[b] = { treasure: [], secret: [], side: [], armory: [] };

  const shared = [];
  for (const id of orphans) {
    const item = items[id];
    const home = homeBiome(item, biomes);
    if (home) {
      tables[home][slotFor(item)].push({ itemId: id, quantity: quantityFor(item), weight: RARITY_WEIGHT[item.rarity || "common"] || 4 });
      for (const [child, parent] of Object.entries(PAIRED)) {
        if (parent === home && item.id.startsWith("unique_")) {
          tables[child].secret.push({ itemId: id, quantity: [1, 1], weight: 1 });
        }
      }
    } else {
      shared.push(id);
    }
  }

  shared.forEach((id, i) => {
    const item = items[id];
    const b = biomes[i % biomes.length];
    tables[b][slotFor(item)].push({ itemId: id, quantity: quantityFor(item), weight: RARITY_WEIGHT[item.rarity || "common"] || 4 });
  });

  let written = 0;
  for (const b of biomes) {
    for (const slot of SLOTS) {
      if (tables[b][slot].length === 0) {
        const filler = tables[b].treasure[0] || tables[b].side[0] || tables[b].armory[0] || tables[b].secret[0];
        if (filler) tables[b][slot].push({ ...filler, weight: 2 });
      }
    }
    const outPath = path.join(ROOT, "content/loot/tables", b + ".json");
    const existing = fs.existsSync(outPath) ? readJson(outPath) : null;
    const merged = { schemaVersion: 1, biomeId: b, lootTables: { treasure: [], secret: [], side: [], armory: [] } };
    for (const slot of SLOTS) {
      const seen = new Set();
      const combined = [...(existing ? existing.lootTables[slot] || [] : []), ...tables[b][slot]];
      for (const e of combined) {
        if (seen.has(e.itemId)) continue;
        seen.add(e.itemId);
        merged.lootTables[slot].push(e);
      }
    }
    writeJson(outPath, merged);
    written++;

    const biomePath = path.join(ROOT, "content/biomes", b + ".json");
    const biome = readJson(biomePath);
    const rel = "content/loot/tables/" + b + ".json";
    if (biome.lootTablePath !== rel) {
      biome.lootTablePath = rel;
      writeJson(biomePath, biome);
    }
  }

  const nowReach = reachableToday(items);
  const stillOrphan = Object.keys(items).filter((id) => !nowReach.has(id));
  console.log("tables written:", written);
  console.log("items:", Object.keys(items).length, "reachable before:", reach.size, "after:", nowReach.size);
  console.log("still orphaned:", stillOrphan.length, stillOrphan.slice(0, 10));
}

build();
