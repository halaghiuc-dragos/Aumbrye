"""Item icon silhouettes, one 16 x 16 glyph per shape.

The glyphs are not drawn by hand: each shape is a small 3D model in tools/blender/icons.py, and
`Blender/blender -b -P tools/blender/build_icons.py` rasterises it (lit from the upper left, fitted to
a twelve pixel box, ringed in an outline) into glyphs.json. This module only exposes those rows under
the names the atlas builder uses.
"""

from __future__ import annotations

import json
from pathlib import Path

_GLYPHS: dict[str, list[str]] = json.loads(Path(__file__).with_name("glyphs.json").read_text(encoding="utf-8"))

globals().update({name.upper(): rows for name, rows in _GLYPHS.items()})
