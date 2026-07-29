import { readFileSync, readdirSync, statSync } from "node:fs";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import Ajv from "ajv";
import addFormats from "ajv-formats";

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(__dirname, "../..");
const contentRoot = join(repoRoot, "content");
const schemasRoot = join(contentRoot, "schemas");

const SCHEMA_MAP = {
  dungeon_definition: "dungeon-definition.v1.json",
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

function resolveSchemaForFixture(filePath) {
  const name = relative(contentRoot, filePath).replace(/\\/g, "/");
  if (name.startsWith("fixtures/dungeon_definition")) {
    return join(schemasRoot, SCHEMA_MAP.dungeon_definition);
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
  }
  return schemaCache.get(schemaPath);
}

const files = collectJsonFiles(contentRoot);
let failures = 0;

for (const filePath of files) {
  const schemaPath = resolveSchemaForFixture(filePath);
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

if (failures > 0) {
  process.exit(1);
}

console.log(`Validated ${files.length} file(s).`);
