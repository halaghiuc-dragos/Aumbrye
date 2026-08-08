#!/usr/bin/env node
import { readFileSync, readdirSync, existsSync, statSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const CONTENT = join(ROOT, "content");
const CLIENT = join(ROOT, "apps/game/client");
const asJson = process.argv.includes("--json");
const warnOnly = process.argv.includes("--warn-only");

const findings = [];
const report = (severity, check, message) => findings.push({ severity, check, message });
const fail = (check, message) => report("error", check, message);
const warn = (check, message) => report("warning", check, message);

function readJson(path) {
  try {
    return JSON.parse(readFileSync(path, "utf8"));
  } catch {
    return null;
  }
}

function jsonFiles(relDir) {
  const dir = join(CONTENT, relDir);
  if (!existsSync(dir) || !statSync(dir).isDirectory()) return [];
  return readdirSync(dir)
    .filter((f) => f.endsWith(".json"))
    .map((f) => ({ name: f, path: join(dir, f), data: readJson(join(dir, f)) }))
    .filter((f) => f.data !== null);
}

function walkGd(dir, out = []) {
  if (!existsSync(dir)) return out;
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry);
    const st = statSync(full);
    if (st.isDirectory()) walkGd(full, out);
    else if (entry.endsWith(".gd")) out.push(full);
  }
  return out;
}

const gdSources = walkGd(join(CLIENT, "scripts")).map((p) => readFileSync(p, "utf8"));
const gdBlob = gdSources.join("\n");


function constStringValues(relPath, prefix) {
  const src = readFileSync(join(CLIENT, relPath), "utf8");
  const out = new Set();
  const re = new RegExp(`const\\s+${prefix}\\w*\\s*:=\\s*"([^"]+)"`, "g");
  let m;
  while ((m = re.exec(src)) !== null) out.add(m[1]);
  return out;
}

const MODIFIERS = constStringValues("scripts/dungeon/run_modifier_service.gd", "MODIFIER_");
const COUNTER_KEYS = new Set(
  [...constStringValues("scripts/meta/progress_counters.gd", "KEY_")].map(String)
);


const biomes = jsonFiles("biomes");
const enemies = jsonFiles("enemies");
const bosses = jsonFiles("bosses");
const traps = jsonFiles("traps");
const questFiles = jsonFiles("quests");
const quests = questFiles.flatMap((f) =>
  Array.isArray(f.data.quests)
    ? f.data.quests.map((q) => ({ name: f.name, path: f.path, data: q }))
    : [f]
);
const dialogues = jsonFiles("dialogue");
const relics = jsonFiles("relics");
const npcs = jsonFiles("npcs");
const classes = jsonFiles("classes");
const recipes = jsonFiles("recipes");
const merchants = jsonFiles("merchant");
const waves = jsonFiles("waves");
const dungeons = jsonFiles("dungeons");

const enemyIds = new Set(enemies.map((f) => String(f.data.id)));
const bossIds = new Set(bosses.map((f) => String(f.data.id)));
const trapIds = new Set(traps.map((f) => String(f.data.id)));
const questIds = new Set(quests.map((f) => String(f.data.id ?? f.data.questId ?? "")).filter(Boolean));
const dialogueIds = new Set(dialogues.map((f) => String(f.data.id)));
const biomeIds = new Set(biomes.map((f) => String(f.data.id)));
const dungeonIds = new Set(dungeons.map((f) => String(f.data.id)));

const itemDefIds = new Set();
for (const sub of ["equipment", "consumables", "materials", "quest"]) {
  for (const f of jsonFiles(join("items", sub))) itemDefIds.add(String(f.data.id));
}
const catalog = readJson(join(CONTENT, "items/catalog.json")) ?? {};
const catalogIds = new Set(
  ["equipment", "consumables", "materials"].flatMap((k) =>
    Array.isArray(catalog[k]) ? catalog[k].map(String) : []
  )
);


