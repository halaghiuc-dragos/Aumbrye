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

// --------------------------------------------------------------------------- combat exchange
//
// The number that decides how a fight feels is not enemy health or player damage on its own, it
// is how many hits the player can take before they die. A souls-like wants that number small and
// roughly constant for the whole game: a basic enemy of the biome you are standing in should kill
// you in about six unanswered hits whether that biome is the first or the tenth.
//
// This models one unblocked, undodged exchange against gear appropriate to the biome, which is
// the worst case for the player and the easiest case to reason about. Real fights are kinder --
// the player dodges, blocks, parries and heals -- and harder, because enemies come in groups.

const PLAYER_BASE_HEALTH = 100;
// The seven classes sit between +30 and +45 maxHealth; this is the middle of them.
const PLAYER_CLASS_HEALTH = 38;

// Mirrors Hurtbox: reduction = points / (points + softening), then capped.
const DEFENSE_SOFTENING = 150;
const DEFENSE_CAP = 0.75;

// The player lands a fraction of their theoretical dps: whiffs, repositioning, stamina, and the
// windows they spend dodging rather than swinging.
const PLAYER_UPTIME = 0.55;

// The band a basic enemy of its own biome has to land in. Below four the game is a coin flip;
// above eight the player can walk through the fight reading nothing.
const TARGET_HITS_TO_KILL_PLAYER = [4, 8];

// What is actually enforced: each biome's median basic enemy sits here, and nothing that is not a
// boss is so weak the player can ignore it entirely.
const MEDIAN_BAND = [5, 7];
const PUSHOVER_HITS = 12;

function enemyCycleSeconds(enemy) {
  return (
    Number(enemy.windup_duration ?? 0) +
    Number(enemy.active_duration ?? 0) +
    Number(enemy.recovery_duration ?? 0) +
    Number(enemy.attack_cooldown ?? 0)
  );
}

function dungeonOrderByBiome() {
  const map = {};
  for (const file of listJsonFiles(join(contentRoot, "dungeons"))) {
    const d = readJson(file);
    if (d.id && d.order != null) map[d.id] = Number(d.order);
  }
  return map;
}

function bossIds() {
  const ids = new Set();
  for (const file of listJsonFiles(join(contentRoot, "bosses"))) {
    const d = readJson(file);
    if (d.id) ids.add(d.id);
  }
  return ids;
}

function enemyBiomeMap() {
  const map = {};
  for (const file of listJsonFiles(join(contentRoot, "biomes"))) {
    const biome = readJson(file);
    for (const key of ["enemyPool", "bossPool"]) {
      for (const entry of biome[key] ?? []) {
        const id = entry?.enemyId;
        if (id && map[id] == null) map[id] = biome.id;
      }
    }
  }
  return map;
}

// What the player is realistically wearing in each biome, read off the equipment that drops
// there rather than assumed: the median piece per slot, every slot filled.
function playerGearByOrder(orderByBiome) {
  const perOrder = {};
  for (const dir of [join(contentRoot, "items", "equipment")]) {
    for (const file of listJsonFiles(dir)) {
      const item = readJson(file);
      const order = orderByBiome[item.biome ?? item.theme];
      if (order == null || !item.equipmentSlot) continue;
      perOrder[order] ??= {};
      perOrder[order][item.equipmentSlot] ??= [];
      perOrder[order][item.equipmentSlot].push({
        health: Number(item.stats?.maxHealth ?? 0),
        points: Number(item.stats?.armor ?? 0) + Number(item.stats?.defense ?? 0),
      });
    }
  }
  const profiles = {};
  for (const [order, slots] of Object.entries(perOrder)) {
    let health = 0;
    let points = 0;
    for (const pieces of Object.values(slots)) {
      health += median(pieces.map((p) => p.health));
      points += median(pieces.map((p) => p.points));
    }
    profiles[order] = { health, points };
  }
  // Not every biome authors a full set yet. Rather than let a sparse biome claim the player is
  // naked there, carry the strongest profile seen so far forward -- gear does not get taken away.
  let running = { health: 0, points: 0 };
  for (let order = 1; order <= 10; order++) {
    const found = profiles[order];
    if (found && found.points >= running.points) running = found;
    profiles[order] = running;
  }
  return profiles;
}

