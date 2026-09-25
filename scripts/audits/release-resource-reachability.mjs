#!/usr/bin/env node
/** Check static Godot resource references against the configured release exclusions. */
import { existsSync, readFileSync, readdirSync, statSync } from "node:fs";
import { join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = resolve(fileURLToPath(new URL("../..", import.meta.url)));
const CLIENT = join(ROOT, "apps/game/client");
const CONTENT = join(ROOT, "content");
const PRESETS = join(CLIENT, "export_presets.cfg");
const SCENE_ROUTER = join(CLIENT, "scripts/app/run_scene_router.gd");
const EXCLUDED_DIRS = new Set([".godot"]);
const RESOURCE_EXTENSIONS = new Set([
  ".gd", ".tscn", ".tres", ".godot", ".cs", ".csproj", ".gdshader", ".import",
]);

function collect(directory, output = []) {
  for (const name of readdirSync(directory).sort()) {
    if (EXCLUDED_DIRS.has(name)) continue;
    const path = join(directory, name);
    const info = statSync(path);
    if (info.isDirectory()) collect(path, output);
    else if (RESOURCE_EXTENSIONS.has(path.slice(path.lastIndexOf(".")).toLowerCase())) output.push(path);
  }
  return output;
}

function collectJson(directory, output = []) {
  for (const name of readdirSync(directory).sort()) {
    if (EXCLUDED_DIRS.has(name)) continue;
    const path = join(directory, name);
    const info = statSync(path);
    if (info.isDirectory()) collectJson(path, output);
    else if (name.toLowerCase().endsWith(".json")) output.push(path);
  }
  return output;
}

function readExcludedPaths(text) {
  const paths = new Set();
  for (const match of text.matchAll(/^exclude_filter="([^"]*)"/gm)) {
    for (const raw of match[1].split(",").map((item) => item.trim()).filter(Boolean)) {
      paths.add(raw.replace(/\*+$/, ""));
    }
  }
  return paths;
}

const excluded = readExcludedPaths(readFileSync(PRESETS, "utf8"));
const files = [
  ...collect(CLIENT).map((path) => ({ path, base: CLIENT, scope: "client" })),
  ...collectJson(CONTENT)
    .map((path) => ({ path, base: ROOT, scope: "content" })),
];
const findings = [];
const referencePattern = /(?:res:\/\/)([^"'`\s)]+)|(?:path\s*=\s*")(res:\/\/[^\"]+)/g;
for (const source of files) {
  const sourcePath = source.path;
  const sourceRelative = relative(source.base, sourcePath).split("\\").join("/");
  const sourceIsExcluded = source.scope === "client"
    && [...excluded].some((prefix) => sourceRelative.startsWith(prefix));
  if (sourceIsExcluded) continue;
  const sourceText = readFileSync(sourcePath, "utf8");
  for (const match of sourceText.matchAll(referencePattern)) {
    const target = (match[1] ?? match[2] ?? "").replace(/^res:\/\//, "").replace(/[),;]+$/, "");
    if (!target || target.startsWith("uid://")) continue;
    // Interpolated resource paths are checked by their catalog/runtime-specific validators.
    if (target.includes("%")) continue;
    const targetRelative = target.split("/").join("/");
    const excludedPrefix = [...excluded].find((prefix) => targetRelative.startsWith(prefix));
    // Godot editor plugin registration is not part of runtime resource reachability.
    if (sourceRelative === "project.godot" && targetRelative.startsWith("addons/godot_mcp/")) continue;
    if (excludedPrefix && !sourceIsExcluded) {
      findings.push({
        kind: "excluded-target",
        source: source.scope === "content" ? `content/${relative(CONTENT, sourcePath).split("\\").join("/")}` : sourceRelative,
        target: `res://${targetRelative}`,
        excludedBy: excludedPrefix,
      });
    }
    if (!existsSync(join(CLIENT, targetRelative))) {
      // The app id file is a developer/Steam-launch convenience; SteamService has a runtime
      // fallback and distribution launchers provide it beside the executable when needed.
      if (targetRelative === "steam_appid.txt") continue;
      findings.push({
        kind: "missing-target",
        source: source.scope === "content" ? `content/${relative(CONTENT, sourcePath).split("\\").join("/")}` : sourceRelative,
        target: `res://${targetRelative}`,
      });
    }
  }
}

const errors = findings.filter((finding) => finding.kind === "missing-target"
  || finding.kind === "excluded-target");
const packFlag = process.argv.indexOf("--pack");
const packPath = packFlag >= 0 ? resolve(process.argv[packFlag + 1] ?? "") : "";
const packFindings = [];
if (packFlag >= 0) {
  if (!packPath || !existsSync(packPath)) {
    packFindings.push({ kind: "missing-pack", pack: process.argv[packFlag + 1] ?? "" });
  } else {
    // Godot's PCK resource table stores each published path as path="res://...". Read the table
    // directly so validation reflects the actual export, not merely the editor's source tree.
    const packText = readFileSync(packPath).toString("latin1");
    const packedPaths = new Set([...packText.matchAll(/path="res:\/\/([^"]+)"/g)].map((match) => match[1]));
    for (const path of packedPaths) {
      const excludedPrefix = [...excluded].find((prefix) => path.startsWith(prefix));
      if (excludedPrefix) packFindings.push({ kind: "excluded-packed-resource", path, excludedBy: excludedPrefix });
    }
    const routes = [...readFileSync(SCENE_ROUTER, "utf8").matchAll(/const\s+\w+_SCENE\s*:=\s*"res:\/\/([^"]+\.tscn)"/g)]
      .map((match) => match[1]);
    routes.push("scenes/ui/main_menu.tscn");
    const roomKinds = [
      "entrance", "stairs", "corridor", "courtyard", "hall", "treasure", "secret",
      "arena", "boss", "puzzle", "corridor_long", "corridor_bend", "balcony",
    ];
    for (const biomePath of collectJson(join(CONTENT, "biomes"))) {
      const biome = JSON.parse(readFileSync(biomePath, "utf8"));
      const prefix = String(biome.templatePrefix ?? "");
      const folder = String(biome.assetFolder ?? "");
      if (!prefix || !folder) {
        packFindings.push({ kind: "invalid-biome-room-route", source: relative(ROOT, biomePath) });
        continue;
      }
      for (const kind of roomKinds) {
        routes.push(`scenes/rooms/${folder}/${prefix}_${kind}.tscn`);
      }
    }
    let routedSceneCount = 0;
    for (const route of new Set(routes)) {
      const basename = route.slice(route.lastIndexOf("/") + 1, -".tscn".length);
      const included = packedPaths.has(`${route}.remap`)
        || [...packedPaths].some((path) => path.startsWith(".godot/exported/") && path.endsWith(`-${basename}.scn`));
      if (!included) packFindings.push({ kind: "missing-packed-route", route: `res://${route}` });
      else routedSceneCount += 1;
    }
    packFindings.push({ kind: "informational", routesChecked: routedSceneCount });
  }
}
const packErrors = packFindings.filter((finding) => finding.kind !== "informational");
console.log(JSON.stringify({
  resourcesScanned: files.length,
  contentJsonScanned: files.filter((file) => file.scope === "content").length,
  releaseExclusions: [...excluded],
  staticReferencesChecked: true,
  errors: errors.length,
  findings,
  exportedPack: packPath || null,
  packedResourceErrors: packErrors.length,
  packedResourceFindings: packFindings,
}, null, 2));
if (errors.length || packErrors.length) process.exitCode = 1;
