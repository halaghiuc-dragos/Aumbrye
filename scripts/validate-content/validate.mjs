import { readFileSync, readdirSync, statSync, existsSync } from "node:fs";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import Ajv from "ajv";
import addFormats from "ajv-formats";

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(__dirname, "../..");
const contentRoot = join(repoRoot, "content");
const schemasRoot = join(contentRoot, "schemas");
// Superseded schemas live here; only explicitly-versioned legacy fixtures may reference them.
const retiredSchemasRoot = join(schemasRoot, "retired");
const strictContent = process.argv.includes("--strict-content");
const PLACEHOLDER_DESC = /^M6 content item\.?$/i;

// Files under a schema-checked prefix that intentionally have no schema: generated measurements,
// tooling metadata, and fixtures a test writes transiently.
const UNSCHEMA_ALLOWLIST = new Set([
  "content/fixtures/mix_seed_parity.json",
  "content/fixtures/room_kit_specs.json",
  "content/fixtures/perf_baseline.json",
  "content/fixtures/schema_versions.json",
  "content/fixtures/_m6_strict_orphan_item.json",
]);

const SCHEMA_PREFIXES = [
  "fixtures/dungeon_definition",
  "fixtures/forgotten_castle_slice.json",
  "fixtures/inventory_sample.v1.json",
  "fixtures/item_instance_roll_sample.v1.json",
  "fixtures/character_state_sample.v1.json",
  "fixtures/input_bindings_sample.v1.json",
  "enemies/",
  "weapons/",
  "combat/",
  "items/",
  "bosses/",
  "biomes/",
  "affixes/",
  "progression/",
  "talents/",
  "npcs/",
  "quests/",
  "dialogue/",
  "relics/",
  "recipes/",
  "merchant/",
  "classes/",
  "audio_profiles/",
  "achievements/",
  "statuses/",
  "loot/",
  "hub/",
  "waves/",
  "audio/",
  "ui/",
  "characters/",
  "bestiary/",
  "challenges/",
  "modes/",
  "traps/",
  "vfx/",
  "art/",
  "rooms/",
  "appearance/",
  "text/",
];

const ALLOWED_ITEM_STAT_KEYS = new Set([
  "maxHealth",
  "healthRegen",
  "evasion",
  "defense",
  "damagePercent",
  "moveSpeedPercent",
  "staminaMax",
  "bonusDamage",
  "physicalDamage",
  "fireDamage",
  "frostDamage",
  "arcaneDamage",
  "poisonDamage",
  "attackSpeed",
  "critChance",
  "poiseDamage",
  "armor",
  "blockReduction",
  "poise",
  "staminaRegen",
  "staminaCostReduction",
  "damageReduction",
  "moveSpeed",
  "lootQuality",
  "xpGain",
  "goldFind",
  "cooldownReduction",
  "manaMax",
  "manaRegen",
  "resistPhysical",
  "resistFire",
  "resistFrost",
  "resistPoison",
  "resistLightning",
  "resistArcane",
]);

function collectJsonFiles(dir) {
  const results = [];
  for (const entry of readdirSync(dir)) {
    const fullPath = join(dir, entry);
    const stat = statSync(fullPath);
    if (stat.isDirectory()) {
      if (entry === "schemas") continue;
      results.push(...collectJsonFiles(fullPath));
    } else if (entry.endsWith(".json")) {
      results.push(fullPath);
    }
  }
  return results;
}

