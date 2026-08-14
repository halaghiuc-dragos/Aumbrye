"""Voxel solid-modelling kit for Aumbrye's character rigs.

Every part of every rig was a solid rectangular prism. The asset format has always carried an
explicit `cells` list and the runtime mesher (`voxel_mesh_builder.gd`) is a proper greedy mesher
that handles arbitrary sparse occupancy — the generator simply filled every cell:

    cells = [[x, y, z] for x in range(sx) for y in range(sy) for z in range(sz)]

So the warden was eight boxes in a trenchcoat. This module is the missing half: a small set of
carving operations that turn a block into a shape.

Design rules, which matter more than the code here:

* **Silhouette first.** The game renders through a low-resolution pixel viewport, so a form is read
  almost entirely from its outline. Interior detail below about two voxels vanishes; a chamfer that
  changes the profile survives.
* **One colour per part.** The mesher merges faces across the whole part and never compares
  per-cell material, so shading has to come from geometry catching the light, not from painting.
  A recess reads as a dark band because it is genuinely in shadow.
* **Chamfers, not curves.** At nine voxels across, a sphere is a lumpy blob. A 45-degree cut is
  crisp, deliberate, and unmistakably voxel — it is the pixel-art line, in three dimensions.
* **Taper carries weight.** Limbs narrowing toward the extremity and a torso narrowing at the waist
  are what separate a figure from a stack of crates, and cost nothing in triangles.
"""

from __future__ import annotations

from typing import Callable, Iterable


