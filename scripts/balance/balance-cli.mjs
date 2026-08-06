#!/usr/bin/env node
/**
 * Balance export CLI — reads content/ and writes reports/balance_export.json.
 * Usage: node scripts/balance/balance-cli.mjs [--summary] [--fail-on-outliers <ratio>]
 */

import { existsSync, mkdirSync, readFileSync, readdirSync, statSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(__dirname, "../..");
const contentRoot = join(repoRoot, "content");
const reportsDir = join(repoRoot, "reports");
const exportPath = join(reportsDir, "balance_export.json");

const args = process.argv.slice(2);
const showSummary = args.includes("--summary");
let failRatio = null;
for (let i = 0; i < args.length; i++) {
  if (args[i] === "--fail-on-outliers" && i + 1 < args.length) {
    failRatio = Number(args[i + 1]);
  }
}

function readJson(path) {
  return JSON.parse(readFileSync(path, "utf8"));
}

function listJsonFiles(dir) {
  if (!statSync(dir).isDirectory()) return [];
  const results = [];
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry);
    if (statSync(full).isDirectory()) {
      results.push(...listJsonFiles(full));
    } else if (entry.endsWith(".json")) {
      results.push(full);
    }
  }
  return results;
}

function statTotal(stats) {
  if (!stats || typeof stats !== "object") return 0;
  return Object.values(stats).reduce((sum, v) => sum + Number(v), 0);
}

function median(values) {
  if (values.length === 0) return 0;
  const sorted = [...values].sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  return sorted.length % 2 === 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid];
}

function linearSlope(xs, ys) {
  if (xs.length < 2) return 0;
  const n = xs.length;
  const sumX = xs.reduce((a, b) => a + b, 0);
  const sumY = ys.reduce((a, b) => a + b, 0);
  const sumXY = xs.reduce((acc, x, i) => acc + x * ys[i], 0);
  const sumXX = xs.reduce((acc, x) => acc + x * x, 0);
  const denom = n * sumXX - sumX * sumX;
  if (denom === 0) return 0;
  return (n * sumXY - sumX * sumY) / denom;
}

function weaponDps(weapon) {
  const attacks = weapon.light_attacks ?? [];
  if (attacks.length === 0) return 0;
  let totalDps = 0;
  for (const atk of attacks) {
    const damage = Number(atk.damage ?? 0);
    const cycle = Number(atk.startup ?? 0) + Number(atk.active ?? 0) + Number(atk.recovery ?? 0);
    totalDps += cycle > 0 ? damage / cycle : 0;
  }
  return totalDps / attacks.length;
}

function weaponStaminaPerDamage(weapon) {
  const attacks = weapon.light_attacks ?? [];
  if (attacks.length === 0) return 0;
  let total = 0;
  let count = 0;
  for (const atk of attacks) {
    const damage = Number(atk.damage ?? 0);
    const stamina = Number(atk.stamina_cost ?? 0);
    if (damage > 0) {
      total += stamina / damage;
      count++;
    }
  }
  return count > 0 ? total / count : 0;
}

function loadEnemies() {
  const enemyDirs = [join(contentRoot, "enemies"), join(contentRoot, "bosses")];
  const enemies = [];
  for (const dir of enemyDirs) {
    for (const file of listJsonFiles(dir)) {
      enemies.push(readJson(file));
    }
  }
  return enemies;
}

function loadBiomes() {
  const dir = join(contentRoot, "biomes");
  return listJsonFiles(dir).map(readJson);
}

function loadItems() {
  const dirs = [
    join(contentRoot, "items", "equipment"),
    join(contentRoot, "items", "consumables"),
    join(contentRoot, "items", "materials"),
    join(contentRoot, "relics"),
  ];
  const items = [];
  for (const dir of dirs) {
    for (const file of listJsonFiles(dir)) {
      items.push(readJson(file));
    }
  }
  return items;
}

function loadWeapons() {
  const dir = join(contentRoot, "weapons");
  return listJsonFiles(dir).map((file) => {
    const data = readJson(file);
    return { ...data, _path: file };
  });
}