function resolveSchemaForFile(filePath) {
  const name = relative(contentRoot, filePath).replace(/\\/g, "/");
  if (name.startsWith("fixtures/dungeon_definition") || name === "fixtures/forgotten_castle_slice.json") {
    if (name === "fixtures/dungeon_definition_v1_minimal.json") {
      return join(retiredSchemasRoot, "dungeon-definition.v1.json");
    }
    return join(schemasRoot, "dungeon-definition.v2.json");
  }
  if (name === "fixtures/inventory_sample.v1.json") {
    return join(retiredSchemasRoot, "inventory.v1.json");
  }
  if (name === "fixtures/inventory_sample.v2.json") {
    return join(schemasRoot, "inventory.v2.json");
  }
  if (name === "fixtures/item_instance_roll_sample.v1.json") {
    return join(schemasRoot, "item-instance-roll.v1.json");
  }
  if (name.startsWith("enemies/")) {
    return join(schemasRoot, "enemy-definition.v1.json");
  }
  if (name.startsWith("weapons/")) {
    return join(schemasRoot, "weapon-definition.v1.json");
  }
  if (name === "combat/dodge.json") {
    return join(schemasRoot, "dodge-tuning.v1.json");
  }
  if (name === "items/catalog.json") {
    return join(schemasRoot, "item-catalog.v1.json");
  }
  if (name.startsWith("items/")) {
    return join(schemasRoot, "item-definition.v1.json");
  }
  if (name.startsWith("bosses/")) {
    return join(schemasRoot, "enemy-definition.v1.json");
  }
  if (name.startsWith("biomes/")) {
    return join(schemasRoot, "biome-definition.v2.json");
  }
  if (name.startsWith("dungeons/")) {
    return join(schemasRoot, "dungeon-catalog-entry.v1.json");
  }
  if (name === "affixes/prefixes.json" || name === "affixes/suffixes.json") {
    return join(schemasRoot, "affix-pack.v1.json");
  }
  if (name === "affixes/rarity_rules.json") {
    return join(schemasRoot, "affix-rarity-rules.v1.json");
  }
  if (name === "progression/xp_curve.json") {
    return join(schemasRoot, "xp-curve.v1.json");
  }
  if (name === "progression/descent_pacts.json") {
    return join(schemasRoot, "descent-pacts.v1.json");
  }
  if (name === "progression/endless_depth.json") {
    return join(schemasRoot, "endless-depth.v1.json");
  }
  if (name === "progression/room_pacing.json") {
    return join(schemasRoot, "room-pacing.v1.json");
  }
  if (name.startsWith("rooms/")) {
    return join(schemasRoot, "room-kit.v1.json");
  }
  if (name.startsWith("text/")) {
    return join(schemasRoot, "name-list.v1.json");
  }
  if (name === "appearance/aspects.json") {
    return join(schemasRoot, "appearance-aspects.v1.json");
  }
  if (name.startsWith("traps/")) {
    return join(schemasRoot, "trap-definition.v1.json");
  }
  if (name === "vfx/effects.json") {
    return join(schemasRoot, "vfx-effect.v1.json");
  }
  if (name === "ui/input_glyph_atlas.json") {
    return join(schemasRoot, "input-glyph-atlas.v1.json");
  }
  if (name === "art/palettes.json") {
    return join(schemasRoot, "palette.v1.json");
  }
  if (name === "art/lighting.json") {
    return join(schemasRoot, "lighting-profile.v1.json");
  }
  if (name === "art/portals.json") {
    return join(schemasRoot, "portal.v1.json");
  }
  if (name.startsWith("art/structures/")) {
    return join(schemasRoot, "structure.v1.json");
  }
  if (name === "talents/tree.json") {
    return join(schemasRoot, "talent-tree.v1.json");
  }
  if (name === "fixtures/character_state_sample.v1.json") {
    return join(retiredSchemasRoot, "character-state.v1.json");
  }
  if (name === "fixtures/character_state_sample.v2.json") {
    return join(schemasRoot, "character-state.v2.json");
  }
  if (name === "fixtures/input_bindings_sample.v1.json") {
    return join(schemasRoot, "input-bindings.v1.json");
  }
  if (name.startsWith("npcs/")) {
    return join(schemasRoot, "npc-definition.v1.json");
  }
  if (name === "quests/dungeon_quests.json") {
    return join(schemasRoot, "dungeon-quest.v1.json");
  }
  if (name.startsWith("quests/")) {
    return join(schemasRoot, "quest-definition.v1.json");
  }
  if (name.startsWith("dialogue/")) {
    return join(schemasRoot, "dialogue-definition.v1.json");
  }
  if (name.startsWith("relics/")) {
    return join(schemasRoot, "relic-definition.v1.json");
  }
  if (name.startsWith("recipes/")) {
    return join(schemasRoot, "recipe-definition.v1.json");
  }
  if (name.startsWith("merchant/")) {
    return join(schemasRoot, "merchant-pack.v1.json");
  }
  if (name.startsWith("classes/")) {
    return join(schemasRoot, "class-definition.v1.json");
  }
  if (name.startsWith("audio_profiles/")) {
    return join(schemasRoot, "audio-profile.v1.json");
  }
  if (name === "achievements/hooks.json") {
    return join(schemasRoot, "achievement-hooks.v1.json");
  }
  if (name.startsWith("achievements/")) {
    return join(schemasRoot, "achievement-catalog.v1.json");
  }
  if (name.startsWith("statuses/")) {
    return join(schemasRoot, "status-definition.v1.json");
  }
  if (name === "loot/global_drops.json") {
    return join(schemasRoot, "global-drops.v1.json");
  }
  if (name.startsWith("loot/tables/")) {
    return join(schemasRoot, "loot-table.v1.json");
  }
  if (name === "hub/tips.json") {
    return join(schemasRoot, "hub-tips.v1.json");
  }
  if (name.startsWith("waves/")) {
    return join(schemasRoot, "waves-definition.v1.json");
  }
  if (name === "audio/sfx.json") {
    return join(schemasRoot, "sfx-bank.v1.json");
  }
  if (name === "ui/item_icon_atlas.json") {
    return join(schemasRoot, "item-icon-atlas.v1.json");
  }
  if (name === "ui/class_icon_atlas.json") {
    return join(schemasRoot, "ui-symbol-atlas.v1.json");
  }
  if (name === "ui/hud_atlas.json") {
    return join(schemasRoot, "hud-atlas.v1.json");
  }
  if (name === "ui/hub_growth.json") {
    return join(schemasRoot, "hub-growth.v1.json");
  }
  if (name === "challenges/weekly.json") {
    return join(schemasRoot, "challenge-rotation.v1.json");
  }
  if (name === "modes/catalog.json") {
    return join(schemasRoot, "run-mode-catalog.v1.json");
  }
  if (name === "ui/status_icon_atlas.json") {
    return join(schemasRoot, "status-icon-atlas.v1.json");
  }
  if (name === "bestiary/entries.json") {
    return join(schemasRoot, "bestiary-catalog.v1.json");
  }
  if (name.startsWith("characters/")) {
    return join(schemasRoot, "character-rig.v1.json");
  }
  return null;
}

const ajv = new Ajv({ allErrors: true, strict: false });
addFormats(ajv);

const schemaCache = new Map();

