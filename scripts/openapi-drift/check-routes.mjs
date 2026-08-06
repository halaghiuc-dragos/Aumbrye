import { readFileSync, readdirSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const specPath = join(root, "packages/shared/openapi/aumbrye-api.v1.yaml");
const apiRoot = join(root, "services/backend/src/Aumbrye.Api");

function collectYamlPaths(yaml) {
  const paths = new Set();
  for (const line of yaml.split(/\r?\n/)) {
    const match = line.match(/^  (\/api\/v1\/[^\s:]+):\s*$/);
    if (match) paths.add(normalizePath(match[1]));
  }
  return paths;
}

function normalizePath(path) {
  let normalized = path.replace(/\{[^}]+}/g, "{id}");
  if (normalized.endsWith("/") && normalized !== "/") {
    normalized = normalized.slice(0, -1);
  }
  return normalized;
}

function collectCsharpRoutes(dir) {
  const routes = new Set();

  for (const file of walk(dir)) {
    const text = readFileSync(file, "utf8");
    let groupPrefix = "";

    for (const line of text.split(/\r?\n/)) {
      const groupMatch = line.match(/MapGroup\(\s*"([^"]+)"/);
      if (groupMatch) {
        groupPrefix = groupMatch[1];
        continue;
      }

      const routeMatch = line.match(/Map(?:Get|Post|Put|Delete|Patch)\(\s*"([^"]*)"/);
      if (!routeMatch) continue;

      let path = routeMatch[1];
      if (path.startsWith("/api/")) {
        routes.add(normalizePath(path));
        continue;
      }

      const base = groupPrefix.replace(/\/$/, "");
      const suffix = path.startsWith("/") ? path : `/${path}`;
      routes.add(normalizePath(`${base}${suffix}`));
    }
  }

  routes.add("/api/v1/health");
  return routes;
}

function walk(dir) {
  const files = [];
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) files.push(...walk(path));
    else if (entry.name.endsWith(".cs")) files.push(path);
  }
  return files;
}

const yamlPaths = collectYamlPaths(readFileSync(specPath, "utf8"));
const apiPaths = collectCsharpRoutes(apiRoot);

const missingInSpec = [...apiPaths].filter((p) => !yamlPaths.has(p)).sort();
const extraInSpec = [...yamlPaths].filter((p) => !apiPaths.has(p)).sort();

if (missingInSpec.length || extraInSpec.length) {
  if (missingInSpec.length) {
    console.error("Routes missing from OpenAPI spec:");
    for (const path of missingInSpec) console.error(`  ${path}`);
  }
  if (extraInSpec.length) {
    console.error("OpenAPI spec paths not mapped in API:");
    for (const path of extraInSpec) console.error(`  ${path}`);
  }
  process.exit(1);
}

console.log(`OpenAPI drift check passed (${apiPaths.size} routes).`);
