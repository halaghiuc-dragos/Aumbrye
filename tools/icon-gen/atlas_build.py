#!/usr/bin/env python3
"""Build every generated UI icon sheet from one set of drawing rules.

The sheets used to come from four scripts that disagreed with each other, and the disagreement was
visible in play:

  * the top sixteen rows of the item atlas had no keyline and thin one-pixel features, while
    everything from row sixteen down was drawn with a hard outline and a five-tone ramp -- so one
    inventory grid showed two different art styles side by side;
  * rows seven to fourteen of that atlas were empty, wasting a third of the texture;
  * the colourblind status sheet was five flat blobs and five empty cells, so half the statuses
    showed nothing at all in colourblind mode;
  * the minimap sheet was sixteen solid colour squares with no glyph on any of them.

Everything is now drawn to the rule the item shapes were already written to: a hard dark outline
the whole way round, flat tones inside, highlight up and to the left, one pixel of margin.

Usage:
    python tools/icon-gen/atlas_build.py            # write the sheets and manifests
    python tools/icon-gen/atlas_build.py --check    # verify what is on disk, write nothing
    python tools/icon-gen/atlas_build.py --report   # per-cell alignment report
"""

from __future__ import annotations

import argparse
import glob
import io
import json
import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))

import curated  # noqa: E402
import item_icons as items_mod  # noqa: E402
import minimap_icons as minimap_mod  # noqa: E402
import pixel  # noqa: E402
import status_icons as status_mod  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / "apps" / "game" / "client" / "assets" / "ui"
CONTENT_UI = ROOT / "content" / "ui"

CELL = 16
ITEM_COLUMNS = 16

# --------------------------------------------------------------------------------- item atlas

#: A flat, desaturated ramp for the empty-equipment-slot hints, so a slot silhouette reads as a
#: socket waiting to be filled rather than as an item already in the bag.
SLOT_RAMP = (
    (0x15, 0x15, 0x1B), (0x24, 0x25, 0x2D), (0x31, 0x33, 0x3D),
    (0x3F, 0x42, 0x4E), (0x4E, 0x52, 0x60),
    (0x22, 0x20, 0x1C), (0x30, 0x2C, 0x25), (0x3E, 0x39, 0x2F),
)

#: Keys the item content tree does not produce: relics, run buffs, the fallback marker.
EXTRA_CELLS: dict[str, tuple[str, str]] = {
    "relic_bloodstone": ("gem", "elixir"),
    "relic_flame_core": ("gem", "vault"),
    "relic_frost_shard": ("shard", "frozen"),
    "relic_poison_vial": ("flask", "swamp"),
    "relic_shadow_veil": ("amulet", "umbral"),
    "relic_stone_heart": ("runestone", "iron"),
    "relic_sun_medallion": ("amulet", "gold"),
    "relic_wind_charm": ("amulet", "crystal"),
    "bloodlust": ("flask", "elixir"),
    "iron_will": ("runestone", "iron"),
    "swift_step": ("boot", "swamp"),
}

SLOT_CELLS = dict(items_mod.SLOT_SHAPE)
SLOT_CELLS["relic"] = "gem"

#: Sheet order, so the atlas is readable opened in an image editor and a regenerated diff stays
#: local to the group that actually changed.
GROUP_ORDER = ["weapon", "armor", "accessory", "consumable", "material", "relic", "slot"]


def load_items() -> list[dict]:
    out = []
    for path in sorted(glob.glob(str(ROOT / "content" / "items" / "**" / "*.json"), recursive=True)):
        if path.endswith("catalog.json"):
            continue
        data = json.load(open(path))
        if data.get("id"):
            out.append(data)
    return out


def item_cells() -> list[tuple[str, str, str, str]]:
    """(key, group, shape, ramp) for every cell the item atlas must carry."""
    cells: list[tuple[str, str, str, str]] = []
    for item in load_items():
        key = str(item["id"])
        group = str(item.get("itemType", "material"))
        if group not in GROUP_ORDER:
            group = "material"
        shape, ramp = curated.CURATED.get(
            key, (items_mod.shape_for(item), items_mod.ramp_for(item))
        )
        cells.append((key, group, shape, ramp))
    for key, fallback in EXTRA_CELLS.items():
        group = "relic" if key.startswith("relic_") else "consumable"
        shape, ramp = curated.CURATED.get(key, fallback)
        cells.append((key, group, shape, ramp))
    for slot, shape in SLOT_CELLS.items():
        cells.append(("slot/%s" % slot, "slot", shape, "@slot"))
    cells.sort(key=lambda c: (GROUP_ORDER.index(c[1]), c[2], c[0]))
    return cells