function loadSchema(schemaPath) {
  if (!schemaCache.has(schemaPath)) {
    const schema = JSON.parse(readFileSync(schemaPath, "utf8"));
    ajv.addSchema(schema);
    schemaCache.set(schemaPath, schema.$id ?? schemaPath);
    if (schemaPath.endsWith("character-state.v1.json")) {
      loadSchema(join(retiredSchemasRoot, "inventory.v1.json"));
    }
    if (schemaPath.endsWith("character-state.v2.json")) {
      loadSchema(join(schemasRoot, "inventory.v2.json"));
    }
    if (schemaPath.endsWith("affix-pack.v1.json")) {
      loadSchema(join(schemasRoot, "affix-definition.v1.json"));
    }
    if (
      schemaPath.endsWith("item-icon-atlas.v1.json")
      || schemaPath.endsWith("status-icon-atlas.v1.json")
      || schemaPath.endsWith("ui-symbol-atlas.v1.json")
    ) {
      loadSchema(join(schemasRoot, "ui-symbol-atlas.v1.json"));
    }
  }
  return schemaCache.get(schemaPath);
}

const files = collectJsonFiles(contentRoot);
let failures = 0;

for (const filePath of files) {
  const relPath = relative(repoRoot, filePath).replace(/\\/g, "/");
  const schemaPath = resolveSchemaForFile(filePath);
  if (!schemaPath) {
    if (UNSCHEMA_ALLOWLIST.has(relPath)) {
      console.log(`ALLOWLIST (no schema): ${relPath}`);
      continue;
    }
    console.error(`FAIL: ${relPath} has no schema mapping`);
    console.error(`  Tried prefixes: ${SCHEMA_PREFIXES.join(", ")}`);
    failures++;
    continue;
  }

  const schemaId = loadSchema(schemaPath);
  const data = JSON.parse(readFileSync(filePath, "utf8"));
  const validate = ajv.getSchema(schemaId);

  if (!validate) {
    console.error(`FAIL: could not compile schema for ${relPath}`);
    failures++;
    continue;
  }

  if (!validate(data)) {
    console.error(`FAIL: ${relPath}`);
    for (const err of validate.errors ?? []) {
      console.error(`  - ${err.instancePath || "/"} ${err.message}`);
    }
    failures++;
  } else {
    console.log(`OK: ${relPath}`);
  }
}


function validateItemCatalogConsistency() {
  const catalogPath = join(contentRoot, "items", "catalog.json");
  if (!statSync(catalogPath).isFile()) {
    console.warn("SKIP: content/items/catalog.json not found");
    return 0;
  }

  const catalog = JSON.parse(readFileSync(catalogPath, "utf8"));
  const categories = {
    equipment: join(contentRoot, "items", "equipment"),
    consumables: join(contentRoot, "items", "consumables"),
    materials: join(contentRoot, "items", "materials"),
  };

  let errors = 0;
  const catalogIds = new Set();

  for (const [category, dirPath] of Object.entries(categories)) {
    const listed = catalog[category] ?? [];
    for (const itemId of listed) {
      if (catalogIds.has(itemId)) {
        console.error(`FAIL: catalog.json lists duplicate item id "${itemId}"`);
        errors++;
      }
      catalogIds.add(itemId);
    }

    if (!statSync(dirPath).isDirectory()) {
      console.error(`FAIL: missing item category directory ${relative(repoRoot, dirPath)}`);
      errors++;
      continue;
    }

    const idsOnDisk = [];
    for (const entry of readdirSync(dirPath)) {
      if (!entry.endsWith(".json")) continue;
      const itemPath = join(dirPath, entry);
      const item = JSON.parse(readFileSync(itemPath, "utf8"));
      const itemId = item.id;
      if (!itemId) {
        console.error(`FAIL: ${relative(repoRoot, itemPath)} missing id`);
        errors++;
        continue;
      }
      idsOnDisk.push(itemId);
      if (!listed.includes(itemId)) {
        console.error(`FAIL: ${itemId} exists in ${category}/ but is missing from catalog.json`);
        errors++;
      }
      const expectedTypes = {
        equipment: ["weapon", "armor", "accessory"],
        consumables: ["consumable"],
        materials: ["material", "key"],
      };
      if (!expectedTypes[category].includes(item.itemType)) {
        console.error(
          `FAIL: ${itemId} itemType "${item.itemType}" unexpected in folder "${category}"`
        );
        errors++;
      }
    }

    for (const itemId of listed) {
      if (!idsOnDisk.includes(itemId)) {
        console.error(`FAIL: catalog.json lists ${itemId} in ${category} but no JSON file exists`);
        errors++;
      }
    }
  }

  if (errors === 0) {
    console.log(`OK: content/items/catalog.json (${catalogIds.size} item ids)`);
  }
  return errors;
}

function isAuthoredItem(item) {
  if (item.authored === false) return false;
  const description = String(item.description ?? "");
  if (description.trim() === "") return false;
  if (PLACEHOLDER_DESC.test(description)) return false;
  if (item.value === null) return false;
  return true;
}

function validateAuthoredContent(itemPath, item) {
  let errors = 0;
  const rel = relative(repoRoot, itemPath);
  const authored = item.authored !== false;
  const description = String(item.description ?? "");
  if (!authored) {
    console.error(`FAIL: ${rel} has authored: false`);
    errors++;
  }
  if (description.trim() === "") {
    console.error(`FAIL: ${rel} has empty description`);
    errors++;
  }
  if (PLACEHOLDER_DESC.test(description)) {
    console.error(`FAIL: ${rel} uses placeholder description`);
    errors++;
  }
  if (item.value === null) {
    console.error(`FAIL: ${rel} has null value`);
    errors++;
  }
  if (strictContent && !isAuthoredItem(item)) {
    // --strict-content retained for CI script compatibility; rules are always enforced.
  }
  return errors;
}

