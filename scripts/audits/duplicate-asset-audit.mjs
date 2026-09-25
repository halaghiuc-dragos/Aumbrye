#!/usr/bin/env node
/** Classify identical-byte project files without deleting or rewriting any asset. */
import { existsSync, readFileSync, readdirSync, statSync, writeFileSync } from "node:fs";
import { createHash } from "node:crypto";
import { join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(fileURLToPath(new URL("../..", import.meta.url)));
const coveragePath = join(root, "GAME_REVIEW_FILE_COVERAGE.csv");
const reportPath = join(root, "reports/duplicate_asset_classification.json");
const exportMeasurementPath = join(root, "reports/duplicate_asset_export_measurement.json");
const ignored = new Set([
  ".git", ".claude", ".agents", ".codex", "node_modules", ".godot", "bin", "obj", ".import", "reports", "docs",
]);
const textExtensions = new Set([
  ".gd", ".tscn", ".tres", ".godot", ".json", ".cs", ".csproj", ".yaml", ".yml",
  ".mjs", ".js", ".ts", ".md", ".cfg", ".ini", ".xml", ".csv", ".toml", ".shader",
]);

function parseCsvRow(line) {
  const result = [];
  let value = "";
  let quoted = false;
  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if (ch === '"' && quoted && line[i + 1] === '"') {
      value += '"';
      i++;
    } else if (ch === '"') quoted = !quoted;
    else if (ch === "," && !quoted) {
      result.push(value);
      value = "";
    } else value += ch;
  }
  result.push(value);
  return result;
}

function walk(dir, output = []) {
  for (const name of readdirSync(dir)) {
    if (ignored.has(name)) continue;
    const path = join(dir, name);
    const info = statSync(path);
    if (info.isDirectory()) walk(path, output);
    else output.push(path);
  }
  return output;
}

const rows = readFileSync(coveragePath, "utf8").trimEnd().split(/\r?\n/).slice(1)
  .map(parseCsvRow)
  .filter((row) => row[6] && row[4] !== "0")
  .map((row) => ({ path: row[0], recordedBytes: Number(row[4]), recordedSha256: row[6] }))
  .filter((row) => existsSync(join(root, row.path)) && statSync(join(root, row.path)).isFile())
  .map((row) => {
    const content = readFileSync(join(root, row.path));
    const sha256 = createHash("sha256").update(content).digest("hex");
    return {
      path: row.path,
      bytes: content.length,
      sha256,
      changedSinceCoverage: content.length !== row.recordedBytes
        || sha256 !== row.recordedSha256,
    };
  });
const byHash = new Map();
for (const row of rows) {
  if (!byHash.has(row.sha256)) byHash.set(row.sha256, []);
  byHash.get(row.sha256).push(row);
}
const groups = [...byHash.entries()].filter(([, files]) => files.length > 1);
const candidates = new Set(groups.flatMap(([, files]) => files.map((file) => file.path)));
const references = new Map([...candidates].map((path) => [path, []]));
function referenceAliases(path) {
  const aliases = [path];
  if (path.startsWith("apps/game/client/")) {
    const resourcePath = path.slice("apps/game/client/".length);
    aliases.push(`res://${resourcePath}`, `res://../${path.slice("apps/game/".length)}`);
  }
  if (path.startsWith("content/")) aliases.push(`res://../../${path}`, `res://../../../${path}`);
  return aliases;
}
const candidateAliases = new Map([...candidates].map((path) => [path, referenceAliases(path)]));
const filesToScan = walk(root).filter((path) =>
  path !== coveragePath
  && !["GAME_IMPROVEMENT_PLAN.md", "GAME_REVIEW_FILE_COVERAGE.csv"].includes(relative(root, path))
  && textExtensions.has(path.slice(path.lastIndexOf(".")).toLowerCase()),
);
for (const sourcePath of filesToScan) {
  const sourceRelative = relative(root, sourcePath).split(sep).join("/");
  let source;
  try { source = readFileSync(sourcePath, "utf8"); } catch { continue; }
  for (const candidate of candidates) {
    if (candidate === sourceRelative) continue;
    if (candidateAliases.get(candidate).some((alias) => source.includes(alias))) {
      references.get(candidate).push(sourceRelative);
    }
  }
}

const classified = groups.map(([sha256, files]) => {
  const paths = files.map((file) => ({
    ...file,
    references: references.get(file.path),
    referenced: references.get(file.path).length > 0,
    projectArea: file.path.split("/").slice(0, 3).join("/"),
  }));
  const totalBytes = Math.max(...files.map((file) => file.bytes));
  return {
    sha256,
    bytesPerCopy: totalBytes,
    copies: paths.length,
    potentialDuplicateBytes: totalBytes * (paths.length - 1),
    referencedCopies: paths.filter((file) => file.referenced).length,
    status: paths.every((file) => !file.referenced)
      ? "unreferenced-by-scanned-text-needs-export-verification"
      : paths.some((file) => file.referenced)
        ? "referenced-or-alias-needs-ownership-review"
        : "unknown",
    files: paths,
  };
});
classified.sort((a, b) => b.potentialDuplicateBytes - a.potentialDuplicateBytes);
let exportMeasurement = null;
if (existsSync(exportMeasurementPath)) {
  try {
    const measured = JSON.parse(readFileSync(exportMeasurementPath, "utf8"));
    const unfilteredExists = existsSync(measured.unfilteredPack?.path);
    const filteredExists = existsSync(measured.filteredPack?.path);
    const sizesMatch = unfilteredExists && filteredExists
      && statSync(measured.unfilteredPack.path).size === measured.unfilteredPack.bytes
      && statSync(measured.filteredPack.path).size === measured.filteredPack.bytes;
    if (sizesMatch && measured.filteredPack.bytes < measured.unfilteredPack.bytes) {
      exportMeasurement = measured;
    }
  } catch {
    exportMeasurement = null;
  }
}
const report = {
  generatedAt: new Date().toISOString(),
  source: "GAME_REVIEW_FILE_COVERAGE.csv hashes plus literal paths in project text",
  scannedProjectTextFiles: filesToScan.length,
  liveHashedFiles: rows.length,
  filesChangedSinceCoverage: rows.filter((row) => row.changedSinceCoverage).length,
  identicalByteGroups: classified.length,
  duplicateFiles: classified.reduce((sum, group) => sum + group.copies, 0),
  potentialDuplicateBytes: classified.reduce((sum, group) => sum + group.potentialDuplicateBytes, 0),
  referencedGroups: classified.filter((group) => group.files.some((file) => file.referenced)).length,
  unreferencedGroups: classified.filter((group) => group.status.startsWith("unreferenced")).length,
  exportSizeSavingsVerified: exportMeasurement !== null,
  exportMeasurement,
  deletionPerformed: false,
  groups: classified,
};
writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`, "utf8");
console.log(JSON.stringify({
  report: relative(root, reportPath),
  scannedProjectTextFiles: report.scannedProjectTextFiles,
  liveHashedFiles: report.liveHashedFiles,
  filesChangedSinceCoverage: report.filesChangedSinceCoverage,
  identicalByteGroups: report.identicalByteGroups,
  duplicateFiles: report.duplicateFiles,
  potentialDuplicateBytes: report.potentialDuplicateBytes,
  referencedGroups: report.referencedGroups,
  unreferencedGroups: report.unreferencedGroups,
  exportSizeSavingsVerified: report.exportSizeSavingsVerified,
  verifiedPackBytesAvoided: report.exportMeasurement?.packBytesAvoided ?? null,
  deletionPerformed: false,
}, null, 2));
