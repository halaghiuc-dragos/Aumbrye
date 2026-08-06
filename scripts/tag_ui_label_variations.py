#!/usr/bin/env python3
"""Add theme_type_variation to Label nodes in scenes/ui/*.tscn."""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
UI_SCENES = ROOT / "apps" / "game" / "client" / "scenes" / "ui"

MENU_TITLE = {"Title", "TitleLabel", "SeedTitle"}
HINT = {"HintLabel", "SeedHintLabel", "Hint"}
STAT = {
    "TimeLabel",
    "KillsLabel",
    "LootLabel",
    "XpLabel",
    "GoldLabel",
    "LevelLabel",
}
SECTION = {"SeedTitle"}  # handled as MenuTitle above — SeedTitle is menu title style


def variation_for(node_name: str) -> str:
    if node_name in MENU_TITLE:
        return "MenuTitle"
    if node_name in HINT:
        return "HintText"
    if node_name in STAT:
        return "StatValue"
    lower = node_name.lower()
    if "title" in lower and node_name not in {"SeedTitle"}:
        return "SectionTitle"
    if "hint" in lower:
        return "HintText"
    return "BodyText"


def process_file(path: Path) -> int:
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines()
    out: list[str] = []
    changed = 0
    i = 0
    while i < len(lines):
        line = lines[i]
        m = re.match(r"\[node name=\"([^\"]+)\" type=\"Label\"", line)
        if m:
            name = m.group(1)
            variation = variation_for(name)
            out.append(line)
            i += 1
            block: list[str] = []
            has_variation = False
            while i < len(lines) and not lines[i].startswith("[node "):
                if lines[i].strip().startswith("theme_type_variation"):
                    has_variation = True
                    block.append(f'theme_type_variation = "{variation}"')
                elif lines[i].strip().startswith("theme_override_font_sizes"):
                    pass  # drop manual sizes — theme owns sizing
                else:
                    block.append(lines[i])
                i += 1
            if not has_variation:
                if block and block[0].strip() != "":
                    block.insert(0, f'theme_type_variation = "{variation}"')
                else:
                    block = [f'theme_type_variation = "{variation}"'] + block
                changed += 1
            out.extend(block)
            continue
        out.append(line)
        i += 1
    if changed:
        path.write_text("\n".join(out) + ("\n" if text.endswith("\n") else ""), encoding="utf-8")
    return changed


def main() -> None:
    total = 0
    for path in sorted(UI_SCENES.glob("*.tscn")):
        n = process_file(path)
        if n:
            print(f"{path.name}: {n} labels tagged")
            total += n
    print(f"updated {total} labels")


if __name__ == "__main__":
    main()