function validateContentRules() {
  let errors = 0;
  errors += validateXpCurveKeys();
  errors += validateAffixRarityNaming();
  errors += validateLootTableCatalog();
  const itemDirs = [
    join(contentRoot, "items", "equipment"),
    join(contentRoot, "items", "consumables"),
    join(contentRoot, "items", "materials"),
  ];
  const relicsDir = join(contentRoot, "relics");

  for (const dir of itemDirs) {
    if (!existsSync(dir)) continue;
    for (const entry of readdirSync(dir)) {
      if (!entry.endsWith(".json")) continue;
      const itemPath = join(dir, entry);
      const item = JSON.parse(readFileSync(itemPath, "utf8"));
      errors += validateAuthoredContent(itemPath, item);
      errors += validateItemStatRules(itemPath, item);
    }
  }

  if (existsSync(relicsDir)) {
    for (const entry of readdirSync(relicsDir)) {
      if (!entry.endsWith(".json")) continue;
      const itemPath = join(relicsDir, entry);
      const item = JSON.parse(readFileSync(itemPath, "utf8"));
      errors += validateAuthoredContent(itemPath, item);
    }
  }

  if (errors === 0) {
    console.log("OK: content authorship, stat keys, and weaponId rules");
  }
  return errors;
}

function validateItemStatRules(itemPath, item) {
  let errors = 0;
  const stats = item.stats ?? {};
  for (const stat of Object.keys(stats)) {
    if (!ALLOWED_ITEM_STAT_KEYS.has(stat)) {
      console.error(`FAIL: ${relative(repoRoot, itemPath)} uses unknown stat key "${stat}"`);
      errors++;
    }
  }
  const slot = item.equipmentSlot ?? "";
  if (item.itemType === "weapon" && slot === "weapon" && !item.weaponId) {
    console.error(`FAIL: ${relative(repoRoot, itemPath)} weapon item missing weaponId`);
    errors++;
  }
  if (item.weaponId) {
    const weaponPath = join(contentRoot, "weapons", `${item.weaponId}.json`);
    if (!existsSync(weaponPath)) {
      console.error(
        `FAIL: ${relative(repoRoot, itemPath)} weaponId "${item.weaponId}" has no content/weapons/${item.weaponId}.json`
      );
      errors++;
    }
  }
  return errors;
}

function validateXpCurveKeys() {
  const curvePath = join(contentRoot, "progression", "xp_curve.json");
  if (!existsSync(curvePath)) {
    console.error("FAIL: content/progression/xp_curve.json not found");
    return 1;
  }
  const curve = JSON.parse(readFileSync(curvePath, "utf8"));
  let errors = 0;
  for (const legacyKey of ["baseXpPerRun", "tierXpBonus"]) {
    if (Object.prototype.hasOwnProperty.call(curve, legacyKey)) {
      console.error(`FAIL: xp_curve.json still uses legacy key "${legacyKey}"`);
      errors++;
    }
  }
  for (const requiredKey of [
    "baseXpPerKill",
    "bossBonusXp",
    "escapeBonusXp",
    "talentPointsPerLevel",
    "levels",
  ]) {
    if (!Object.prototype.hasOwnProperty.call(curve, requiredKey)) {
      console.error(`FAIL: xp_curve.json missing required key "${requiredKey}"`);
      errors++;
    }
  }
  if (errors === 0) {
    console.log("OK: xp_curve runtime keys");
  }
  return errors;
}

function validateAffixRarityNaming() {
  let errors = 0;
  for (const rel of ["affixes/prefixes.json", "affixes/suffixes.json", "affixes/rarity_rules.json"]) {
    const text = readFileSync(join(contentRoot, rel), "utf8");
    if (text.includes('"mythic"')) {
      console.error(`FAIL: ${rel} still contains mythic rarity key`);
      errors++;
    }
  }
  if (errors === 0) {
    console.log("OK: affix content uses aumbral only");
  }
  return errors;
}

function validateLootTableCatalog() {
  const catalogPath = join(contentRoot, "items", "catalog.json");
  if (!existsSync(catalogPath)) {
    return 0;
  }
  const catalog = JSON.parse(readFileSync(catalogPath, "utf8"));
  const catalogIds = new Set();
  for (const category of ["equipment", "consumables", "materials"]) {
    for (const itemId of catalog[category] ?? []) {
      catalogIds.add(itemId);
    }
  }

  const tablesDir = join(contentRoot, "loot", "tables");
  if (!existsSync(tablesDir)) {
    return 0;
  }

  let errors = 0;
  for (const entry of readdirSync(tablesDir)) {
    if (!entry.endsWith(".json")) continue;
    const tablePath = join(tablesDir, entry);
    const table = JSON.parse(readFileSync(tablePath, "utf8"));
    const lootTables = table.lootTables ?? {};
    for (const role of ["treasure", "secret", "side", "armory"]) {
      for (const row of lootTables[role] ?? []) {
        const itemId = row.itemId;
        if (!catalogIds.has(itemId)) {
          console.error(
            `FAIL: ${relative(repoRoot, tablePath)} role ${role} references unknown itemId "${itemId}"`
          );
          errors++;
        }
      }
    }
  }
  if (errors === 0) {
    console.log("OK: loot table itemIds exist in catalog");
  }
  return errors;
}

