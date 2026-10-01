"""Build every prop .glb with Blender.

    Blender/blender -b -P tools/blender/build_props.py [-- --only chest]
"""

from __future__ import annotations

import importlib
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)

import bl_lib  # noqa: E402

OUT = os.path.join(ROOT, "apps", "game", "client", "assets", "props")
MODULES = ["props_interactables", "props_biome", "props_dressing", "props_landmarks", "props_portals", "props_hub_tents", "props_hub_plaza", "props_walls", "props_masonry", "props_misc", "props_waves", "props_nature", "props_fx", "props_fauna", "props_skyline", "props_terrain", "props_crowd"]


def main():
    only = sys.argv[sys.argv.index("--only") + 1] if "--only" in sys.argv else ""
    for name in MODULES:
        module = importlib.import_module(name)
        for prop_id, build in module.BUILDERS.items():
            if only and prop_id != only:
                continue
            bl_lib.reset_scene()
            entries = build()
            objects = [entry[1].finish(entry[2]) for entry in entries]
            by_name = {entry[0]: obj for entry, obj in zip(entries, objects)}
            for entry, obj in zip(entries, objects):
                obj.name = entry[0]
                if len(entry) > 3:
                    parent = by_name[entry[3]]
                    obj.parent = parent
                    obj.location = tuple(a - b for a, b in zip(obj.location, parent.location))
            bl_lib.export_glb_multi(objects, os.path.join(OUT, f"{prop_id}.glb"))
            print("built", prop_id)


if __name__ == "__main__":
    main()