const pooledEnemies = new Set();
for (const biome of biomes) {
  for (const key of ["enemyPool", "bossPool"]) {
    for (const row of biome.data[key] ?? []) {
      const id = String(row.enemyId ?? "");
      if (!id) continue;
      pooledEnemies.add(id);
      if (!enemyIds.has(id) && !bossIds.has(id)) {
        fail("enemy-pool", `${biome.name}: ${key} references unknown enemy "${id}"`);
      }
    }
  }
}
for (const wave of waves) {
  const text = JSON.stringify(wave.data);
  for (const id of [...enemyIds, ...bossIds]) {
    if (text.includes(`"${id}"`)) pooledEnemies.add(id);
  }
}
for (const boss of bosses) {
  const text = JSON.stringify(boss.data);
  for (const id of enemyIds) if (text.includes(`"${id}"`)) pooledEnemies.add(id);
}
for (const id of enemyIds) {
  if (!pooledEnemies.has(id) && !gdBlob.includes(`"${id}"`)) {
    fail("enemy-reachable", `enemy "${id}" is in no biome pool, wave or summon list`);
  }
}
for (const id of bossIds) {
  if (!pooledEnemies.has(id) && !gdBlob.includes(`"${id}"`)) {
    fail("boss-reachable", `boss "${id}" is in no biome bossPool`);
  }
}


const pooledTraps = new Set();
for (const biome of biomes) {
  for (const row of biome.data.trapPool ?? []) {
    const id = String(row.trapId ?? "");
    if (!id) continue;
    pooledTraps.add(id);
    if (!trapIds.has(id)) fail("trap-pool", `${biome.name}: unknown trap "${id}"`);
  }
}
for (const id of trapIds) {
  if (!pooledTraps.has(id)) fail("trap-reachable", `trap "${id}" is in no biome trapPool`);
}


const obtainable = new Set();
const ITEM_SENTINELS = new Set(["any", "none", ""]);
const noteItem = (id, source, where) => {
  const value = String(id ?? "");
  if (ITEM_SENTINELS.has(value)) return;
  obtainable.add(value);
  if (!itemDefIds.has(value)) fail("item-reference", `${where}: unknown item "${value}" (${source})`);
};

for (const biome of biomes) {
  for (const [table, rows] of Object.entries(biome.data.lootTables ?? {})) {
    for (const row of rows ?? []) noteItem(row.itemId, `lootTables.${table}`, biome.name);
  }
}
for (const merchant of merchants) {
  for (const row of merchant.data.items ?? []) noteItem(row.itemId, "merchant", merchant.name);
}
for (const recipe of recipes) {
  noteItem(recipe.data.itemId, "recipe", recipe.name);
  for (const row of recipe.data.inputs ?? recipe.data.materials ?? []) {
    noteItem(row.itemId ?? row.id, "recipe input", recipe.name);
  }
  noteItem(recipe.data.outputItemId, "recipe output", recipe.name);
}
for (const cls of classes) {
  noteItem(cls.data.startingWeaponItemId, "class kit", cls.name);
  for (const row of cls.data.startingItems ?? []) noteItem(row.itemId ?? row, "class kit", cls.name);
}
for (const quest of quests) {
  for (const row of quest.data.rewards?.items ?? []) noteItem(row.itemId ?? row, "quest reward", quest.name);
  noteItem(quest.data.itemId, "quest target", quest.name);
  noteItem(quest.data.rewardItemId, "quest reward", quest.name);
}
const globalDrops = readJson(join(CONTENT, "loot/global_drops.json")) ?? {};
for (const row of globalDrops.skipItems ?? []) noteItem(row.itemId, "global drop", "loot/global_drops.json");

for (const id of catalogIds) {
  if (!itemDefIds.has(id)) fail("item-catalog", `catalog lists "${id}" with no definition file`);
  else if (!obtainable.has(id) && !gdBlob.includes(`"${id}"`)) {
    fail("item-reachable", `item "${id}" drops from nothing, is sold by nobody and is crafted by no recipe`);
  }
}
for (const id of itemDefIds) {
  if (!catalogIds.has(id)) warn("item-catalog", `item "${id}" has a definition but is not in catalog.json`);
}


for (const file of dialogues) {
  const nodes = file.data.nodes ?? {};
  const start = String(file.data.startNode ?? "");
  if (!nodes[start]) {
    fail("dialogue-start", `${file.name}: startNode "${start}" does not exist`);
    continue;
  }
  const seen = new Set();
  const queue = [start];
  while (queue.length > 0) {
    const key = queue.pop();
    if (seen.has(key)) continue;
    seen.add(key);
    const node = nodes[key];
    if (!node) continue;
    const targets = [];
    if (node.next) targets.push(String(node.next));
    if (node.fallback) targets.push(String(node.fallback));
    for (const choice of node.choices ?? []) if (choice.next) targets.push(String(choice.next));
    for (const target of targets) {
      if (target === "end" || target === "") continue;
      if (!nodes[target]) fail("dialogue-edge", `${file.name}: node "${key}" points at missing "${target}"`);
      else queue.push(target);
    }
  }
  for (const key of Object.keys(nodes)) {
    if (!seen.has(key)) fail("dialogue-reachable", `${file.name}: node "${key}" cannot be reached from the start`);
  }
}