const DIALOGUE_ACTION_TYPES = new Set([
  "set_flag",
  "increment_flag",
  "add_gold",
  "start_quest",
  "complete_quest",
  "give_item",
  "take_item",
  "unlock_recipe",
  "set_relationship",
  "play_sfx",
  "advance_story_beat",
  "record_discovery",
  "record_rescue",
  "open_blacksmith",
  "open_merchant",
  "open_quest_board",
  "open_storage",
]);

const DIALOGUE_CONDITION_PRIMARY_KEYS = new Set([
  "all",
  "any",
  "not",
  "flag",
  "minLevel",
  "maxLevel",
  "quest",
  "gold",
  "minRuns",
  "minDeaths",
  "hasItem",
  "dungeonCleared",
  "biome",
  "minTier",
  "relationship",
  "storyBeat",
  "questCompletions",
  "lastRunOutcome",
  "lastRunBiome",
  "minLastRunFloor",
  "lastRunBoss",
  "bestiaryKills",
  "bountyTokens",
]);

const DIALOGUE_CONDITION_MODIFIER_KEYS = new Set(["value", "state", "count", "atLeast"]);

const QUEST_TYPES = new Set([
  "kill",
  "fetch",
  "escape",
  "clear_without",
  "reach_depth",
  "discover",
  "escort",
  "defeat_with",
]);

const QUEST_REQUIRED_FIELDS = {
  // "kill" takes no targetId: QuestService.register_kill treats an absent targetId as
  // "any kill counts", which is what the open-ended bounties rely on. "defeat_with"
  // does require one -- it skips every kill whose enemy id does not match.
  kill: [],
  fetch: ["targetItemId"],
  escape: [],
  clear_without: [],
  reach_depth: ["requiredCount"],
  discover: [],
  escort: ["targetNpcId"],
  defeat_with: ["targetId"],
};

function readJsonDir(relDir) {
  const dirPath = join(contentRoot, relDir);
  const out = new Map();
  if (!existsSync(dirPath)) return out;
  for (const entry of readdirSync(dirPath)) {
    if (!entry.endsWith(".json")) continue;
    out.set(entry, JSON.parse(readFileSync(join(dirPath, entry), "utf8")));
  }
  return out;
}

function collectCatalogItemIds() {
  const catalogPath = join(contentRoot, "items", "catalog.json");
  const ids = new Set();
  if (!existsSync(catalogPath)) return ids;
  const catalog = JSON.parse(readFileSync(catalogPath, "utf8"));
  for (const category of ["equipment", "consumables", "materials"]) {
    for (const itemId of catalog[category] ?? []) ids.add(itemId);
  }
  return ids;
}

function collectRecipeIds() {
  const ids = new Set();
  for (const [, parsed] of readJsonDir("recipes")) {
    const rows = Array.isArray(parsed) ? parsed : (parsed.recipes ?? [parsed]);
    for (const row of rows) {
      if (row && typeof row.id === "string") ids.add(row.id);
    }
  }
  return ids;
}

function collectIdsFromDir(relDir) {
  const ids = new Set();
  for (const [, parsed] of readJsonDir(relDir)) {
    if (parsed && typeof parsed.id === "string") ids.add(parsed.id);
  }
  return ids;
}

function walkDialogueConditions(condition, onError, where) {
  if (condition === null || condition === undefined) return;
  if (typeof condition !== "object" || Array.isArray(condition)) {
    onError(where + " condition must be an object");
    return;
  }
  const keys = Object.keys(condition);
  if (keys.length === 0) return;
  let primary = 0;
  for (const key of keys) {
    if (DIALOGUE_CONDITION_PRIMARY_KEYS.has(key)) {
      primary++;
    } else if (!DIALOGUE_CONDITION_MODIFIER_KEYS.has(key)) {
      onError(where + " unknown condition key \"" + key + "\"");
    }
  }
  if (primary === 0) {
    onError(where + " condition has no recognised predicate (keys: " + keys.join(", ") + ")");
  }
  for (const key of ["all", "any"]) {
    for (const [i, entry] of (condition[key] ?? []).entries()) {
      walkDialogueConditions(entry, onError, where + "/" + key + "[" + i + "]");
    }
  }
  if (condition.not !== undefined) {
    walkDialogueConditions(condition.not, onError, where + "/not");
  }
}