def build_item_atlas() -> tuple[Image.Image, dict]:
    cells = item_cells()
    rows = (len(cells) + ITEM_COLUMNS - 1) // ITEM_COLUMNS
    img = Image.new("RGBA", (ITEM_COLUMNS * CELL, rows * CELL), (0, 0, 0, 0))
    px = img.load()

    # Position within the shape+ramp family, so siblings are spread across the trim variants by
    # construction rather than by whatever the id hash happened to pick.
    family_ordinal: dict[str, int] = {}
    family_counts: dict[tuple[str, str], int] = {}
    for key, _group, shape_name, ramp_name in cells:
        family = (shape_name, ramp_name)
        family_ordinal[key] = family_counts.get(family, 0)
        family_counts[family] = family_ordinal[key] + 1

    mapping: dict[str, dict] = {}
    for index, (key, _group, shape_name, ramp_name) in enumerate(cells):
        col, row = index % ITEM_COLUMNS, index // ITEM_COLUMNS
        glyph = items_mod.SHAPES[shape_name]
        ramp = SLOT_RAMP if ramp_name == "@slot" else items_mod.RAMPS[ramp_name]
        # Trim varied per item, so two items of the same kind and material are still telling the
        # player apart. The empty-slot hints keep the flat ramp -- they are one thing, not a family.
        if ramp_name != "@slot":
            ramp = pixel.accent_variant(ramp, key, glyph, family_ordinal[key])
        pixel.validate(key, glyph, CELL)
        pixel.blit(px, glyph, ramp, col, row, CELL)
        mapping[key] = {"col": col, "row": row}

    # No two items may share an icon.
    #
    # Shape says what kind of thing an item is and the ramp says what it is made of, which between
    # them only describe a family: at one point 195 of 284 items were pixel-for-pixel identical to
    # something else, so a loot list showed the same picture for the sword you are holding and the
    # one you just picked up. Trim varies per item to break that, and this is what keeps it broken.
    by_pixels: dict[bytes, list[str]] = {}
    for key, cell in mapping.items():
        if key.startswith("slot/"):
            continue
        box = (cell["col"] * CELL, cell["row"] * CELL,
               cell["col"] * CELL + CELL, cell["row"] * CELL + CELL)
        by_pixels.setdefault(img.crop(box).tobytes(), []).append(key)
    collisions = [names for names in by_pixels.values() if len(names) > 1]
    if collisions:
        raise SystemExit(
            "items sharing an icon: %s"
            % "; ".join(", ".join(sorted(names)) for names in collisions)
        )

    # There is no "?" cell and no fallback marker. Every item in the content tree is drawn, and
    # this is what keeps it that way: an item added without an icon fails the build here rather
    # than shipping a placeholder for a player to find.
    missing = sorted(str(item["id"]) for item in load_items() if str(item["id"]) not in mapping)
    if missing:
        raise SystemExit(
            "no icon for %d item(s): %s" % (len(missing), ", ".join(missing))
        )

    manifest = {
        "schemaVersion": 1,
        "texture": "res://assets/ui/item_icons.png",
        "cellSize": CELL,
        "columns": ITEM_COLUMNS,
        "rows": rows,
        "cells": dict(sorted(mapping.items())),
    }
    return img, manifest


# ------------------------------------------------------------------------------- status atlas

STATUS_COLUMNS = 4
STATUS_ORDER = [
    "burn", "poison", "freeze", "bleed",
    "stun", "torpor", "focus", "resolve",
    "stoneskin", "swiftness", "frame_buff", "frame_debuff",
]