const referencedDialogue = new Set();
for (const npc of npcs) {
  if (npc.data.dialogueId) referencedDialogue.add(String(npc.data.dialogueId));
  for (const rule of npc.data.dialogueRules ?? []) {
    if (rule.dialogueId) referencedDialogue.add(String(rule.dialogueId));
  }
}
for (const quest of quests) if (quest.data.dialogueId) referencedDialogue.add(String(quest.data.dialogueId));
for (const file of questFiles) {
  for (const row of file.data.quests ?? []) {
    if (row.dialogueId) referencedDialogue.add(String(row.dialogueId));
  }
}
for (const id of referencedDialogue) {
  if (!dialogueIds.has(id)) fail("dialogue-reference", `unknown dialogue "${id}" is referenced by an NPC or quest`);
}
for (const id of dialogueIds) {
  if (!referencedDialogue.has(id) && !gdBlob.includes(`"${id}"`)) {
    fail("dialogue-reachable", `dialogue "${id}" is not reachable from any NPC, quest or script`);
  }
}


const questByPrereq = new Map(
  quests.map((q) => [String(q.data.id ?? q.data.questId ?? ""), q.data.prerequisites ?? []])
);
for (const [id, prereqs] of questByPrereq) {
  for (const prereq of prereqs) {
    if (!questIds.has(String(prereq))) fail("quest-prereq", `quest "${id}" requires unknown quest "${prereq}"`);
  }
}
const questState = new Map();
function questCompletable(id, trail = new Set()) {
  if (questState.has(id)) return questState.get(id);
  if (trail.has(id)) {
    fail("quest-cycle", `quest "${id}" is part of a prerequisite cycle`);
    questState.set(id, false);
    return false;
  }
  trail.add(id);
  let ok = true;
  for (const prereq of questByPrereq.get(id) ?? []) {
    if (!questIds.has(String(prereq)) || !questCompletable(String(prereq), trail)) ok = false;
  }
  trail.delete(id);
  questState.set(id, ok);
  return ok;
}
for (const quest of quests) {
  const id = String(quest.data.id ?? quest.data.questId ?? "");
  if (id === "") continue;
  if (!questCompletable(id)) fail("quest-reachable", `quest "${id}" can never be started`);
  const biomeId = quest.data.biomeId;
  if (biomeId && !biomeIds.has(String(biomeId))) fail("quest-target", `quest "${id}" targets unknown biome "${biomeId}"`);
  const dungeonId = quest.data.dungeonId;
  if (dungeonId && !dungeonIds.has(String(dungeonId))) fail("quest-target", `quest "${id}" targets unknown dungeon "${dungeonId}"`);
  const enemyId = quest.data.enemyId ?? quest.data.targetEnemyId;
  if (enemyId && !enemyIds.has(String(enemyId)) && !bossIds.has(String(enemyId))) {
    fail("quest-target", `quest "${id}" targets unknown enemy "${enemyId}"`);
  }
}


for (const relic of relics) {
  const id = String(relic.data.id);
  if (relic.data.offerable === false && !gdBlob.includes(`"${id}"`)) {
    const granted = quests.some((q) => JSON.stringify(q.data).includes(`"${id}"`));
    if (!granted) fail("relic-reachable", `relic "${id}" is not offerable and is granted by nothing`);
  }
}


const bestiary = readJson(join(CONTENT, "bestiary/entries.json")) ?? {};
const bestiaryIds = new Set((bestiary.entries ?? []).map((e) => String(e.enemyId)));
for (const id of bestiaryIds) {
  if (!enemyIds.has(id) && !bossIds.has(id)) fail("bestiary-entry", `bestiary entry "${id}" has no enemy definition`);
  else if (!pooledEnemies.has(id)) {
    fail("bestiary-reachable", `bestiary entry "${id}" can never be revealed — the enemy is in no pool`);
  }
}
for (const id of pooledEnemies) {
  if (!bestiaryIds.has(id)) warn("bestiary-coverage", `spawnable "${id}" has no bestiary entry`);
}


