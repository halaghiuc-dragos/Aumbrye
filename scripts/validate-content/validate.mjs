import { readFileSync, readdirSync, statSync, existsSync } from "node:fs";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import Ajv from "ajv";
import addFormats from "ajv-formats";

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(__dirname, "../..");
const contentRoot = join(repoRoot, "content");
const schemasRoot = join(contentRoot, "schemas");
const strictContent = process.argv.includes("--strict-content");
const PLACEHOLDER_DESC = /^M6 content item\.?$/i;

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
]);


const SCHEMA_MAP = {
  dungeon_definition: "dungeon-definition.v1.json",
  enemy_definition: "enemy-definition.v1.json",
  weapon_definition: "weapon-definition.v1.json",
  item_instance: "item-instance.v1.json",
  inventory: "inventory.v1.json",
};

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
    return join(schemasRoot, "dungeon-definition.v1.json");
  }
  if (name === "fixtures/inventory_sample.v1.json") {
    return join(schemasRoot, "inventory.v1.json");
  }
  if (name.startsWith("enemies/")) {
    return join(schemasRoot, "enemy-definition.v1.json");
  }
  if (name.startsWith("weapons/")) {
    return join(schemasRoot, "weapon-definition.v1.json");
  }
  if (name === "items/catalog.json") {
    return join(schemasRoot, "item-catalog.v1.json");
  }
  if (name.startsWith("items/")) {
    return join(schemasRoot, "item-instance.v1.json");
  }
  if (name.startsWith("bosses/")) {
    return join(schemasRoot, "enemy-definition.v1.json");
  }
  if (name.startsWith("biomes/")) {
    return join(schemasRoot, "biome-definition.v1.json");
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
  if (name === "talents/tree.json") {
    return join(schemasRoot, "talent-tree.v1.json");
  }
  if (name === "fixtures/character_state_sample.v1.json") {
    return join(schemasRoot, "character-state.v1.json");
  }
  if (name.startsWith("npcs/")) {
    return join(schemasRoot, "npc-definition.v1.json");
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
  if (name.startsWith("achievements/")) {
    return join(schemasRoot, "achievement-catalog.v1.json");
  }
  if (name.startsWith("statuses/")) {
    return join(schemasRoot, "status-definition.v1.json");
  }
  if (name.startsWith("loot/")) {
    return join(schemasRoot, "global-drops.v1.json");
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
    // Preload nested refs used by character-state and affix-pack.
    if (schemaPath.endsWith("character-state.v1.json")) {
      loadSchema(join(schemasRoot, "inventory.v1.json"));
    }
    if (schemaPath.endsWith("affix-pack.v1.json")) {
      loadSchema(join(schemasRoot, "affix-definition.v1.json"));
    }
  }
  return schemaCache.get(schemaPath);
}

const files = collectJsonFiles(contentRoot);
let failures = 0;

for (const filePath of files) {
  const schemaPath = resolveSchemaForFile(filePath);
  if (!schemaPath) {
    console.warn(`SKIP (no schema): ${relative(repoRoot, filePath)}`);
    continue;
  }

  const schemaId = loadSchema(schemaPath);
  const data = JSON.parse(readFileSync(filePath, "utf8"));
  const validate = ajv.getSchema(schemaId);

  if (!validate) {
    console.error(`FAIL: could not compile schema for ${relative(repoRoot, filePath)}`);
    failures++;
    continue;
  }

  if (!validate(data)) {
    console.error(`FAIL: ${relative(repoRoot, filePath)}`);
    for (const err of validate.errors ?? []) {
      console.error(`  - ${err.instancePath || "/"} ${err.message}`);
    }
    failures++;
  } else {
    console.log(`OK: ${relative(repoRoot, filePath)}`);
  }
}

const catalogFailures = validateItemCatalogConsistency();
failures += catalogFailures;

const contentRuleFailures = validateContentRules();
failures += contentRuleFailures;

if (failures > 0) {
  process.exit(1);
}

console.log(`Validated ${files.length} file(s).`);

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
  const fileIds = new Map();

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
      fileIds.set(itemId, relative(contentRoot, itemPath).replace(/\\/g, "/"));
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
        console.warn(
          `WARN: ${itemId} itemType "${item.itemType}" unexpected in folder "${category}"`
        );
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

function validateContentRules() {
  let errors = 0;
  const equipmentDir = join(contentRoot, "items", "equipment");
  for (const entry of readdirSync(equipmentDir)) {
    if (!entry.endsWith(".json")) continue;
    const itemPath = join(equipmentDir, entry);
    const item = JSON.parse(readFileSync(itemPath, "utf8"));
    const itemId = item.id ?? entry.replace(/\.json$/, "");
    const description = String(item.description ?? "");
    if (strictContent && PLACEHOLDER_DESC.test(description)) {
      console.error(`FAIL: ${relative(repoRoot, itemPath)} uses placeholder description`);
      errors++;
    }
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
  }
  if (errors === 0) {
    console.log("OK: content stat keys and weaponId rules");
  }
  return errors;
}