function validateNarrativeContent() {
  let errors = 0;
  const fail = (message) => {
    console.error("FAIL: " + message);
    errors++;
  };

  const dialogues = readJsonDir("dialogue");
  const quests = readJsonDir("quests");
  const npcs = readJsonDir("npcs");
  const itemIds = collectCatalogItemIds();
  const recipeIds = collectRecipeIds();
  const dungeonIds = collectIdsFromDir("dungeons");
  const biomeIds = collectIdsFromDir("biomes");
  const npcIds = collectIdsFromDir("npcs");
  const creatureIds = new Set([
    ...collectIdsFromDir("enemies"),
    ...collectIdsFromDir("bosses"),
  ]);
  const bestiaryIds = new Set();
  const bestiaryPath = join(contentRoot, "bestiary", "entries.json");
  if (existsSync(bestiaryPath)) {
    const bestiary = JSON.parse(readFileSync(bestiaryPath, "utf8"));
    for (const entry of bestiary.entries ?? []) {
      if (bestiaryIds.has(entry.enemyId)) {
        fail("content/bestiary/entries.json duplicates enemyId \"" + entry.enemyId + "\"");
      }
      bestiaryIds.add(entry.enemyId);
      if (!creatureIds.has(entry.enemyId)) {
        fail(
          "content/bestiary/entries.json enemyId \"" + entry.enemyId + "\" is not an enemy or boss"
        );
      }
      if (entry.biomeId !== undefined && !biomeIds.has(entry.biomeId)) {
        fail(
          "content/bestiary/entries.json entry \""
            + entry.enemyId
            + "\" has unknown biome \""
            + entry.biomeId
            + "\""
        );
      }
    }
  }

  const dialogueIds = new Set();
  for (const [file, def] of dialogues) {
    if (typeof def.id !== "string" || def.id === "") {
      fail("content/dialogue/" + file + " has no id");
      continue;
    }
    if (dialogueIds.has(def.id)) {
      fail("content/dialogue/" + file + " duplicates dialogue id \"" + def.id + "\"");
    }
    dialogueIds.add(def.id);
  }

  const questIds = new Set();
  for (const [file, def] of quests) {
    if (file === "dungeon_quests.json") continue;
    if (typeof def.id === "string" && def.id !== "") questIds.add(def.id);
    else fail("content/quests/" + file + " has no id");
  }

  for (const [file, def] of dialogues) {
    const where = "content/dialogue/" + file;
    const nodes = def.nodes ?? {};
    const nodeIds = new Set(Object.keys(nodes));
    if (!nodeIds.has(def.startNode)) {
      fail(where + " startNode \"" + def.startNode + "\" is not a node");
    }
    const checkTarget = (target, label) => {
      if (target === undefined || target === "" || target === "end") return;
      if (!nodeIds.has(target)) {
        fail(where + " " + label + " points at missing node \"" + target + "\"");
      }
    };
    const checkActions = (actions, label) => {
      for (const [i, action] of (actions ?? []).entries()) {
        const at = label + "/actions[" + i + "]";
        if (!action || typeof action !== "object") {
          fail(where + " " + at + " is not an object");
          continue;
        }
        const type = action.type;
        if (!DIALOGUE_ACTION_TYPES.has(type)) {
          fail(where + " " + at + " unknown action type \"" + type + "\"");
          continue;
        }
        if ((type === "start_quest" || type === "complete_quest") && !questIds.has(action.questId)) {
          fail(where + " " + at + " references unknown quest \"" + action.questId + "\"");
        }
        if ((type === "give_item" || type === "take_item") && !itemIds.has(action.itemId)) {
          fail(where + " " + at + " references unknown item \"" + action.itemId + "\"");
        }
        if (type === "unlock_recipe" && !recipeIds.has(action.recipeId)) {
          fail(where + " " + at + " references unknown recipe \"" + action.recipeId + "\"");
        }
        if (type === "record_rescue" && !npcIds.has(action.npcId)) {
          fail(where + " " + at + " references unknown npc \"" + action.npcId + "\"");
        }
        if (type === "set_flag" && typeof action.flag !== "string") {
          fail(where + " " + at + " set_flag needs a flag id");
        }
        if (type === "increment_flag" && typeof action.flag !== "string") {
          fail(where + " " + at + " increment_flag needs a flag id");
        }
        if (type === "set_relationship" && typeof action.npc !== "string") {
          fail(where + " " + at + " set_relationship needs an npc key");
        }
        if (type === "record_discovery" && typeof action.discoveryId !== "string") {
          fail(where + " " + at + " record_discovery needs a discoveryId");
        }
      }
    };
    const checkCondition = (condition, label) => {
      if (condition === undefined) return;
      walkDialogueConditions(condition, (message) => fail(where + " " + message), label);
      const scan = (node) => {
        if (!node || typeof node !== "object") return;
        if (typeof node.dungeonCleared === "string" && !dungeonIds.has(node.dungeonCleared)) {
          fail(where + " " + label + " references unknown dungeon \"" + node.dungeonCleared + "\"");
        }
        if (typeof node.biome === "string" && !biomeIds.has(node.biome)) {
          fail(where + " " + label + " references unknown biome \"" + node.biome + "\"");
        }
        if (typeof node.lastRunBiome === "string" && !biomeIds.has(node.lastRunBiome)) {
          fail(
            where + " " + label + " references unknown biome \"" + node.lastRunBiome + "\""
          );
        }
        if (typeof node.bestiaryKills === "string" && !bestiaryIds.has(node.bestiaryKills)) {
          fail(
            where
              + " "
              + label
              + " references unknown bestiary entry \""
              + node.bestiaryKills
              + "\""
          );
        }
        if (typeof node.hasItem === "string" && !itemIds.has(node.hasItem)) {
          fail(where + " " + label + " references unknown item \"" + node.hasItem + "\"");
        }
        if (typeof node.quest === "string" && !questIds.has(node.quest)) {
          fail(where + " " + label + " references unknown quest \"" + node.quest + "\"");
        }
        if (typeof node.questCompletions === "string" && !questIds.has(node.questCompletions)) {
          fail(where + " " + label + " references unknown quest \"" + node.questCompletions + "\"");
        }
        for (const entry of node.all ?? []) scan(entry);
        for (const entry of node.any ?? []) scan(entry);
        if (node.not) scan(node.not);
      };
      scan(condition);
    };

    for (const [nodeId, node] of Object.entries(nodes)) {
      const label = "node \"" + nodeId + "\"";
      checkTarget(node.next, label + " next");
      checkTarget(node.fallback, label + " fallback");
      checkActions(node.actions, label);
      checkCondition(node.condition, label);
      for (const [i, choice] of (node.choices ?? []).entries()) {
        const choiceLabel = label + " choice[" + i + "]";
        checkTarget(choice.next, choiceLabel + " next");
        checkActions(choice.actions, choiceLabel);
        checkCondition(choice.condition, choiceLabel);
        if ((choice.next === undefined || choice.next === "") && (choice.actions ?? []).length === 0) {
          fail(where + " " + choiceLabel + " has neither next nor actions");
        }
      }
      if (!node.choices && node.next === undefined && node.fallback === undefined) {
        fail(where + " " + label + " is a dead end (no next, fallback or choices)");
      }
    }
  }

  for (const [file, def] of quests) {
    if (file === "dungeon_quests.json") {
      for (const entry of def.quests ?? []) {
        const at = "content/quests/" + file + " entry \"" + entry.questId + "\"";
        if (!dialogueIds.has(entry.dialogueId)) {
          fail(at + " has unknown dialogueId \"" + entry.dialogueId + "\"");
        }
        if (!itemIds.has(entry.rewardItemId)) {
          fail(at + " has unknown rewardItemId \"" + entry.rewardItemId + "\"");
        }
        for (const biome of entry.biomes ?? []) {
          if (!biomeIds.has(biome)) {
            fail(at + " has unknown biome \"" + biome + "\"");
          }
        }
      }
      continue;
    }
    const where = "content/quests/" + file;
    if (!QUEST_TYPES.has(def.type)) {
      fail(where + " unknown quest type \"" + def.type + "\"");
      continue;
    }
    for (const field of QUEST_REQUIRED_FIELDS[def.type]) {
      if (def[field] === undefined) {
        fail(where + " type \"" + def.type + "\" requires \"" + field + "\"");
      }
    }
    for (const prerequisite of def.prerequisites ?? []) {
      if (!questIds.has(prerequisite)) {
        fail(where + " prerequisite \"" + prerequisite + "\" is not a quest");
      }
      if (prerequisite === def.id) {
        fail(where + " lists itself as a prerequisite");
      }
    }
    if (def.targetItemId !== undefined && !itemIds.has(def.targetItemId)) {
      fail(where + " targetItemId \"" + def.targetItemId + "\" is not in the item catalog");
    }
    if (def.weaponItemId !== undefined && !itemIds.has(def.weaponItemId)) {
      fail(where + " weaponItemId \"" + def.weaponItemId + "\" is not in the item catalog");
    }
    if (def.targetNpcId !== undefined && !npcIds.has(def.targetNpcId)) {
      fail(where + " targetNpcId \"" + def.targetNpcId + "\" is not an NPC");
    }
    if (def.dungeonId !== undefined && !dungeonIds.has(def.dungeonId)) {
      fail(where + " dungeonId \"" + def.dungeonId + "\" is not a dungeon");
    }
    if (def.biomeId !== undefined && !biomeIds.has(def.biomeId)) {
      fail(where + " biomeId \"" + def.biomeId + "\" is not a biome");
    }
    if (def.repeatable !== true && def.cooldownRuns !== undefined) {
      fail(where + " cooldownRuns is only meaningful on a repeatable quest");
    }
    if (def.availableWhen !== undefined) {
      walkDialogueConditions(
        def.availableWhen,
        (message) => fail(where + " " + message),
        "availableWhen"
      );
    }
    for (const item of def.rewards?.items ?? []) {
      if (!itemIds.has(item.itemId)) {
        fail(where + " reward item \"" + item.itemId + "\" is not in the item catalog");
      }
    }
    if (def.rewards?.recipeId !== undefined && !recipeIds.has(def.rewards.recipeId)) {
      fail(where + " reward recipe \"" + def.rewards.recipeId + "\" does not exist");
    }
  }

  const questPrereqs = new Map();
  for (const [file, def] of quests) {
    if (file === "dungeon_quests.json") continue;
    questPrereqs.set(def.id, def.prerequisites ?? []);
  }
  const chainState = new Map();
  const visit = (questId, trail) => {
    if (chainState.get(questId) === "done") return;
    if (chainState.get(questId) === "open") {
      fail("content/quests prerequisite cycle: " + [...trail, questId].join(" -> "));
      return;
    }
    chainState.set(questId, "open");
    for (const prerequisite of questPrereqs.get(questId) ?? []) {
      if (questPrereqs.has(prerequisite)) visit(prerequisite, [...trail, questId]);
    }
    chainState.set(questId, "done");
  };
  for (const questId of questPrereqs.keys()) visit(questId, []);

  for (const [file, def] of npcs) {
    const where = "content/npcs/" + file;
    if (def.dialogueId !== undefined && def.dialogueId !== "" && !dialogueIds.has(def.dialogueId)) {
      fail(where + " dialogueId \"" + def.dialogueId + "\" does not exist");
    }
    for (const [i, rule] of (def.dialogueRules ?? []).entries()) {
      if (!dialogueIds.has(rule.dialogueId)) {
        fail(where + " dialogueRules[" + i + "] dialogueId \"" + rule.dialogueId + "\" does not exist");
      }
      walkDialogueConditions(
        rule.condition,
        (message) => fail(where + " " + message),
        "dialogueRules[" + i + "]"
      );
    }
  }

  if (errors === 0) {
    console.log(
      "OK: narrative graph ("
        + dialogues.size
        + " dialogue trees, "
        + questIds.size
        + " quests, "
        + npcs.size
        + " npcs)"
    );
  }
  return errors;
}