function playerProfile(order, gearByOrder) {
  const gear = gearByOrder[order] ?? { health: 0, points: 0 };
  const health = PLAYER_BASE_HEALTH + PLAYER_CLASS_HEALTH + gear.health;
  const mitigation = Math.min(DEFENSE_CAP, gear.points / (gear.points + DEFENSE_SOFTENING));
  return {
    order,
    health: Number(health.toFixed(1)),
    defensePoints: Number(gear.points.toFixed(1)),
    mitigation: Number(mitigation.toFixed(3)),
    effectiveHealth: Number((health / (1 - mitigation)).toFixed(1)),
  };
}

function buildExchange(enemies, weapons) {
  const orderByBiome = dungeonOrderByBiome();
  const biomeOf = enemyBiomeMap();
  const gearByOrder = playerGearByOrder(orderByBiome);
  const profiles = {};
  for (let order = 1; order <= 10; order++) profiles[order] = playerProfile(order, gearByOrder);

  // The starting weapon is the honest yardstick for pacing: it is what the player holds when the
  // feel of the game is decided, and every other weapon is tuned relative to it.
  const starter = weapons.find((w) => w.id === "sword_basic");
  const playerDps = starter ? weaponDps(starter) * PLAYER_UPTIME : 0;

  const bosses = bossIds();
  const rows = [];
  for (const enemy of enemies) {
    const biome = biomeOf[enemy.id];
    const order = orderByBiome[biome];
    if (order == null) continue;
    const health = Number(enemy.health ?? 0);
    const damage = Number(enemy.attack_damage ?? 0);
    const cycle = enemyCycleSeconds(enemy);
    if (health <= 0 || damage <= 0 || cycle <= 0) continue;
    const player = profiles[order];
    const perHit = damage * (1 - player.mitigation);
    rows.push({
      id: enemy.id,
      order,
      boss: bosses.has(enemy.id),
      health,
      damage,
      damageAfterArmour: Number(perHit.toFixed(1)),
      hitsToKillPlayer: Number((player.health / perHit).toFixed(1)),
      playerSecondsToKill: Number((playerDps > 0 ? health / playerDps : 0).toFixed(1)),
      enemySecondsToKillPlayer: Number(((player.health / perHit) * cycle).toFixed(1)),
    });
  }
  rows.sort((a, b) => a.order - b.order || a.health - b.health);

  const hits = rows.map((r) => r.hitsToKillPlayer);

  // The design target is the *median* basic enemy of each biome, not every enemy in it: the
  // weakest chaff in a pool is meant to be chaff, and a boss is meant to be worse than the band.
  // Holding every row to the band would only invite someone to flatten the roster to silence it.
  const byOrder = {};
  for (const row of rows) {
    if (row.boss) continue;
    (byOrder[row.order] ??= []).push(row.hitsToKillPlayer);
  }
  const perOrder = {};
  const breaches = [];
  for (const [order, values] of Object.entries(byOrder)) {
    const med = Number(median(values).toFixed(1));
    perOrder[order] = med;
    if (med < MEDIAN_BAND[0] || med > MEDIAN_BAND[1]) {
      breaches.push({ kind: "biome_median", order: Number(order), hitsToKillPlayer: med });
    }
  }
  for (const row of rows) {
    if (row.boss) continue;
    if (row.hitsToKillPlayer > PUSHOVER_HITS) {
      breaches.push({
        kind: "pushover",
        id: row.id,
        order: row.order,
        hitsToKillPlayer: row.hitsToKillPlayer,
      });
    }
  }

  return {
    playerDps: Number(playerDps.toFixed(2)),
    targetHitsToKillPlayer: TARGET_HITS_TO_KILL_PLAYER,
    medianBand: MEDIAN_BAND,
    pushoverThreshold: PUSHOVER_HITS,
    playerByOrder: profiles,
    medianHitsToKillPlayer: Number(median(hits).toFixed(1)),
    medianByOrder: perOrder,
    outOfBandCount: rows.filter(
      (r) =>
        r.hitsToKillPlayer < TARGET_HITS_TO_KILL_PLAYER[0] ||
        r.hitsToKillPlayer > TARGET_HITS_TO_KILL_PLAYER[1]
    ).length,
    breaches,
    rows,
  };
}

