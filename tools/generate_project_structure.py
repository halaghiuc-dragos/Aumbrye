#!/usr/bin/env python3
"""Emit project_structure.json — a measured inventory of the repository.

This replaces the hand-written audit documents that used to sit at the repo root and went stale
the moment anything was fixed. Everything here is counted from disk at run time, so the file is
regenerated rather than maintained:

    python3 tools/generate_project_structure.py
"""

from __future__ import annotations

import json
import re
import subprocess
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CLIENT = ROOT / "apps" / "game" / "client"

# Directories that hold build output, caches or vendored code — never part of the inventory.
PRUNE = {
    ".git", ".godot", "node_modules", "bin", "obj", "dist", "build",
    "__pycache__", ".pytest_cache", ".ruff_cache", ".venv", "addons",
}


def _walk(base: Path):
    for p in base.rglob("*"):
        if any(part in PRUNE for part in p.relative_to(ROOT).parts):
            continue
        if p.is_file():
            yield p


def _count(base: Path, suffix: str) -> int:
    return sum(1 for p in _walk(base) if p.name.endswith(suffix))


def _lines(base: Path, suffix: str) -> int:
    total = 0
    for p in _walk(base):
        if p.name.endswith(suffix):
            try:
                total += p.read_text(errors="replace").count("\n")
            except OSError:
                pass
    return total


def _tree(base: Path, depth: int, level: int = 0) -> dict:
    """Immediate subdirectories with their file counts, to `depth` levels."""
    out: dict = {}
    if not base.is_dir() or level >= depth:
        return out
    for child in sorted(base.iterdir()):
        if not child.is_dir() or child.name in PRUNE:
            continue
        files = sum(1 for _ in _walk(child))
        if files == 0:
            continue
        entry: dict = {"files": files}
        nested = _tree(child, depth, level + 1)
        if nested:
            entry["children"] = nested
        out[child.name] = entry
    return out


def _godot_project() -> dict:
    cfg = (CLIENT / "project.godot").read_text(errors="replace")

    def setting(key: str) -> str:
        m = re.search(rf'^{re.escape(key)}="?([^"\n]+)"?$', cfg, re.M)
        return m.group(1) if m else ""

    autoloads = re.findall(r'^([A-Za-z_][A-Za-z0-9_]*)="\*?(res://[^"]+)"$',
                           cfg.split("[autoload]", 1)[-1].split("\n[", 1)[0], re.M)
    return {
        "name": setting("config/name"),
        "version": setting("config/version"),
        "mainScene": setting("run/main_scene"),
        "featureTags": re.findall(r'"([^"]+)"', setting("config/features")),
        "autoloads": {name: path for name, path in autoloads},
        "autoloadCount": len(autoloads),
        "translations": re.findall(r'(res://translations/[^"]+)', cfg),
    }


def _validation_suites() -> dict:
    """Headless verification entry points.

    The in-engine suite tree (``scripts/validation/``, 58 suites) was removed — it had grown larger
    than the code it covered and had never run to completion. What replaced it is the smoke test,
    which boots every autoload and subsystem an exported build needs and returns an exit code, plus
    the seed-health sweep. Both run in CI.
    """
    suites = sorted((CLIENT / "scripts" / "validation" / "suites").glob("*.gd"))
    return {
        "count": len(suites),
        "lines": sum(p.read_text(errors="replace").count("\n") for p in suites),
        "entryPoints": {
            "smokeTest": "godot --path apps/game/client --headless -- --smoke-test",
            "seedHealth": "godot --path apps/game/client --headless --script "
                          "res://scripts/tools/procgen_seed_health.gd",
        },
        "names": [p.stem for p in suites],
    }


def _content() -> dict:
    content = ROOT / "content"
    by_dir: dict[str, int] = {}
    for p in _walk(content):
        if p.suffix == ".json":
            by_dir[p.relative_to(content).parts[0]] = by_dir.get(p.relative_to(content).parts[0], 0) + 1
    schemas = sorted(p.name for p in (content / "schemas").glob("*.json"))
    return {
        "jsonFiles": sum(by_dir.values()),
        "byCategory": dict(sorted(by_dir.items())),
        "schemas": schemas,
    }


def _git_head() -> str:
    try:
        return subprocess.run(
            ["git", "-C", str(ROOT), "rev-parse", "--short", "HEAD"],
            capture_output=True, text=True, check=True, timeout=10,
        ).stdout.strip()
    except (subprocess.SubprocessError, OSError):
        return ""


def build() -> dict:
    return {
        "schemaVersion": 1,
        "generatedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "generatedBy": "tools/generate_project_structure.py",
        "gitHead": _git_head(),
        "stacks": {
            "gameClient": {
                "path": "apps/game/client",
                "engine": "Godot 4.7",
                "language": "GDScript",
                "scripts": _count(CLIENT / "scripts", ".gd") + _count(CLIENT / "scenes", ".gd"),
                "scriptLines": _lines(CLIENT / "scripts", ".gd") + _lines(CLIENT / "scenes", ".gd"),
                "scenes": _count(CLIENT / "scenes", ".tscn"),
                "shaders": _count(CLIENT, ".gdshader"),
                "bakedMeshes": _count(CLIENT / "assets" / "characters", ".tres"),
                "voxelSources": _count(CLIENT / "assets" / "characters", ".voxels.json"),
                "project": _godot_project(),
                "validation": _validation_suites(),
            },
            "backend": {
                "path": "services/backend",
                "language": "C#",
                "sourceFiles": _count(ROOT / "services" / "backend", ".cs"),
                "sourceLines": _lines(ROOT / "services" / "backend", ".cs"),
                "projects": sorted(p.stem for p in (ROOT / "services" / "backend").rglob("*.csproj")),
            },
            "sharedPackages": {
                "path": "packages",
                "sourceFiles": _count(ROOT / "packages", ".cs"),
                "sourceLines": _lines(ROOT / "packages", ".cs"),
                "projects": sorted(p.stem for p in (ROOT / "packages").rglob("*.csproj")),
            },
            "web": {
                "path": "apps/web",
                "language": "TypeScript",
                "sourceFiles": _count(ROOT / "apps" / "web", ".ts") + _count(ROOT / "apps" / "web", ".tsx"),
                "sourceLines": _lines(ROOT / "apps" / "web", ".ts") + _lines(ROOT / "apps" / "web", ".tsx"),
            },
            "tooling": {
                "path": "tools",
                "python": _count(ROOT / "tools", ".py") + _count(ROOT / "scripts", ".py"),
                "node": _count(ROOT / "tools", ".mjs") + _count(ROOT / "scripts", ".mjs"),
            },
        },
        "content": _content(),
        "artSource": {
            "path": "art-source",
            "voxFiles": _count(ROOT / "art-source", ".vox"),
        },
        "docs": sorted(
            str(p.relative_to(ROOT)) for p in _walk(ROOT / "docs") if p.suffix == ".md"
        ),
        "directoryTree": _tree(ROOT, depth=2),
    }


def main() -> int:
    out = ROOT / "project_structure.json"
    out.write_text(json.dumps(build(), indent=2) + "\n", encoding="utf-8")
    print(f"wrote {out.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
