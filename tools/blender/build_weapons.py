"""Build every weapon .glb with Blender.

    Blender/blender -b -P tools/blender/build_weapons.py
"""

from __future__ import annotations

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)

import bl_lib  # noqa: E402
import weapons  # noqa: E402

OUT = os.path.join(ROOT, "apps", "game", "client", "assets", "weapons")


def main():
    for kit_id, build in weapons.BUILDERS.items():
        bl_lib.reset_scene()
        bl_lib.export_glb(build().finish(), os.path.join(OUT, f"{kit_id}.glb"))
        print("built", kit_id)


if __name__ == "__main__":
    main()