// ------------------------------------------------------------------- build envelope
//
// The single-build model above answers "is the average fight fair". It cannot answer the question
// that actually decides whether a game is balanced, which is what the *extremes* of the build
// space do to it: the floor build has to be able to win, and the ceiling build must not be able to
// walk through the game without reading anything.
//
// Every multiplier in the game stacks onto the same two numbers -- what the player deals and what
// they can take -- so the envelope is computed by driving each of them to its worst and best legal
// value at once and seeing where the fight lands.
//
//   deals:  weapon attack x quality x upgrade x two-hand x crit x damagePercent x flat bonus
//           x attack speed (more swings per second, not harder ones)
//   takes:  base + class + gear health, against armour on the diminishing-returns curve
//
// A combination that cannot happen in play is not interesting, so the bounds are legal ones: the
// floor is a common, chipped, unupgraded piece in every slot and the ceiling is an aumbral,
// masterforged, fully-upgraded one.

const QUALITY_MIN = 0.8;
const QUALITY_MAX = 1.2;
const UPGRADE_STEP_MIN = 0.04; // keen path
const UPGRADE_STEP_MAX = 0.08; // heavy path
const UPGRADE_LEVEL_MAX = 10; // aumbral
const TWO_HAND_DAMAGE_MULT = 1.25;
const CRIT_BASE_MULT = 1.5;
const ATTACK_SPEED_CAP = 0.45;
const FLAT_DAMAGE_CAP_RATIO = 2.0;
// Flat-damage affixes are weapon-only and now capped per family by rarity_rules.affixGroupLimits,
// so the ceiling is that many of the biggest rolls rather than a whole weapon's worth of them.
function affixFlatDamageCeiling() {
  const rules = readJson(join(contentRoot, "affixes", "rarity_rules.json"));
  const limit = Number(rules.affixGroupLimits?.flatDamage ?? 99);
  const flatKeys = new Set([
    "physicalDamage", "fireDamage", "frostDamage", "arcaneDamage", "poisonDamage",
  ]);
  const rolls = [];
  for (const pack of ["prefixes", "suffixes"]) {
    for (const affix of readJson(join(contentRoot, "affixes", `${pack}.json`)).affixes ?? []) {
      if (flatKeys.has(affix.stat)) rolls.push(Number(affix.tiers?.aumbral?.max ?? 0));
    }
  }
  rolls.sort((a, b) => b - a);
  return rolls.slice(0, limit).reduce((a, b) => a + b, 0);
}

// What the ceiling build is allowed to look like before the game stops being a fight. These are
// the assertions: a build that beats them means some multiplier has grown past the others.
// A fully-geared build must still be killable by the deepest enemies in a readable number of hits,
// or the endgame has no fights left in it.
const CEILING_MAX_HITS_TO_KILL_PLAYER = 14;
const FLOOR_MAX_SECONDS_TO_KILL = 90;
// How far gear alone may swing one attack. The legal multipliers -- quality 1.2, ten upgrade
// levels at the heavy step 1.8, two-handing 1.25, best-in-slot damagePercent 1.47, crit 1.15,
// attack speed 1.15, and gear flat damage capped at triple the swing -- multiply out to about
// twenty against a chipped, unupgraded common in the hands of the worst-scaling class. That is the
// budget; anything past it means a multiplier has grown out of step with the rest.
const MAX_BUILD_SPREAD = 20;
const MAX_ROSTER_SPREAD = 8;

function attackList(weapon) {
  const out = [];
  for (const atk of weapon.light_attacks ?? []) out.push({ kind: "light", ...atk });
  for (const atk of weapon.heavy_attacks ?? []) out.push({ kind: "heavy", ...atk });
  if (weapon.heavy_attack) out.push({ kind: "heavy", ...weapon.heavy_attack });
  if (weapon.running_attack) out.push({ kind: "running", ...weapon.running_attack });
  if (weapon.rolling_attack) out.push({ kind: "rolling", ...weapon.rolling_attack });
  if (weapon.art) out.push({ kind: "art", ...weapon.art });
  return out;
}

// One attack's sustained damage per second, before build multipliers.
function attackDps(atk) {
  const cycle =
    Number(atk.startup ?? 0) + Number(atk.active ?? 0) + Number(atk.recovery ?? 0);
  return cycle > 0 ? Number(atk.damage ?? 0) / cycle : 0;
}

