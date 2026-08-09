import fs from "fs";
import path from "path";

const ROOT = path.resolve(
  path.dirname(new URL(import.meta.url).pathname).replace(/^\/([A-Za-z]:)/, "$1"),
  ".."
);
const CLIENT = path.join(ROOT, "apps/game/client");
const CSV = path.join(CLIENT, "translations/strings.csv");

const csvKeys = new Set(
  fs
    .readFileSync(CSV, "utf8")
    .split(/\r?\n/)
    .slice(1)
    .map((l) => (l.startsWith('"') ? (l.match(/^"((?:[^"]|"")*)"/) || [])[1] : l.split(",")[0]))
    .filter(Boolean)
);

const used = new Map(); // key -> Set(file)
function scan(dir) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) {
      if ([".godot", "addons", "artifacts"].includes(e.name)) continue;
      scan(p);
      continue;
    }
    if (!e.name.endsWith(".gd")) continue;
    const src = fs.readFileSync(p, "utf8");
    for (const m of src.matchAll(/\btr\(\s*"([A-Z][A-Z0-9_]{2,})"/g)) add(m[1], p);
    for (const m of src.matchAll(/\btr\(\s*'([A-Z][A-Z0-9_]{2,})'/g)) add(m[1], p);
    // tr("PREFIX_%s" % x) -> record prefix pattern for reporting only
    for (const m of src.matchAll(/"(SETTINGS_PAGE)_%s"/g)) add(m[1] + "_*", p);
  }
}
function add(k, f) {
  if (!used.has(k)) used.set(k, new Set());
  used.get(k).add(path.relative(CLIENT, f));
}

scan(path.join(CLIENT, "scripts"));

const missing = [...used.keys()].filter((k) => !k.endsWith("_*") && !csvKeys.has(k)).sort();
const unusedKeys = [...csvKeys].filter((k) => !used.has(k)).sort();

console.log("csv keys:", csvKeys.size, " literal tr() keys used:", used.size);
console.log("\nMISSING from CSV (" + missing.length + "):");
for (const k of missing) console.log("  " + k + "   <- " + [...used.get(k)].slice(0, 2).join(", "));
console.log("\n(csv keys never referenced by a literal tr(): " + unusedKeys.length + ")");
