"""One-shot generator for apps/game/client/assets/ui/fonts/aumbrye_pixel.ttf."""
from __future__ import annotations

import os
from pathlib import Path

from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "ui" / "fonts" / "aumbrye_pixel.ttf"


def main() -> None:
    fb = FontBuilder(1024, isTTF=True)
    glyphs = [".notdef", "space", "A"]
    fb.setupGlyphOrder(glyphs)
    glyf: dict = {}
    pen = TTGlyphPen(None)
    pen.moveTo((0, 0))
    pen.lineTo((0, 0))
    pen.closePath()
    glyf[".notdef"] = pen.glyph()
    pen = TTGlyphPen(None)
    pen.moveTo((0, 0))
    pen.lineTo((200, 0))
    pen.lineTo((200, 800))
    pen.lineTo((0, 800))
    pen.closePath()
    box = pen.glyph()
    glyf["space"] = box
    glyf["A"] = box
    fb.setupGlyf(glyf)
    fb.setupHorizontalMetrics({".notdef": (600, 0), "space": (512, 0), "A": (700, 0)})
    fb.setupHorizontalHeader(ascent=800, descent=-200)
    fb.setupCharacterMap({32: "space", 65: "A"})
    fb.setupOS2(sTypoAscender=800, sTypoDescender=-200, usWinAscent=800, usWinDescent=200)
    fb.setupPost()
    fb.setupNameTable({"familyName": "Aumbrye Pixel", "styleName": "Regular"})
    OUT.parent.mkdir(parents=True, exist_ok=True)
    fb.save(str(OUT))
    print(f"Wrote {OUT} ({OUT.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