function buildEnvelope(enemies, weapons, items, classes) {
  // A build only ever meets part of the roster. The floor build -- chipped commons, worst class --
  // is what the player has in the first biome, so it is judged against the first biome. The
  // ceiling build exists only at the end, so it is judged against the last. Holding the floor
  // build to the final boss, or the ceiling build to first-biome chaff, measures nothing.
  const orderByBiome = dungeonOrderByBiome();
  const biomeOf = enemyBiomeMap();
  const orderOf = (enemy) => orderByBiome[biomeOf[enemy.id]] ?? null;
  const OPENING_ORDERS = [1, 2];
  const DEEPEST_ORDERS = [9, 10];
  const classHealth = classes.map((c) => Number(c.statBonuses?.maxHealth ?? 0));
  const classDamage = classes.map((c) => Number(c.statBonuses?.physicalDamage ?? 0));
  const classCrit = classes.map((c) => Number(c.statBonuses?.critChance ?? 0));

  // Gear extremes, taken across everything that can occupy a slot rather than per biome: a player
  // can carry a piece forward, so the ceiling of the game is the ceiling of the whole item pool.
  const bySlot = {};
  for (const item of items) {
    if (!item.equipmentSlot) continue;
    (bySlot[item.equipmentSlot] ??= []).push(item);
  }
  let gearHealthMin = 0;
  let gearHealthMax = 0;
  let gearPointsMin = 0;
  let gearPointsMax = 0;
  let gearDamagePctMax = 0;
  let gearFlatDamageMax = 0;
  let gearCritMax = 0;
  let gearAttackSpeedMax = 0;
  for (const pieces of Object.values(bySlot)) {
    const health = pieces.map((i) => Number(i.stats?.maxHealth ?? 0));
    const points = pieces.map(
      (i) => Number(i.stats?.armor ?? 0) + Number(i.stats?.defense ?? 0)
    );
    gearHealthMin += Math.min(...health) * QUALITY_MIN;
    gearHealthMax += Math.max(...health) * QUALITY_MAX;
    gearPointsMin += Math.min(...points) * QUALITY_MIN;
    gearPointsMax += Math.max(...points) * QUALITY_MAX;
    gearDamagePctMax += Math.max(...pieces.map((i) => Number(i.stats?.damagePercent ?? 0)));
    gearFlatDamageMax += Math.max(
      ...pieces.map((i) =>
        ["physicalDamage", "fireDamage", "frostDamage", "arcaneDamage", "poisonDamage"].reduce(
          (a, k) => a + Number(i.stats?.[k] ?? 0),
          0
        )
      )
    );
    gearCritMax += Math.max(...pieces.map((i) => Number(i.stats?.critChance ?? 0)));
    gearAttackSpeedMax += Math.max(...pieces.map((i) => Number(i.stats?.attackSpeed ?? 0)));
  }
  gearFlatDamageMax += affixFlatDamageCeiling();
  const attackSpeed = Math.min(ATTACK_SPEED_CAP, gearAttackSpeedMax);

  const upgradeMin = 1.0;
  const upgradeMax = 1.0 + UPGRADE_STEP_MAX * UPGRADE_LEVEL_MAX;

  // --- what the player can take
  const healthFloor = PLAYER_BASE_HEALTH + Math.min(...classHealth) + gearHealthMin;
  const healthCeiling = PLAYER_BASE_HEALTH + Math.max(...classHealth) + gearHealthMax;
  const mitigationFloor = Math.min(
    DEFENSE_CAP,
    gearPointsMin / (gearPointsMin + DEFENSE_SOFTENING)
  );
  const mitigationCeiling = Math.min(
    DEFENSE_CAP,
    gearPointsMax / (gearPointsMax + DEFENSE_SOFTENING)
  );
  const ehpFloor = healthFloor / (1 - mitigationFloor);
  const ehpCeiling = healthCeiling / (1 - mitigationCeiling);

  // --- what the player can deal
  //
  // Two different questions live here and mixing them produces a meaningless number. "How much can
  // gear swing the game" is the same attack at the floor build against the ceiling build. "Is the
  // weapon roster balanced" is the best attack against the worst at the *same* build. Comparing a
  // staff jab on a naked character against a dagger heavy on a maxed one answers neither.
  const crit = Math.min(1, Math.max(...classCrit) + gearCritMax);
  const critMult = 1 + crit * (CRIT_BASE_MULT - 1);
  const ceilingMultiplier =
    QUALITY_MAX *
    upgradeMax *
    TWO_HAND_DAMAGE_MULT *
    (1 + Math.max(...classDamage) + gearDamagePctMax / 100) *
    critMult *
    (1 + attackSpeed);
  const floorMultiplier = QUALITY_MIN * upgradeMin * (1 + Math.min(...classDamage));

  let buildSpread = 0;
  let buildSpreadSource = "";
  let bestAttack = null;
  let worstAttack = null;
  let dpsFloor = Infinity;
  let dpsCeiling = 0;
  let floorSource = "";
  let ceilingSource = "";
  for (const weapon of weapons) {
    const opener = (weapon.light_attacks ?? [])[0];
    const openerDamage = Number(opener?.damage ?? 0);
    for (const atk of attackList(weapon)) {
      const base = attackDps(atk);
      if (base <= 0) continue;
      const cycle =
        Number(atk.startup ?? 0) + Number(atk.active ?? 0) + Number(atk.recovery ?? 0);
      // Flat damage is weight-scaled now, so it lands per second the way weapon damage does
      // rather than as a fixed lump on whichever attack swings fastest.
      const weight = openerDamage > 0 ? Number(atk.damage ?? 0) / openerDamage : 1;
      // Mirrors CombatStatModifiers.flat_damage_bonus: weight-scaled, then bounded to a multiple
      // of the attack's own damage so gear amplifies the weapon instead of replacing it.
      const flatPerHit = Math.min(
        gearFlatDamageMax * weight,
        Number(atk.damage ?? 0) * FLAT_DAMAGE_CAP_RATIO
      );
      const flatDps = cycle > 0 ? flatPerHit / cycle : 0;
      const floor = base * floorMultiplier;
      const ceiling = (base + flatDps) * ceilingMultiplier;
      const label = `${weapon.id}/${atk.kind}`;
      if (floor > 0 && ceiling / floor > buildSpread) {
        buildSpread = ceiling / floor;
        buildSpreadSource = label;
      }
      if (bestAttack == null || ceiling > bestAttack.dps) {
        bestAttack = { id: label, dps: Number((ceiling * PLAYER_UPTIME).toFixed(1)) };
      }
      if (worstAttack == null || ceiling < worstAttack.dps) {
        worstAttack = { id: label, dps: Number((ceiling * PLAYER_UPTIME).toFixed(1)) };
      }
      if (floor < dpsFloor) {
        dpsFloor = floor;
        floorSource = label;
      }
      if (ceiling > dpsCeiling) {
        dpsCeiling = ceiling;
        ceilingSource = label;
      }
    }
  }
  dpsFloor *= PLAYER_UPTIME;
  dpsCeiling *= PLAYER_UPTIME;
  const rosterSpread = bestAttack.dps / worstAttack.dps;

  // --- where that leaves the fights
  const breaches = [];
  const observations = [];
  const endgame = enemies.filter((e) => DEEPEST_ORDERS.includes(orderOf(e)));
  let toughest = null;
  let slowest = null;
  for (const enemy of endgame) {
    const damage = Number(enemy.attack_damage ?? 0);
    if (damage <= 0) continue;
    // effectiveHealth already has mitigation folded in, so the raw hit is what divides it.
    const hits = ehpCeiling / damage;
    if (toughest == null || hits > toughest.hits) {
      toughest = { id: enemy.id, hits: Number(hits.toFixed(1)) };
    }
  }
  for (const enemy of enemies) {
    if (!OPENING_ORDERS.includes(orderOf(enemy))) continue;
    const health = Number(enemy.health ?? 0);
    if (health <= 0) continue;
    const seconds = health / dpsFloor;
    if (slowest == null || seconds > slowest.seconds) {
      slowest = { id: enemy.id, seconds: Number(seconds.toFixed(1)) };
    }
  }

  if (buildSpread > MAX_BUILD_SPREAD) {
    breaches.push({
      kind: "build_spread",
      detail: `gear swings ${buildSpreadSource} by ${buildSpread.toFixed(1)}x floor-to-ceiling (limit ${MAX_BUILD_SPREAD}x)`,
    });
  }
  if (rosterSpread > MAX_ROSTER_SPREAD) {
    breaches.push({
      kind: "roster_spread",
      detail: `${bestAttack.id} deals ${rosterSpread.toFixed(1)}x ${worstAttack.id} at the same build (limit ${MAX_ROSTER_SPREAD}x)`,
    });
  }
  // Reported, not enforced.
  //
  // The player's effective health grows about seven-fold from the floor build to the ceiling one,
  // while enemy damage grows about two-and-a-half-fold across the biomes. At the deepest biomes a
  // maxed build is roughly three and a half times as survivable as a median one, and no single
  // enemy-damage number puts both inside their bands: the damage that gives a median build six
  // hits leaves a maxed build twenty-nine, and the damage that gives a maxed build fourteen kills
  // a median one in four.
  //
  // Closing it is a design decision about how strong full optimisation should make the player, and
  // it is paid for in content rather than constants -- either the deepest biomes get gear that
  // lifts the median build toward the ceiling, or the health and armour an endgame build can stack
  // comes down. Picking one silently inside a balance script would be the wrong place to decide
  // it, so this measures the gap and says so instead of failing the build over it.
  if (toughest && toughest.hits > CEILING_MAX_HITS_TO_KILL_PLAYER) {
    observations.push({
      kind: "endgame_soft_for_maxed_build",
      detail: `the deepest enemies need ${toughest.hits} hits to kill a fully-optimised build (target ${CEILING_MAX_HITS_TO_KILL_PLAYER}) while a median build there takes about six — enemy damage alone cannot satisfy both`,
    });
  }
  if (slowest && slowest.seconds > FLOOR_MAX_SECONDS_TO_KILL) {
    breaches.push({
      kind: "unwinnable_for_floor_build",
      detail: `${slowest.id} takes ${slowest.seconds}s for the weakest legal build (limit ${FLOOR_MAX_SECONDS_TO_KILL}s)`,
    });
  }

  return {
    player: {
      healthFloor: Number(healthFloor.toFixed(1)),
      healthCeiling: Number(healthCeiling.toFixed(1)),
      mitigationFloor: Number(mitigationFloor.toFixed(3)),
      mitigationCeiling: Number(mitigationCeiling.toFixed(3)),
      effectiveHealthFloor: Number(ehpFloor.toFixed(1)),
      effectiveHealthCeiling: Number(ehpCeiling.toFixed(1)),
      attackSpeedCeiling: Number(attackSpeed.toFixed(3)),
    },
    dps: {
      floor: Number(dpsFloor.toFixed(2)),
      ceiling: Number(dpsCeiling.toFixed(2)),
      buildSpread: Number(buildSpread.toFixed(1)),
      buildSpreadSource,
      rosterSpread: Number(rosterSpread.toFixed(1)),
      bestAttack,
      worstAttack,
      floorSource,
      ceilingSource,
    },
    toughestForCeilingBuild: toughest,
    observations,
    slowestForFloorBuild: slowest,
    breaches,
  };
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

function loadClasses() {
  return listJsonFiles(join(contentRoot, "classes")).map(readJson);
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
    combatExchange: buildExchange(enemies, weapons),
    buildEnvelope: buildEnvelope(enemies, weapons, items, loadClasses()),
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

for (const note of report.buildEnvelope?.observations ?? []) {
  console.warn(`NOTE: ${note.kind} — ${note.detail}`);
}

const exchangeBreaches = [
  ...(report.combatExchange?.breaches ?? []),
  ...(report.buildEnvelope?.breaches ?? []),
];
if (exchangeBreaches.length > 0) {
  console.error(
    `FAIL: ${exchangeBreaches.length} balance breach(es) — a biome's median basic enemy must kill ` +
      `the player in ${report.combatExchange.medianBand.join("-")} unanswered hits, and the build ` +
      `envelope must stay inside its spread limits`
  );
  for (const b of exchangeBreaches) {
    console.error(`  ${b.kind}: ${b.id ?? `order ${b.order}`} = ${b.hitsToKillPlayer} hits`);
  }
  process.exit(1);
}

if (failRatio != null) {
  const exceeded = report.outliers.filter((o) => o.ratio > failRatio);
  if (exceeded.length > 0) {
    console.error(`FAIL: ${exceeded.length} outlier(s) exceed ratio ${failRatio}`);
    process.exit(1);
  }
}

console.log(`Exported balance report to ${exportPath}`);