function validateSchemaManifest() {
  const manifestPath = join(schemasRoot, "MANIFEST.json");
  if (!existsSync(manifestPath)) {
    console.error("FAIL: content/schemas/MANIFEST.json is missing");
    return 1;
  }

  let manifest;
  try {
    manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
  } catch (err) {
    console.error(`FAIL: content/schemas/MANIFEST.json is not valid JSON — ${err.message}`);
    return 1;
  }

  const entries = Object.entries(manifest.schemas ?? {});
  if (entries.length === 0) {
    console.error("FAIL: content/schemas/MANIFEST.json declares no schemas");
    return 1;
  }

  let errors = 0;
  const retiredDir = join(schemasRoot, "retired");

  for (const [name, entry] of entries) {
    const current = String(entry.current ?? "");
    if (!current) {
      console.error(`FAIL: MANIFEST entry '${name}' has no current version`);
      errors++;
      continue;
    }

    const currentFile = join(schemasRoot, `${name}.${current}.json`);
    if (!existsSync(currentFile)) {
      console.error(`FAIL: MANIFEST pins ${name} to ${current} but ${name}.${current}.json is missing`);
      errors++;
    }

    for (const retired of entry.retired ?? []) {
      const live = join(schemasRoot, `${name}.${retired}.json`);
      const quarantined = join(retiredDir, `${name}.${retired}.json`);
      if (existsSync(live)) {
        console.error(
          `FAIL: ${name}.${retired}.json is retired but still in content/schemas/ — move it to content/schemas/retired/`
        );
        errors++;
      } else if (!existsSync(quarantined)) {
        console.error(`FAIL: retired schema ${name}.${retired}.json is referenced but not found in content/schemas/retired/`);
        errors++;
      }
    }
  }

  const declared = new Set();
  for (const [name, entry] of entries) {
    declared.add(`${name}.${String(entry.current)}.json`);
  }
  for (const file of readdirSync(schemasRoot)) {
    if (!file.endsWith(".json") || file === "MANIFEST.json") continue;
    const match = /^(.*)\.(v\d+)\.json$/.exec(file);
    if (!match) continue;
    const [, name, version] = match;
    const entry = manifest.schemas?.[name];
    if (entry && String(entry.current) !== version && !declared.has(file)) {
      console.error(
        `FAIL: ${file} is present but MANIFEST pins ${name} to ${entry.current}; declare it under "retired" and move it`
      );
      errors++;
    }
  }

  if (errors === 0) {
    console.log(`OK: schema manifest (${entries.length} schemas pinned)`);
  }
  return errors;
}