#: Colourblind sheet ramps. The shapes already differ status to status; what fails under red-green
#: deficiency is that burn/bleed/poison sit on one confusable hue arc. These pull every status onto
#: the blue-yellow axis plus lightness, which survives all three common deficiencies.
CB_RAMPS = {
    "burn": (
        (0x2c, 0x1c, 0x00), (0x6b, 0x45, 0x00), (0xa8, 0x6e, 0x00),
        (0xdd, 0x9d, 0x1c), (0xff, 0xd9, 0x7a),
    ),
    "poison": (
        (0x00, 0x22, 0x2c), (0x00, 0x50, 0x63), (0x00, 0x7e, 0x99),
        (0x2f, 0xaa, 0xc6), (0x92, 0xdd, 0xef),
    ),
    "freeze": (
        (0x12, 0x1e, 0x3a), (0x27, 0x3f, 0x77), (0x42, 0x66, 0xb4),
        (0x7b, 0x9b, 0xdc), (0xd2, 0xe1, 0xff),
    ),
    "bleed": (
        (0x2a, 0x0f, 0x1f), (0x5f, 0x28, 0x46), (0x92, 0x44, 0x6d),
        (0xc2, 0x74, 0x9a), (0xf0, 0xbc, 0xd2),
    ),
    "stun": (
        (0x33, 0x2c, 0x00), (0x77, 0x68, 0x00), (0xb4, 0xa0, 0x00),
        (0xe2, 0xd0, 0x30), (0xff, 0xf5, 0x9e),
    ),
    "torpor": (
        (0x1a, 0x14, 0x26), (0x38, 0x2d, 0x52), (0x5b, 0x4c, 0x82),
        (0x8b, 0x7d, 0xb2), (0xc8, 0xc0, 0xe0),
    ),
    "focus": (
        (0x10, 0x24, 0x30), (0x22, 0x4d, 0x66), (0x38, 0x7c, 0xa2),
        (0x6f, 0xae, 0xcd), (0xc2, 0xe6, 0xf7),
    ),
    "resolve": (
        (0x2e, 0x26, 0x08), (0x6c, 0x5a, 0x14), (0xa4, 0x8c, 0x22),
        (0xd4, 0xbd, 0x4a), (0xff, 0xef, 0xae),
    ),
    "stoneskin": (
        (0x1b, 0x1d, 0x21), (0x3d, 0x42, 0x49), (0x64, 0x6b, 0x75),
        (0x93, 0x9c, 0xa7), (0xcf, 0xd6, 0xde),
    ),
    "swiftness": (
        (0x14, 0x28, 0x2e), (0x2c, 0x57, 0x63), (0x4a, 0x88, 0x99),
        (0x82, 0xba, 0xc9), (0xd0, 0xed, 0xf5),
    ),
    "frame_buff": (
        (0x33, 0x2c, 0x00), (0x77, 0x68, 0x00), (0xb4, 0xa0, 0x00),
        (0xe2, 0xd0, 0x30), (0xff, 0xf5, 0x9e),
    ),
    "frame_debuff": (
        (0x12, 0x1e, 0x3a), (0x27, 0x3f, 0x77), (0x42, 0x66, 0xb4),
        (0x7b, 0x9b, 0xdc), (0xd2, 0xe1, 0xff),
    ),
}


def _stoneskin_glyph() -> list[str]:
    """A hexagonal plate of stone.

    The old shape split the cell on a diagonal with light on one side and dark on the other, which
    at sixteen pixels read as a grey smear rather than as armour.
    """
    spans = [
        (2, 6, 9), (3, 4, 11), (4, 3, 12), (5, 2, 13), (6, 2, 13), (7, 2, 13),
        (8, 2, 13), (9, 2, 13), (10, 3, 12), (11, 4, 11), (12, 5, 10), (13, 7, 8),
    ]
    return pixel.shade(pixel.mask_from_spans(spans, CELL), CELL)


def status_cells() -> dict[str, list[str]]:
    glyphs = {name: rows for name, (rows, _ramp, _at) in status_mod.ICONS.items()}
    glyphs["stoneskin"] = _stoneskin_glyph()
    return glyphs