class Vox:
    """A voxel volume on an integer grid, built by carving away from a solid block."""

    __slots__ = ("sx", "sy", "sz", "cells")

    def __init__(self, sx: int, sy: int, sz: int, solid: bool = True) -> None:
        self.sx, self.sy, self.sz = int(sx), int(sy), int(sz)
        self.cells: set[tuple[int, int, int]] = set()
        if solid:
            self.fill()

    # --- construction ---------------------------------------------------------------------

    def fill(self) -> "Vox":
        self.cells = {
            (x, y, z)
            for x in range(self.sx)
            for y in range(self.sy)
            for z in range(self.sz)
        }
        return self

    def carve(self, predicate: Callable[[int, int, int], bool]) -> "Vox":
        """Remove every cell for which `predicate(x, y, z)` is true."""
        self.cells = {c for c in self.cells if not predicate(*c)}
        return self

    def add(self, cells: Iterable[tuple[int, int, int]]) -> "Vox":
        for c in cells:
            x, y, z = c
            if 0 <= x < self.sx and 0 <= y < self.sy and 0 <= z < self.sz:
                self.cells.add((x, y, z))
        return self

    # --- shaping --------------------------------------------------------------------------

    def taper(self, profile: Callable[[float], tuple[float, float]]) -> "Vox":
        """Scale the cross-section per layer.

        `profile(t)` takes a height in 0..1 and returns (x_scale, z_scale) in 0..1. Cells outside
        the scaled footprint, measured from the centre, are removed. This is what gives a limb its
        wrist and a torso its waist.
        """
        # Widths are resolved to whole voxels per layer rather than compared against a float
        # half-extent. On a four-voxel arm the float form only ever produced two distinct widths —
        # the taper became a step — because the smoothstep spent nearly all of its range at the
        # ends and the rounding did the rest. Choosing the layer's width directly makes every
        # intermediate width reachable and makes the profile mean exactly what it says.
        keep: set[tuple[int, int, int]] = set()
        for (x, y, z) in self.cells:
            t = y / max(1, self.sy - 1)
            fx, fz = profile(t)
            wx = max(1, int(round(self.sx * fx)))
            wz = max(1, int(round(self.sz * fz)))
            # Keep each layer's parity matching the part's, or the integer centring floors to one
            # side and the whole limb leans a voxel off-axis.
            if (self.sx - wx) % 2:
                wx = min(self.sx, wx + 1)
            if (self.sz - wz) % 2:
                wz = min(self.sz, wz + 1)
            x0 = (self.sx - wx) // 2
            z0 = (self.sz - wz) // 2
            if x0 <= x < x0 + wx and z0 <= z < z0 + wz:
                keep.add((x, y, z))
        self.cells = keep
        return self

    def chamfer_vertical(self, radius: int) -> "Vox":
        """Cut the four vertical edges at 45 degrees — the signature voxel bevel."""
        if radius <= 0:
            return self

        def corner(x: int, y: int, z: int) -> bool:
            dx = min(x, self.sx - 1 - x)
            dz = min(z, self.sz - 1 - z)
            return dx + dz < radius

        return self.carve(corner)

    def chamfer_cap(self, radius: int, top: bool = True) -> "Vox":
        """Bevel the top (or bottom) face's four edges, rounding a shoulder or a helm crown."""
        if radius <= 0:
            return self

        def cap(x: int, y: int, z: int) -> bool:
            dy = (self.sy - 1 - y) if top else y
            if dy >= radius:
                return False
            inset = radius - dy
            dx = min(x, self.sx - 1 - x)
            dz = min(z, self.sz - 1 - z)
            return dx < inset or dz < inset

        return self.carve(cap)

    def recess_band(
        self, y0: int, y1: int, depth: int = 1, faces: str = "xz"
    ) -> "Vox":
        """Sink a horizontal band into the side faces.

        With one flat colour per part, a recess is the only way to draw a line: the sunken face
        catches less light than the surface either side of it, so it reads as a belt, a visor slot
        or a joint seam.
        """

        def band(x: int, y: int, z: int) -> bool:
            if not (y0 <= y <= y1):
                return False
            on_x = x < depth or x >= self.sx - depth
            on_z = z < depth or z >= self.sz - depth
            return ("x" in faces and on_x) or ("z" in faces and on_z)

        return self.carve(band)

    def notch(self, x0: int, y0: int, z0: int, x1: int, y1: int, z1: int) -> "Vox":
        """Remove an axis-aligned block — a neck slot, an armpit, a gap under a pauldron."""

        def inside(x: int, y: int, z: int) -> bool:
            return x0 <= x <= x1 and y0 <= y <= y1 and z0 <= z <= z1

        return self.carve(inside)

    def flare(self, layers: int, amount: int, axis: str = "z") -> "Vox":
        """Widen the bottom few layers outward — a boot, a skirt hem, a plinth."""
        if layers <= 0 or amount <= 0:
            return self
        new: list[tuple[int, int, int]] = []
        for (x, y, z) in list(self.cells):
            if y >= layers:
                continue
            grow = amount if y == 0 else max(1, amount - 1)
            for step in range(1, grow + 1):
                if "z" in axis:
                    new.append((x, y, z + step))
                    new.append((x, y, z - step))
                if "x" in axis:
                    new.append((x + step, y, z))
                    new.append((x - step, y, z))
        return self.add(new)

    # --- output ---------------------------------------------------------------------------

    def normalised_cells(self) -> list[list[int]]:
        """Cells shifted so the volume starts at the origin, sorted for a stable diff."""
        if not self.cells:
            return []
        mx = min(c[0] for c in self.cells)
        my = min(c[1] for c in self.cells)
        mz = min(c[2] for c in self.cells)
        return sorted([[x - mx, y - my, z - mz] for (x, y, z) in self.cells])

    def __len__(self) -> int:
        return len(self.cells)


# --- part profiles ---------------------------------------------------------------------------
#
# Keyed by the role a part plays rather than by its exact name, so every archetype — player,
# brute, hound, the ten biome enemies — picks up the same language of shapes automatically.


