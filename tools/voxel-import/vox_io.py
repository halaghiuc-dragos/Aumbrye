"""MagicaVoxel .vox read/write for character parts."""

from __future__ import annotations

import struct
from dataclasses import dataclass, field
from pathlib import Path

from palette import RGB, snap_colour


@dataclass
class VoxelModel:
    size: tuple[int, int, int] = (1, 1, 1)
    voxels: dict[tuple[int, int, int], int] = field(default_factory=dict)
    palette: list[RGB] = field(default_factory=lambda: [(0.0, 0.0, 0.0)] * 256)

    def set_voxel(self, x: int, y: int, z: int, colour_index: int) -> None:
        if colour_index <= 0:
            self.voxels.pop((x, y, z), None)
            return
        self.voxels[(x, y, z)] = colour_index

    def fill_box(
        self,
        origin: tuple[int, int, int],
        size: tuple[int, int, int],
        colour_index: int,
    ) -> None:
        ox, oy, oz = origin
        sx, sy, sz = size
        for x in range(ox, ox + sx):
            for y in range(oy, oy + sy):
                for z in range(oz, oz + sz):
                    self.set_voxel(x, y, z, colour_index)

    def bounds(self) -> tuple[tuple[int, int, int], tuple[int, int, int]]:
        if not self.voxels:
            return (0, 0, 0), (0, 0, 0)
        xs = [p[0] for p in self.voxels]
        ys = [p[1] for p in self.voxels]
        zs = [p[2] for p in self.voxels]
        return (min(xs), min(ys), min(zs)), (max(xs) + 1, max(ys) + 1, max(zs) + 1)


def _read_chunk(stream) -> tuple[str, bytes]:
    chunk_id = stream.read(4).decode("ascii")
    _content_size = struct.unpack("<I", stream.read(4))[0]
    children_size = struct.unpack("<I", stream.read(4))[0]
    data = stream.read(children_size)
    return chunk_id, data


def read_vox(path: Path) -> VoxelModel:
    data = path.read_bytes()
    if data[:4] != b"VOX ":
        raise ValueError(f"not a vox file: {path}")
    _version = struct.unpack("<I", data[4:8])[0]
    model = VoxelModel()
    stream = __import__("io").BytesIO(data[8:])
    chunk_id, chunk_data = _read_chunk(stream)
    if chunk_id != "MAIN":
        raise ValueError("expected MAIN chunk")
    inner = __import__("io").BytesIO(chunk_data)
    while inner.tell() < len(chunk_data):
        sub_id, sub_data = _read_chunk(inner)
        if sub_id == "SIZE":
            sx, sy, sz = struct.unpack("<III", sub_data[:12])
            model.size = (sx, sy, sz)
        elif sub_id == "XYZI":
            count = struct.unpack("<I", sub_data[:4])[0]
            offset = 4
            for _ in range(count):
                x, y, z, ci = struct.unpack("<BBBB", sub_data[offset : offset + 4])
                model.set_voxel(x, y, z, ci)
                offset += 4
        elif sub_id == "RGBA":
            colours: list[RGB] = []
            for i in range(256):
                r, g, b, _a = struct.unpack("<BBBB", sub_data[i * 4 : i * 4 + 4])
                colours.append((r / 255.0, g / 255.0, b / 255.0))
            model.palette = colours
    return model


def write_vox(path: Path, model: VoxelModel) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    (min_b, max_b) = model.bounds()
    size = (
        max(model.size[0], max_b[0] - min_b[0]),
        max(model.size[1], max_b[1] - min_b[1]),
        max(model.size[2], max_b[2] - min_b[2]),
    )
    xyzi = bytearray()
    xyzi.extend(struct.pack("<I", len(model.voxels)))
    for (x, y, z), ci in sorted(model.voxels.items()):
        xyzi.extend(struct.pack("<BBBB", x & 0xFF, y & 0xFF, z & 0xFF, ci & 0xFF))
    rgba = bytearray()
    palette = model.palette
    for i in range(256):
        if i < len(palette):
            r, g, b = palette[i]
            rgba.extend(
                (
                    int(round(r * 255)),
                    int(round(g * 255)),
                    int(round(b * 255)),
                    255 if i > 0 else 0,
                )
            )
        else:
            rgba.extend((0, 0, 0, 0))
    size_chunk = struct.pack("<III", *size)
    main_children = (
        _pack_chunk("SIZE", size_chunk)
        + _pack_chunk("XYZI", bytes(xyzi))
        + _pack_chunk("RGBA", bytes(rgba))
    )
    main = _pack_chunk("MAIN", main_children)
    path.write_bytes(b"VOX " + struct.pack("<I", 150) + main)


def _pack_chunk(chunk_id: str, payload: bytes) -> bytes:
    return (
        chunk_id.encode("ascii")
        + struct.pack("<I", 0)
        + struct.pack("<I", len(payload))
        + payload
    )


def build_box_model(
    size: tuple[int, int, int],
    body_colour: RGB,
    accent_colour: RGB | None = None,
) -> VoxelModel:
    """Box with origin at top-centre of the top face (joint convention)."""
    sx, sy, sz = size
    model = VoxelModel(size=(sx, sy, sz))
    body = snap_colour(body_colour)
    accent = snap_colour(accent_colour) if accent_colour else body
    model.palette[1] = body
    model.palette[2] = accent
    ox = -sx // 2
    oy = -sy
    oz = -sz // 2
    model.fill_box((ox, oy, oz), size, 1)
    if accent_colour and sy >= 4:
        model.fill_box((ox, oy + sy - 2, oz), (sx, 2, sz), 2)
    return model
