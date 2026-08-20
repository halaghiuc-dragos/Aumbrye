#!/usr/bin/env node
/**
 * Cross-platform validation runner — four layers: dotnet, content, python, godot.
 * Usage: node scripts/validate.mjs [--layer <name>]... [--godot <path>]
 */

import { spawnSync } from "node:child_process";
import {
  existsSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { homedir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(__dirname, "..");
const reportsDir = join(repoRoot, "reports");
const summaryPath = join(reportsDir, "validation-summary.json");

const ALL_LAYERS = ["dotnet", "content", "python", "godot"];

function parseArgs(argv) {
  const layers = [];
  let godotBin = null;
  for (let i = 2; i < argv.length; i++) {
    if (argv[i] === "--layer" && i + 1 < argv.length) {
      layers.push(argv[++i]);
    } else if (argv[i] === "--godot" && i + 1 < argv.length) {
      godotBin = argv[++i];
    } else if (argv[i] === "-h" || argv[i] === "--help") {
      console.log("Usage: node scripts/validate.mjs [--layer dotnet|content|python|godot]... [--godot <path>]");
      process.exit(0);
    } else {
      console.error(`Unknown argument: ${argv[i]}`);
      process.exit(1);
    }
  }
  return { layers: layers.length > 0 ? layers : ALL_LAYERS, godotBin };
}

function runCommand(name, command, args, options = {}) {
  console.log(`\n== Layer: ${name} ==`);
  console.log(`> ${command} ${args.join(" ")}`);
  const result = spawnSync(command, args, {
    cwd: options.cwd ?? repoRoot,
    stdio: "inherit",
    shell: process.platform === "win32",
    env: process.env,
  });
  const code = result.status ?? 1;
  return { ok: code === 0, exitCode: code, detail: code === 0 ? "passed" : `exit ${code}` };
}

function resolveGodotExecutable(explicit) {
  const candidates = [];
  if (explicit) candidates.push(explicit);
  if (process.env.GODOT_BIN) candidates.push(process.env.GODOT_BIN);

  const onPath = spawnSync("godot", ["--version"], { encoding: "utf8", shell: true });
  if (onPath.status === 0) candidates.push("godot");

  if (process.platform === "win32") {
    const localAppData = process.env.LOCALAPPDATA ?? "";
    if (localAppData) {
      const programsGodot = join(localAppData, "Programs", "Godot");
      if (existsSync(programsGodot)) {
        for (const entry of readdirSync(programsGodot)) {
          candidates.push(join(programsGodot, entry));
        }
      }
    }
  } else if (process.platform === "darwin") {
    candidates.push("/Applications/Godot.app/Contents/MacOS/Godot");
  } else {
    candidates.push("/usr/local/bin/godot", join(homedir(), ".local", "bin", "godot"));
  }

  for (const candidate of candidates) {
    const resolved = resolveGodotPath(candidate);
    if (resolved) return resolved;
  }
  return null;
}

function resolveGodotPath(path) {
  if (!path || !existsSync(path)) return null;
  const stat = statSync(path);
  if (stat.isDirectory()) {
    const entries = readdirSync(path);
    const consoleExe = entries.find((e) => e.includes("_console") && e.endsWith(".exe"));
    if (consoleExe) return join(path, consoleExe);
    const godotExe = entries.find((e) => /^Godot/i.test(e) && e.endsWith(".exe"));
    if (godotExe) return join(path, godotExe);
    const unixBin = entries.find((e) => e === "Godot" || e.startsWith("Godot_"));
    if (unixBin) return join(path, unixBin);
    return null;
  }
  return path;
}

function runDotnetLayer() {
  const build = runCommand(
    "dotnet",
    "dotnet",
    ["build", "tools/procgen-cli/ProcgenCli.csproj", "-c", "Debug"],
  );
  if (!build.ok) return { ...build, name: "dotnet", passed: 0, failed: 1 };

  const test = runCommand(
    "dotnet",
    "dotnet",
    ["test", "services/backend/Aumbrye.sln", "--no-restore"],
  );
  return {
    name: "dotnet",
    ok: test.ok,
    passed: test.ok ? 1 : 0,
    failed: test.ok ? 0 : 1,
    detail: test.detail,
  };
}

function runContentLayer() {
  const result = runCommand(
    "content",
    "node",
    [join(repoRoot, "scripts/validate-content/validate.mjs"), "--strict-content"],
  );
  return {
    name: "content",
    ok: result.ok,
    passed: result.ok ? 1 : 0,
    failed: result.ok ? 0 : 1,
    detail: result.detail,
  };
}

function runPythonLayer() {
  const ruff = spawnSync("ruff", ["--version"], { encoding: "utf8", shell: true });
  const command = ruff.status === 0 ? "ruff" : process.platform === "win32" ? "python" : "python3";
  const args = ruff.status === 0 ? ["check", "tools/"] : ["-m", "ruff", "check", "tools/"];
  const result = runCommand("python", command, args);
  return {
    name: "python",
    ok: result.ok,
    passed: result.ok ? 1 : 0,
    failed: result.ok ? 0 : 1,
    detail: result.detail,
  };
}

function runBalanceExport() {
  const result = runCommand(
    "balance-export",
    "node",
    [join(repoRoot, "scripts/balance/balance-cli.mjs")],
  );
  return {
    name: "balance-export",
    ok: result.ok,
    passed: result.ok ? 1 : 0,
    failed: result.ok ? 0 : 1,
    detail: result.detail,
  };
}

function runGodotLayer(godotBin) {
  const godot = resolveGodotExecutable(godotBin);
  if (!godot) {
    console.error("Godot not found. Set GODOT_BIN or pass --godot <path>.");
    return { name: "godot", ok: false, passed: 0, failed: 1, detail: "Godot binary not found" };
  }

  // The in-engine validation suites were removed — they had grown to 28,631 lines against a
  // 100k-line client, had never run to completion, and were a larger maintenance surface than the
  // code they covered. The godot layer now runs the smoke test, which boots every autoload and
  // subsystem an exported build needs and returns an exit code.
  const project = join(repoRoot, "apps/game/client");
  const result = runCommand(
    "godot",
    godot,
    ["--path", project, "--headless", "--", "--smoke-test"],
  );

  return {
    name: "godot",
    ok: result.ok,
    passed: result.ok ? 1 : 0,
    failed: result.ok ? 0 : 1,
    detail: result.ok ? "smoke test passed" : result.detail,
  };
}

const { layers, godotBin } = parseArgs(process.argv);
if (!existsSync(reportsDir)) mkdirSync(reportsDir, { recursive: true });

const layerResults = [];
let totalPassed = 0;
let totalFailed = 0;
let anyFailed = false;

for (const layer of layers) {
  if (!ALL_LAYERS.includes(layer)) {
    console.error(`Unknown layer: ${layer}. Valid: ${ALL_LAYERS.join(", ")}`);
    process.exit(1);
  }

  let result;
  switch (layer) {
    case "dotnet":
      result = runDotnetLayer();
      break;
    case "content":
      result = runContentLayer();
      break;
    case "python":
      result = runPythonLayer();
      break;
    case "godot":
      const balanceExport = runBalanceExport();
      layerResults.push(balanceExport);
      totalPassed += balanceExport.passed ?? 0;
      totalFailed += balanceExport.failed ?? 0;
      if (!balanceExport.ok) anyFailed = true;
      result = runGodotLayer(godotBin);
      break;
    default:
      continue;
  }

  layerResults.push(result);
  totalPassed += result.passed ?? 0;
  totalFailed += result.failed ?? 0;
  if (!result.ok) anyFailed = true;
}

const summary = {
  schemaVersion: 1,
  generatedAt: new Date().toISOString(),
  passed: totalPassed,
  failed: totalFailed,
  layers: layerResults.map(({ name, ok, passed, failed, detail, report }) => ({
    name,
    ok,
    passed,
    failed,
    detail,
    report,
  })),
  summaryPath,
};

writeFileSync(summaryPath, `${JSON.stringify(summary, null, 2)}\n`, "utf8");

console.log("\n== Validation summary ==");
console.log(`Report: ${summaryPath}`);
for (const layer of layerResults) {
  const mark = layer.ok ? "[OK]" : "[FAIL]";
  if (layer.passed > 0 || layer.failed > 0) {
    console.log(`${mark} ${layer.name}: passed=${layer.passed} failed=${layer.failed}`);
  } else {
    console.log(`${mark} ${layer.name}: ${layer.detail}`);
  }
}

process.exit(anyFailed ? 1 : 0);