function validateAudioPlaceholders() {
  const bankPath = join(contentRoot, "audio", "sfx.json");
  if (!existsSync(bankPath)) {
    console.log("OK: audio bank (no content/audio/sfx.json to check)");
    return 0;
  }

  let bank;
  try {
    bank = JSON.parse(readFileSync(bankPath, "utf8"));
  } catch (err) {
    console.error(`FAIL: content/audio/sfx.json is not valid JSON — ${err.message}`);
    return 1;
  }

  const assetsRoot = join(repoRoot, "apps", "game", "client");
  const seenFiles = new Map();
  let errors = 0;
  let placeholders = 0;

  for (const [key, entry] of Object.entries(bank.sfx ?? bank.entries ?? bank)) {
    if (!entry || typeof entry !== "object") continue;

    if (entry.placeholder === true) {
      placeholders++;
      console.warn(`PLACEHOLDER: sfx '${key}' is flagged as temporary foley`);
      continue;
    }

    const variants = Array.isArray(entry.variants)
      ? entry.variants
      : entry.path
        ? [entry.path]
        : [];
    for (const variant of variants) {
      const rel = String(typeof variant === "string" ? variant : (variant?.path ?? ""));
      if (!rel) continue;
      const abs = join(assetsRoot, rel.replace(/^res:\/\//, ""));
      if (!existsSync(abs)) {
        console.error(`FAIL: sfx '${key}' references missing file ${rel}`);
        errors++;
        continue;
      }
      const owner = seenFiles.get(rel);
      if (owner && owner !== key) {
        console.error(
          `FAIL: sfx '${key}' reuses ${rel}, already used by '${owner}' — mark one "placeholder": true or author distinct foley`
        );
        errors++;
      } else {
        seenFiles.set(rel, key);
      }
    }
  }

  if (placeholders > 0) {
    console.warn(`${placeholders} placeholder sfx entr${placeholders === 1 ? "y" : "ies"} still need real foley`);
    if (strictContent) {
      console.error("FAIL: placeholder sfx entries are not allowed under --strict-content");
      errors += placeholders;
    }
  }

  if (errors === 0) {
    console.log("OK: audio bank references distinct existing files");
  }
  return errors;
}


const catalogFailures = validateItemCatalogConsistency();
failures += catalogFailures;

const contentRuleFailures = validateContentRules();
failures += contentRuleFailures;

failures += validateNarrativeContent();
failures += validateSchemaManifest();
failures += validateAudioPlaceholders();

if (failures > 0) {
  process.exit(1);
}

console.log(`Validated ${files.length} file(s).`);
