#!/usr/bin/env node
import { readFileSync, readdirSync, existsSync, writeFileSync, mkdirSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const CONTENT = join(ROOT, "content");
const EQUIPMENT = join(CONTENT, "items/equipment");

const argValue = (flag, fallback) => {
  const index = process.argv.indexOf(flag);
  return index > -1 && process.argv[index + 1] ? process.argv[index + 1] : fallback;
};
const write = process.argv.includes("--write");
const updateCatalog = process.argv.includes("--catalog");
const biomeFilter = argValue("--biome", "");
const rarities = argValue("--rarity", "common,magic,rare").split(",").map((r) => r.trim()).filter(Boolean);

const RARITY_SCALE = { common: 1, magic: 1.25, rare: 1.55, epic: 1.9, legendary: 2.3 };
const RARITY_PREFIX = {
  common: "",
  magic: "Marked ",
  rare: "Wardens' ",
  epic: "Sepulchral ",
  legendary: "Unbroken ",
};

const bases = JSON.parse(readFileSync(join(ROOT, "tools/item_bases.json"), "utf8"));
const biomes = readdirSync(join(CONTENT, "biomes"))
  .filter((f) => f.endsWith(".json"))
  .map((f) => JSON.parse(readFileSync(join(CONTENT, "biomes", f), "utf8")))
  .filter((b) => (biomeFilter ? b.id === biomeFilter : true));

const materialTiers = bases.materialTiers ?? [];
const materialFor = (biome, index) => {
  const matched = materialTiers.find(
    (m) => String(m.id) === String(biome.templatePrefix) || String(m.id) === String(biome.id)
  );
  if (matched) return matched;
  if (materialTiers.length === 0) return { id: biome.templatePrefix ?? biome.id, noun: biome.name, tier: 1 };
  return materialTiers[index % materialTiers.length];
};

const existing = new Set(
  existsSync(EQUIPMENT)
    ? readdirSync(EQUIPMENT).filter((f) => f.endsWith(".json")).map((f) => f.replace(/\.json$/, ""))
    : []
);

const round = (value, places = 2) => Number(value.toFixed(places));

const generated = [];
biomes.forEach((biome, biomeIndex) => {
  const material = materialFor(biome, biomeIndex);
  const materialId = String(material.id ?? biome.templatePrefix ?? biome.id);
  const materialNoun = String(material.noun ?? material.name ?? materialId);
  const materialTier = Number(material.tier ?? biomeIndex + 1);
  for (const archetype of bases.archetypes ?? []) {
    for (const rarity of rarities) {
      const scale = (RARITY_SCALE[rarity] ?? 1) * (1 + 0.18 * (materialTier - 1));
      const id = `${materialId}_${archetype.id}_${rarity}`;
      if (existing.has(id)) continue;
      const stats = {};
      for (const [key, value] of Object.entries(archetype.implicit ?? {})) {
        stats[key] = round(Number(value) * scale, key.endsWith("Chance") || key.endsWith("Percent") ? 3 : 1);
      }
      const item = {
        id,
        name: `${RARITY_PREFIX[rarity] ?? ""}${materialNoun} ${archetype.noun}`.trim(),
        itemType: archetype.itemType,
        equipmentSlot: archetype.equipmentSlot,
        gridWidth: archetype.gridWidth,
        gridHeight: archetype.gridHeight,
        stackSize: 1,
        rarity,
        description: String(archetype.line ?? "Forged where the light does not reach."),
        value: Math.max(1, Math.round(Number(archetype.baseValue ?? 20) * scale)),
        stats,
      };
      if (archetype.weaponId) item.weaponId = archetype.weaponId;
      if (archetype.maxDurability) item.maxDurability = Math.round(Number(archetype.maxDurability) * scale);
      generated.push({ biomeId: biome.id, item });
    }
  }
});

if (!write) {
  console.log(`${generated.length} item(s) would be generated across ${biomes.length} biome(s).`);
  for (const row of generated.slice(0, 10)) console.log(`  ${row.biomeId}  ${row.item.id}  ${row.item.name}`);
  if (generated.length > 10) console.log(`  ... and ${generated.length - 10} more`);
  console.log("Pass --write to emit files, --catalog to register them.");
} else {
  mkdirSync(EQUIPMENT, { recursive: true });
  for (const row of generated) {
    writeFileSync(join(EQUIPMENT, `${row.item.id}.json`), `${JSON.stringify(row.item, null, 2)}\n`);
  }
  if (updateCatalog) {
    const catalogPath = join(CONTENT, "items/catalog.json");
    const catalog = JSON.parse(readFileSync(catalogPath, "utf8"));
    const merged = new Set([...(catalog.equipment ?? []), ...generated.map((row) => row.item.id)]);
    catalog.equipment = [...merged].sort();
    writeFileSync(catalogPath, `${JSON.stringify(catalog, null, 2)}\n`);
  }
  console.log(`Wrote ${generated.length} item file(s)${updateCatalog ? " and updated the catalog" : ""}.`);
  console.log("Run tools/reachability-check.mjs — generated items still need a loot table entry.");
}