def build_status_atlas(colorblind: bool) -> tuple[Image.Image, dict]:
    glyphs = status_cells()
    rows = (len(STATUS_ORDER) + STATUS_COLUMNS - 1) // STATUS_COLUMNS
    img = Image.new("RGBA", (STATUS_COLUMNS * CELL, rows * CELL), (0, 0, 0, 0))
    px = img.load()

    mapping: dict[str, dict] = {}
    for index, name in enumerate(STATUS_ORDER):
        col, row = index % STATUS_COLUMNS, index // STATUS_COLUMNS
        glyph = glyphs[name]
        ramp = (
            CB_RAMPS[name] if colorblind
            else status_mod.RAMPS[status_mod.ICONS[name][1]]
        )
        pixel.validate(name, glyph, CELL)
        # The polarity frame is a corner bracket drawn at the edge of the same cell, behind the
        # glyph. A status that runs to the edge clips it, and the pip stops reading as a buff or a
        # debuff -- so every status keeps a pixel clear. The frames themselves are the edge.
        if not name.startswith("frame") and min(pixel.margins(glyph, CELL)) < 1:
            raise SystemExit(
                "status '%s' touches the cell edge and would clip the polarity frame" % name
            )
        pixel.blit(px, glyph, ramp, col, row, CELL)
        mapping[name] = {"col": col, "row": row}

    manifest = {
        "schemaVersion": 1,
        "texture": "res://assets/ui/status_icons.png",
        "cellSize": CELL,
        "columns": STATUS_COLUMNS,
        "rows": rows,
        "cells": dict(sorted(mapping.items())),
    }
    return img, manifest


# ------------------------------------------------------------------------------ minimap sheet


def build_minimap_atlas() -> Image.Image:
    cell = minimap_mod.CELL
    cols, rows = minimap_mod.COLUMNS, minimap_mod.ROWS
    img = Image.new("RGBA", (cols * cell, rows * cell), (0, 0, 0, 0))
    px = img.load()
    for name, (glyph, ramp_name, (col, row)) in minimap_mod.ICONS.items():
        pixel.validate(name, glyph, cell)
        pixel.blit(px, glyph, minimap_mod.RAMPS[ramp_name], col, row, cell)
    return img


# ------------------------------------------------------------------------------------ plumbing


def _png_bytes(img: Image.Image) -> bytes:
    buf = io.BytesIO()
    img.save(buf, "PNG")
    return buf.getvalue()


TARGETS = []


def collect() -> list[tuple[Path, bytes]]:
    item_img, item_manifest = build_item_atlas()
    status_img, status_manifest = build_status_atlas(colorblind=False)
    cb_img, _ = build_status_atlas(colorblind=True)
    out = [
        (ASSETS / "item_icons.png", _png_bytes(item_img)),
        (ASSETS / "status_icons.png", _png_bytes(status_img)),
        (ASSETS / "status_icons_cb.png", _png_bytes(cb_img)),
        (ASSETS / "minimap_icons.png", _png_bytes(build_minimap_atlas())),
        (
            CONTENT_UI / "item_icon_atlas.json",
            (json.dumps(item_manifest, indent=2) + "\n").encode(),
        ),
        (
            CONTENT_UI / "status_icon_atlas.json",
            (json.dumps(status_manifest, indent=2) + "\n").encode(),
        ),
    ]
    return out


def report() -> None:
    print("item atlas")
    for key, _group, shape_name, _ramp in item_cells():
        glyph = items_mod.SHAPES[shape_name]
        left, top, right, bottom = pixel.margins(glyph, CELL)
        # Blades and hafts are drawn to the full height of the cell on purpose -- that is what
        # makes a sword read as a sword at sixteen pixels. Touching a side is the real fault:
        # neighbouring cells then run together in the inventory grid.
        flag = "  <-- touches a side edge" if min(left, right) == 0 else ""
        print("  %-28s %-12s margins l%d t%d r%d b%d%s"
              % (key, shape_name, left, top, right, bottom, flag))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="verify only, write nothing")
    parser.add_argument("--report", action="store_true", help="print the alignment report")
    args = parser.parse_args()

    if args.report:
        report()
        return

    stale = []
    for path, data in collect():
        if args.check:
            current = path.read_bytes() if path.exists() else b""
            if current != data:
                stale.append(path)
            continue
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        print("wrote %s" % path.relative_to(ROOT))

    if args.check:
        if stale:
            for path in stale:
                print("stale: %s" % path.relative_to(ROOT))
            raise SystemExit(1)
        print("all generated icon sheets are up to date")


if __name__ == "__main__":
    main()