const modeCatalog = readJson(join(CONTENT, "modes/catalog.json")) ?? {};
for (const mode of modeCatalog.modes ?? []) {
  const id = String(mode.id);
  if (mode.dungeonId && !dungeonIds.has(String(mode.dungeonId))) {
    fail("mode-target", `mode "${id}" starts in unknown dungeon "${mode.dungeonId}"`);
  }
  const modifierLists = [mode.modifiers ?? [], ...(mode.escalation ?? []).map((s) => s.modifiers ?? [])];
  for (const list of modifierLists) {
    for (const modifier of list) {
      if (!MODIFIERS.has(String(modifier))) fail("mode-modifier", `mode "${id}" uses unknown modifier "${modifier}"`);
    }
  }
  for (const key of Object.keys(mode.unlock ?? {})) {
    if (!COUNTER_KEYS.has(key)) fail("mode-unlock", `mode "${id}" gates on unknown counter "${key}"`);
  }
}

const challengeData = readJson(join(CONTENT, "challenges/weekly.json")) ?? {};
for (const entry of challengeData.rotation ?? []) {
  const id = String(entry.id);
  if (!dungeonIds.has(String(entry.dungeonId))) {
    fail("challenge-target", `challenge "${id}" uses unknown dungeon "${entry.dungeonId}"`);
  }
  for (const modifier of entry.modifiers ?? []) {
    if (!MODIFIERS.has(String(modifier))) fail("challenge-modifier", `challenge "${id}" uses unknown modifier "${modifier}"`);
  }
}
if ((challengeData.rotation ?? []).length > 0) {
  const dungeonsUsed = new Set((challengeData.rotation ?? []).map((e) => String(e.dungeonId)));
  for (const dungeonId of dungeonsUsed) {
    const dungeon = dungeons.find((d) => String(d.data.id) === dungeonId);
    if (!dungeon) continue;
    const tiers = new Set((dungeon.data.difficultyTiers ?? []).map((t) => Number(t.tier)));
    for (const entry of challengeData.rotation) {
      if (String(entry.dungeonId) !== dungeonId) continue;
      if (!tiers.has(Number(entry.difficultyTier))) {
        fail("challenge-tier", `challenge "${entry.id}" asks for depth ${entry.difficultyTier}, which ${dungeonId} does not have`);
      }
    }
  }
}

const hubGrowth = readJson(join(CONTENT, "ui/hub_growth.json")) ?? {};
for (const entry of hubGrowth.entries ?? []) {
  for (const key of Object.keys(entry.condition ?? {})) {
    if (!COUNTER_KEYS.has(key)) fail("hub-growth", `dressing "${entry.id}" gates on unknown counter "${key}"`);
  }
}


const classAtlas = readJson(join(CONTENT, "ui/class_icon_atlas.json")) ?? {};
for (const cls of classes) {
  const id = String(cls.data.id);
  if (!(classAtlas.cells ?? {})[id]) fail("class-portrait", `class "${id}" has no cell in the class icon atlas`);
}


const achievements = readJson(join(CONTENT, "achievements/catalog.json")) ?? {};
const hooks = readJson(join(CONTENT, "achievements/hooks.json")) ?? {};
const hooked = new Set([
  ...(hooks.manualUnlock ?? []).map(String),
  ...(hooks.hooks ?? []).map((h) => String(h.achievementId)),
]);
for (const achievement of achievements.achievements ?? []) {
  const id = String(achievement.id);
  if (!hooked.has(id) && !gdBlob.includes(`"${id}"`)) {
    fail("achievement-reachable", `achievement "${id}" has no hook and is notified by no script`);
  }
}


const errors = findings.filter((f) => f.severity === "error");
if (asJson) {
  console.log(JSON.stringify({ errors: errors.length, findings }, null, 2));
} else {
  for (const finding of findings) {
    console.log(`${finding.severity === "error" ? "FAIL" : "WARN"} [${finding.check}] ${finding.message}`);
  }
  console.log(`\n${errors.length} unreachable-content error(s), ${findings.length - errors.length} warning(s).`);
}
if (errors.length > 0 && !warnOnly) process.exit(1);