function buildExport() {
  const enemies = loadEnemies();
  const biomes = loadBiomes();
  const items = loadItems();
  const weapons = loadWeapons();

  const threatCostHistogram = {};
  const threatCosts = [];
  const healths = [];
  for (const enemy of enemies) {
    const cost = Number(enemy.threat_cost ?? 0);
    const key = String(cost);
    threatCostHistogram[key] = (threatCostHistogram[key] ?? 0) + 1;
    if (cost > 0) {
      threatCosts.push(cost);
      healths.push(Number(enemy.health ?? 0));
    }
  }

  const byBiome = {};
  for (const biome of biomes) {
    const pool = biome.enemyPool ?? [];
    const ids = new Set(pool.map((e) => e.enemyId ?? e.enemy_id).filter(Boolean));
    byBiome[biome.id] = ids.size;
  }

  const byRarity = {};
  const byEquipmentSlot = {};
  const statTotalsByRarity = {};
  const statTotalsPerRarity = {};
  let unauthoredCount = 0;

  for (const item of items) {
    const rarity = item.rarity ?? "common";
    byRarity[rarity] = (byRarity[rarity] ?? 0) + 1;
    const slot = item.equipmentSlot ?? item.itemType ?? "none";
    byEquipmentSlot[slot] = (byEquipmentSlot[slot] ?? 0) + 1;
    const total = statTotal(item.stats);
    if (!statTotalsPerRarity[rarity]) statTotalsPerRarity[rarity] = [];
    statTotalsPerRarity[rarity].push(total);
    if (item.authored === false) unauthoredCount++;
  }

  for (const [rarity, totals] of Object.entries(statTotalsPerRarity)) {
    statTotalsByRarity[rarity] = median(totals);
  }

  const dpsByWeaponId = {};
  const staminaPerDamage = {};
  for (const weapon of weapons) {
    dpsByWeaponId[weapon.id] = Number(weaponDps(weapon).toFixed(2));
    staminaPerDamage[weapon.id] = Number(weaponStaminaPerDamage(weapon).toFixed(3));
  }

  const xpPath = join(contentRoot, "progression", "xp_curve.json");
  const xpCurve = readJson(xpPath);
  const levels = xpCurve.levels ?? [];
  const levelCap = levels.length > 0 ? Number(levels[levels.length - 1].level ?? levels.length) : 0;
  const xpToLevel = levels.map((row) => Number(row.xpRequired ?? 0));
  const maxXp = xpToLevel.length > 0 ? xpToLevel[xpToLevel.length - 1] : 0;
  const baseXp = Number(xpCurve.baseXpPerKill ?? 25);
  const runsToLevelCap = baseXp > 0 ? Number((maxXp / baseXp).toFixed(2)) : 0;

  const outlierThreshold = 2.0;
  const outliers = [];
  for (const item of items) {
    const rarity = item.rarity ?? "common";
    const total = statTotal(item.stats);
    const med = statTotalsByRarity[rarity] ?? 0;
    if (med > 0 && total > med * outlierThreshold) {
      outliers.push({
        kind: "item_stat_total",
        id: item.id,
        value: Number(total.toFixed(2)),
        medianForRarity: Number(med.toFixed(2)),
        ratio: Number((total / med).toFixed(2)),
      });
    }
  }

  return {
    schemaVersion: 1,
    generatedAt: new Date().toISOString(),
    enemies: {
      count: enemies.length,
      byBiome,
      threatCostHistogram,
      hpPerLevelSlope: Number(linearSlope(threatCosts, healths).toFixed(4)),
    },
    items: {
      count: items.length,
      byRarity,
      byEquipmentSlot,
      statTotalsByRarity,
      unauthoredCount,
    },
    weapons: {
      count: weapons.length,
      dpsByWeaponId,
      staminaPerDamage,
    },
    progression: {
      levelCap,
      xpToLevel,
      runsToLevelCap,
    },
    outliers,
  };
}

const report = buildExport();
if (!existsSync(reportsDir)) {
  mkdirSync(reportsDir, { recursive: true });
}
writeFileSync(exportPath, `${JSON.stringify(report, null, 2)}\n`, "utf8");

if (showSummary) {
  console.log("Per-rarity stat-total medians:");
  for (const [rarity, med] of Object.entries(report.items.statTotalsByRarity).sort()) {
    console.log(`  ${rarity}: ${med.toFixed(2)}`);
  }
  console.log("\nOutliers (stat total > 2× median for rarity):");
  if (report.outliers.length === 0) {
    console.log("  (none)");
  } else {
    for (const o of report.outliers) {
      console.log(`  ${o.id} (${o.ratio}× median, total=${o.value})`);
    }
  }
}

if (failRatio != null) {
  const exceeded = report.outliers.filter((o) => o.ratio > failRatio);
  if (exceeded.length > 0) {
    console.error(`FAIL: ${exceeded.length} outlier(s) exceed ratio ${failRatio}`);
    process.exit(1);
  }
}

console.log(`Exported balance report to ${exportPath}`);