def sculpt_torso(sx: int, sy: int, sz: int) -> Vox:
    """Broad at the shoulders, drawn in at the waist, with a chest plate and a belt line."""
    v = Vox(sx, sy, sz)
    # y = 0 is the waist, y = max the shoulders.
    v.taper(lambda t: (0.76 + 0.24 * t, 0.80 + 0.20 * t))
    v.chamfer_vertical(max(1, min(sx, sz) // 5))
    v.chamfer_cap(1, top=True)
    # Belt: a seam low on the body, where a cuirass would end.
    belt = max(1, sy // 8)
    v.recess_band(belt, belt, depth=1)
    # Neck slot, so the head sits into the shoulders instead of balancing on them.
    neck = max(1, sx // 4)
    v.notch(neck, sy - 1, neck, sx - 1 - neck, sy - 1, sz - 1 - neck)
    return v


def sculpt_head(sx: int, sy: int, sz: int) -> Vox:
    """A helm: bevelled crown, recessed visor slot, jaw drawn in at the base."""
    v = Vox(sx, sy, sz)
    v.taper(lambda t: (1.0, 1.0) if t > 0.3 else (0.72 + 0.28 * (t / 0.3), 0.78 + 0.22 * (t / 0.3)))
    v.chamfer_vertical(max(1, min(sx, sz) // 4))
    v.chamfer_cap(max(1, sy // 5), top=True)
    # Visor: a sunken band across the eyes. The single strongest identity cue on a voxel head.
    eye = max(1, int(sy * 0.55))
    v.recess_band(eye, eye, depth=1, faces="z")
    return v


def sculpt_limb(sx: int, sy: int, sz: int, boot: bool = False) -> Vox:
    """Arms and legs: wide where they meet the body, narrow at the extremity.

    y = 0 is the wrist or ankle and y = max the shoulder or hip, because both hang from their
    joint. A boot adds the flare back at the very bottom.
    """
    v = Vox(sx, sy, sz)
    v.taper(lambda t: (0.58 + 0.42 * t, 0.62 + 0.38 * t))
    v.chamfer_vertical(1)
    v.chamfer_cap(1, top=True)
    if boot:
        v.flare(2, 1, axis="xz")
    return v


def sculpt_block(sx: int, sy: int, sz: int) -> Vox:
    """Fallback for pauldrons, trims, weapons and anything else: bevel it, never ship a raw box.

    Parts thinner than three voxels across are left alone. A chamfer needs a corner to cut, and on
    a two-wide bow stave the cap bevel simply deleted the top layer — it shortened the weapon
    instead of shaping it.
    """
    v = Vox(sx, sy, sz)
    if min(sx, sz) < 3:
        return v
    v.chamfer_vertical(1)
    v.chamfer_cap(1, top=True)
    return v


def _ease(t: float) -> float:
    """Smoothstep. Keeps a taper from reading as a straight cone."""
    t = max(0.0, min(1.0, t))
    return t * t * (3.0 - 2.0 * t)


#: Which sculptor a part name maps to. Matched case-insensitively on a prefix so LegL, LegR,
#: LegBL and LegBR (the hound's four) all resolve to the same profile.
PART_PROFILES: tuple[tuple[tuple[str, ...], str], ...] = (
    (("torso", "body", "chest"), "torso"),
    (("head", "skull", "helm"), "head"),
    (("leg",), "leg"),
    (("arm", "claw"), "arm"),
)


def sculpt_for_part(part_name: str, size: tuple[int, int, int]) -> Vox:
    sx, sy, sz = (max(1, int(v)) for v in size)
    key = part_name.lower()
    for prefixes, profile in PART_PROFILES:
        if key.startswith(prefixes):
            if profile == "torso":
                return sculpt_torso(sx, sy, sz)
            if profile == "head":
                return sculpt_head(sx, sy, sz)
            if profile == "leg":
                return sculpt_limb(sx, sy, sz, boot=True)
            return sculpt_limb(sx, sy, sz, boot=False)
    return sculpt_block(sx, sy, sz)
