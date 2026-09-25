#!/usr/bin/env node
// Compatibility entry point. The Python renderer is the sole source and publisher for this
// illustrated atlas; keep one implementation behind the legacy Node command.
import { spawnSync } from "node:child_process";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const python = spawnSync(
  "python3",
  [resolve(root, "tools/generate_class_icons.py"), ...process.argv.slice(2)],
  { cwd: root, stdio: "inherit" },
);
if (python.error) throw python.error;
process.exit(python.status ?? 1);
