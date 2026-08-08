#!/usr/bin/env node
import { readFileSync, readdirSync, existsSync, mkdirSync, writeFileSync, statSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const CONTENT = join(ROOT, "content");
const outArg = process.argv.indexOf("--out");
const OUT = resolve(ROOT, outArg > -1 ? process.argv[outArg + 1] : "artifacts/balance");

function jsonFiles(relDir) {
  const dir = join(CONTENT, relDir);
  if (!existsSync(dir) || !statSync(dir).isDirectory()) return [];
  return readdirSync(dir)
    .filter((f) => f.endsWith(".json"))
    .map((f) => JSON.parse(readFileSync(join(dir, f), "utf8")));
}

const cell = (value) => {
  if (value === undefined || value === null) return "";
  const text = String(value);
  return /[",\n]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text;
};
const toCsv = (columns, rows) =>
  [columns.join(","), ...rows.map((row) => columns.map((c) => cell(row[c])).join(","))].join("\n") + "\n";

const biomes = jsonFiles("biomes");
const poolOf = new Map();
for (const biome of biomes) {
  for (const key of ["enemyPool", "bossPool"]) {
    for (const row of biome[key] ?? []) {
      if (!poolOf.has(row.enemyId)) poolOf.set(row.enemyId, []);
      poolOf.get(row.enemyId).push(`${biome.id}:${row.weight ?? 1}`);
    }
  }
}

const dps = (unit) => {
  const windup = Number(unit.windup_duration ?? 0);
  const active = Number(unit.active_duration ?? 0);
  const recovery = Number(unit.recovery_duration ?? 0);
  const cooldown = Number(unit.attack_cooldown ?? 0);
  const cycle = windup + active + recovery + cooldown;
  return cycle > 0 ? (Number(unit.attack_damage ?? 0) / cycle).toFixed(2) : "";
};

const unitRow = (unit, kind) => ({
  id: unit.id,
  kind,
  name: unit.name,
  type: unit.enemy_type ?? "",
  threatCost: unit.threat_cost ?? "",
  health: unit.health ?? "",
  poise: unit.poise ?? "",
  moveSpeed: unit.move_speed ?? "",
  attackDamage: unit.attack_damage ?? "",
  poiseDamage: unit.attack_poise_damage ?? "",
  windup: unit.windup_duration ?? "",
  recovery: unit.recovery_duration ?? "",
  cooldown: unit.attack_cooldown ?? "",
  attacks: (unit.attacks ?? []).length,
  damagePerSecond: dps(unit),
  pools: (poolOf.get(unit.id) ?? []).join(" | "),
});

const unitRows = [
  ...jsonFiles("enemies").map((e) => unitRow(e, "enemy")),
  ...jsonFiles("bosses").map((e) => unitRow(e, "boss")),
];

const weaponRows = jsonFiles("weapons").map((weapon) => {
  const light = weapon.light_attacks ?? [];
  const heavy = weapon.heavy_attacks ?? [];
  const sum = (rows, key) => rows.reduce((total, row) => total + Number(row[key] ?? 0), 0);
  return {
    id: weapon.id,
    name: weapon.name,
    archetype: weapon.archetype ?? "",
    damageType: weapon.damage_type ?? "",
    lightHits: light.length,
    lightDamage: sum(light, "damage"),
    lightStamina: sum(light, "stamina_cost"),
    heavyHits: heavy.length,
    heavyDamage: sum(heavy, "damage"),
    heavyStamina: sum(heavy, "stamina_cost"),
    physicalScaling: weapon.scaling?.physicalDamage ?? "",
    poiseScaling: weapon.scaling?.poiseDamage ?? "",
  };
});

const tierRows = [];
for (const dungeon of jsonFiles("dungeons")) {
  for (const tier of dungeon.difficultyTiers ?? []) {
    tierRows.push({
      dungeonId: dungeon.id,
      order: dungeon.order ?? "",
      tier: tier.tier,
      label: tier.label ?? "",
      hpMult: tier.hpMult ?? "",
      damageMult: tier.damageMult ?? "",
      lootBonus: tier.lootBonus ?? "",
      modifiers: (tier.modifiers ?? []).join(" | "),
      floorHpGrowth: dungeon.floorHpGrowth ?? "",
      floorDamageGrowth: dungeon.floorDamageGrowth ?? "",
    });
  }
}

const itemRows = [];
for (const sub of ["equipment", "consumables", "materials"]) {
  for (const item of jsonFiles(join("items", sub))) {
    const stats = item.stats ?? {};
    itemRows.push({
      id: item.id,
      category: sub,
      name: item.name,
      itemType: item.itemType ?? "",
      slot: item.equipmentSlot ?? "",
      rarity: item.rarity ?? "",
      value: item.value ?? "",
      maxDurability: item.maxDurability ?? "",
      statCount: Object.keys(stats).length,
      statTotal: Object.values(stats).reduce((total, v) => total + (Number(v) || 0), 0),
      stats: Object.entries(stats).map(([k, v]) => `${k}=${v}`).join(" | "),
    });
  }
}

mkdirSync(OUT, { recursive: true });
const written = [
  ["units.csv", toCsv(Object.keys(unitRows[0] ?? { id: "" }), unitRows)],
  ["weapons.csv", toCsv(Object.keys(weaponRows[0] ?? { id: "" }), weaponRows)],
  ["dungeon_tiers.csv", toCsv(Object.keys(tierRows[0] ?? { dungeonId: "" }), tierRows)],
  ["items.csv", toCsv(Object.keys(itemRows[0] ?? { id: "" }), itemRows)],
];
for (const [name, body] of written) writeFileSync(join(OUT, name), body);

console.log(`Wrote ${written.length} sheet(s) to ${OUT}`);
console.log(`  units ${unitRows.length}, weapons ${weaponRows.length}, tiers ${tierRows.length}, items ${itemRows.length}`);
