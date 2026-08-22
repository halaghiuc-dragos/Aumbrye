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
* **Material and silhouette together.** The mesher now compares per-cell material when it merges
  faces, so a part can carry a palette instead of one flat colour. Geometry still does most of
  the work — a recess reads as a dark band because it is genuinely in shadow — but a belt can now
  be leather-coloured *and* sunk, which is what separates armour from a painted crate.
* **Chamfers, not curves.** At nine voxels across, a sphere is a lumpy blob. A 45-degree cut is
  crisp, deliberate, and unmistakably voxel — it is the pixel-art line, in three dimensions.
* **Taper carries weight.** Limbs narrowing toward the extremity and a torso narrowing at the waist
  are what separate a figure from a stack of crates, and cost nothing in triangles.
"""

from __future__ import annotations

from typing import Callable, Iterable


class Vox:
    """A voxel volume on an integer grid, built by carving away from a solid block."""

    __slots__ = ("sx", "sy", "sz", "cells", "materials")

    def __init__(self, sx: int, sy: int, sz: int, solid: bool = True) -> None:
        self.sx, self.sy, self.sz = int(sx), int(sy), int(sz)
        self.cells: set[tuple[int, int, int]] = set()
        #: cell -> index into MATERIALS. Absent means 0, so painting is optional throughout.
        self.materials: dict[tuple[int, int, int], int] = {}
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

    # --- painting -------------------------------------------------------------------------

    def paint_all(self, material: int) -> "Vox":
        for c in self.cells:
            self.materials[c] = material
        return self

    def paint_layers(self, y0: int, y1: int, material: int) -> "Vox":
        """Paint a horizontal band. Bands are how anatomy is expressed, so this is the workhorse."""
        for c in self.cells:
            if y0 <= c[1] <= y1:
                self.materials[c] = material
        return self

    def paint_region(
        self, x0: int, y0: int, z0: int, x1: int, y1: int, z1: int, material: int
    ) -> "Vox":
        """Paint an axis-aligned box — a chest placard, a visor slot, a strap."""
        for c in self.cells:
            x, y, z = c
            if x0 <= x <= x1 and y0 <= y <= y1 and z0 <= z <= z1:
                self.materials[c] = material
        return self

    def paint_front(self, x0: int, y0: int, x1: int, y1: int, material: int) -> "Vox":
        """Paint the frontmost cell of each column in a rectangle of the x/y plane.

        A visor slit and a chest placard are features of the *face* of a part, not of a fixed z.
        Addressing them as `z == sz - 1` broke the moment `offset_band` gave the part a profile:
        the front of the chest is no longer the front of the hips, so the placard tore into a
        ragged line one voxel behind the surface on some layers and on the surface on others.
        """
        columns: dict[tuple[int, int], int] = {}
        for (x, y, z) in self.cells:
            if x0 <= x <= x1 and y0 <= y <= y1:
                key = (x, y)
                if z > columns.get(key, -1):
                    columns[key] = z
        for (x, y), z in columns.items():
            self.materials[(x, y, z)] = material
        return self

    # --- shaping, continued -----------------------------------------------------------------

    def taper_by_layer(self, width: Callable[[int], tuple[float, float]]) -> "Vox":
        """Like `taper`, but the profile is a function of the layer index rather than of 0..1.

        Anatomy is written as named bands (`hip`, `belt`, `waist`) computed in whole layers,
        and converting those back to a normalised height only to have `taper` convert them again
        lost a layer to rounding at almost every boundary.
        """
        keep: set[tuple[int, int, int]] = set()
        for (x, y, z) in self.cells:
            fx, fz = width(y)
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

    def offset_band(self, y0: int, y1: int, dz: int) -> "Vox":
        """Slide a horizontal band along z.

        The single most valuable operation here, and the one the first pass lacked. Every part was
        symmetric front-to-back, so in profile the whole cast was a flat slab and a turned figure
        lost all of its shape. A calf that sits back, a knee that leads, a chest that juts — those
        carry the silhouette at the low internal resolution the game renders at, where interior
        detail is gone but the outline survives.
        """
        if dz == 0:
            return self
        moved: set[tuple[int, int, int]] = set()
        materials: dict[tuple[int, int, int], int] = {}
        for c in self.cells:
            x, y, z = c
            target = (x, y, z + dz) if y0 <= y <= y1 else c
            moved.add(target)
            materials[target] = self.materials.get(c, 0)
        self.cells = moved
        self.materials = materials
        min_z = min(z for (_x, _y, z) in self.cells)
        if min_z < 0:
            self.cells = {(x, y, z - min_z) for (x, y, z) in self.cells}
            self.materials = {
                (x, y, z - min_z): m for (x, y, z), m in self.materials.items()
            }
        self.sz = max(z for (_x, _y, z) in self.cells) + 1
        return self

    def extend_forward(self, y0: int, y1: int, amount: int) -> "Vox":
        """Grow a band toward +z only — a toe.

        The volume grows past its declared `sz`; `normalised_cells` re-measures the span, and the
        manifest never states a size, so this is safe. Growing symmetrically instead (the old
        `flare`) produced a plinth with no front or back, which left a warden with no facing at
        all below the waist.
        """
        if amount <= 0:
            return self
        front = max((z for (_x, y, z) in self.cells if y0 <= y <= y1), default=None)
        if front is None:
            return self
        new: list[tuple[int, int, int]] = []
        for (x, y, z) in list(self.cells):
            if not (y0 <= y <= y1) or z != front:
                continue
            for step in range(1, amount + 1):
                new.append((x, y, z + step))
        for c in new:
            self.cells.add(c)
            self.materials.setdefault(c, self.materials.get((c[0], c[1], front), 0))
        self.sz = max(self.sz, front + amount + 1)
        return self

    # --- output ---------------------------------------------------------------------------

    def normalised_cells(self, shift_y: bool = True) -> list[list[int]]:
        """Cells shifted so the volume starts at the origin, sorted for a stable diff.

        A cell is `[x, y, z]` when it uses material 0 and `[x, y, z, m]` otherwise, which keeps an
        unpainted part byte-identical to what this generator produced before materials existed.

        `shift_y=False` keeps the volume's own vertical origin. Hair needs it: a hair volume is
        authored in head-local layers so that it lines up with the head without the call site
        having to supply a magic offset, and shifting a two-layer skullcap down to y = 0 would
        put a crop across the wearer's mouth.
        """
        if not self.cells:
            return []
        mx = min(c[0] for c in self.cells)
        my = min(c[1] for c in self.cells) if shift_y else 0
        mz = min(c[2] for c in self.cells)
        out: list[list[int]] = []
        for c in self.cells:
            material = self.materials.get(c, 0)
            shifted = [c[0] - mx, c[1] - my, c[2] - mz]
            out.append(shifted + [material] if material else shifted)
        return sorted(out)

    def used_materials(self) -> set[int]:
        return {self.materials.get(c, 0) for c in self.cells}

    def __len__(self) -> int:
        return len(self.cells)


# --- materials --------------------------------------------------------------------------------
#
# Indices into `PixelDioramaStyle.PaletteSlot`, written to the asset as `paletteSlots` and looked
# up per theme at load. Slots rather than RGB because the runtime snaps a literal colour to its
# nearest slot, and two authored colours can land on the same one — which would silently collapse
# a part back to the single flat colour this whole mechanism exists to get away from.

PLATE = 2  # WALL_BASE   — the armour itself
SHADOW = 3  # WALL_SHADOW — recesses, joint seams, the undersuit showing through
ACCENT = 4  # ACCENT      — tabard, cloth, the chest placard
LEATHER = 5  # PROP_WOOD  — belt and strapping
STEEL = 6  # PROP_METAL   — polished fittings: knee cops, gauntlets, brow, pauldron rim
GLOW = 7  # EMISSIVE      — the visor slit
HAIR = 1  # FLOOR_SHADOW  — hair, which needs to read against the helm rather than match it

#: Order matters: a cell's fourth element indexes into this, so it is the file's `paletteSlots`.
#: Append only — an existing index must keep meaning what it meant when the assets were written.
MATERIALS: tuple[int, ...] = (PLATE, SHADOW, ACCENT, LEATHER, STEEL, GLOW, HAIR)

#: Position within MATERIALS, which is what actually gets written per cell.
M_PLATE, M_SHADOW, M_ACCENT, M_LEATHER, M_STEEL, M_GLOW, M_HAIR = range(7)


def _band(sy: int, lo: float, hi: float) -> tuple[int, int]:
    """A named horizontal band as a fraction of the part's height, in whole layers.

    Anatomy is expressed in fractions rather than fixed layer counts because the same profiles
    have to serve a 13-layer warden arm and a 5-layer hound leg. The clamp keeps a band from
    inverting on a very short part — a two-layer limb still gets a boot and a thigh, just one
    layer each.
    """
    y0 = int(round((sy - 1) * lo))
    y1 = int(round((sy - 1) * hi))
    return min(y0, sy - 1), min(max(y1, y0), sy - 1)


# --- part profiles ---------------------------------------------------------------------------
#
# Keyed by the role a part plays rather than by its exact name, so every archetype — player,
# brute, hound, the ten biome enemies — picks up the same language of shapes automatically.


def sculpt_torso(sx: int, sy: int, sz: int) -> Vox:
    """Pelvis, belt, drawn-in waist, flared ribcage, collar.

    y = 0 is the hip and y = max the shoulders. The old profile was a single smooth taper from
    waist to shoulder plus one recessed line, which is why every character read as a slab: a torso
    is not monotonic, it pinches at the waist and flares again at the ribs.
    """
    v = Vox(sx, sy, sz)
    hip0, hip1 = _band(sy, 0.00, 0.12)
    belt0, belt1 = _band(sy, 0.13, 0.24)
    waist0, waist1 = _band(sy, 0.25, 0.40)
    chest0, chest1 = _band(sy, 0.41, 0.84)
    collar0, collar1 = _band(sy, 0.85, 1.00)

    def width(y: int) -> tuple[float, float]:
        if y <= hip1:
            return 0.78, 0.80
        if y <= belt1:
            return 0.82, 0.82
        if y <= waist1:
            return 0.78, 0.76  # the pinch that makes a chest read as a chest
        if y <= chest1:
            t = (y - waist1) / max(1, chest1 - waist1)
            return 0.78 + 0.22 * _ease(t), 0.76 + 0.24 * _ease(t)
        return 1.0, 0.96

    v.taper_by_layer(width)
    v.chamfer_vertical(max(1, min(sx, sz) // 5))
    v.chamfer_cap(1, top=True)
    # Neck slot, so the head sits into the shoulders instead of balancing on them.
    neck = max(1, sx // 4)
    v.notch(neck, sy - 1, neck, sx - 1 - neck, sy - 1, sz - 1 - neck)

    if sz >= 6:
        # Chest forward of the hips. Without it a torso is a plank and the figure reads the same
        # from the front and from the side.
        v.offset_band(chest0, collar1, 1)

    v.paint_all(M_PLATE)
    v.paint_layers(waist0, waist1, M_SHADOW)
    v.paint_layers(belt0, belt1, M_LEATHER)
    v.paint_layers(collar0, collar1, M_STEEL)
    # Chest placard: a vertical panel up the front, the one piece of colour that reads at
    # thumbnail size and tells you which way the figure is facing.
    if sx >= 6 and chest1 > chest0:
        # Narrow, and only over the upper chest. Run the full height of the chest band it becomes a
        # slab taped to the front rather than a tabard.
        px0 = sx // 2 - max(1, sx // 8)
        px1 = sx - 1 - px0
        v.paint_front(px0, (chest0 + chest1) // 2, px1, chest1, M_ACCENT)
    return v


def sculpt_head(sx: int, sy: int, sz: int) -> Vox:
    """A helm: narrow neck, jaw, full skull, brow band, bevelled crown, lit visor slit."""
    v = Vox(sx, sy, sz)
    neck0, neck1 = _band(sy, 0.00, 0.06)
    jaw0, jaw1 = _band(sy, 0.07, 0.32)
    face0, face1 = _band(sy, 0.33, 0.74)
    # One layer, inset. A full-width two-layer band across the middle of an eight-voxel head is
    # the brightest thing on the model and reads as a cap brim rather than as a brow.
    brow0, brow1 = _band(sy, 0.55, 0.55)
    crown0, crown1 = _band(sy, 0.75, 1.00)

    def width(y: int) -> tuple[float, float]:
        if y <= neck1:
            # Wide enough to fill the collar notch the torso cuts for it (`sx // 4` in from each
            # side). A narrower neck leaves a dark slot around itself at the shoulders.
            return 0.72, 0.72
        if y <= jaw1:
            t = (y - neck1) / max(1, jaw1 - neck1)
            return 0.72 + 0.28 * _ease(t), 0.74 + 0.26 * _ease(t)
        if y <= face1:
            return 1.0, 1.0
        # The crown draws in rather than capping the head with a wider slab.
        return 0.82, 0.82

    v.taper_by_layer(width)
    v.chamfer_vertical(max(1, min(sx, sz) // 4))
    v.chamfer_cap(max(1, sy // 5), top=True)

    if sz >= 6:
        # The face plane sits proud of the crown, so a helm has a front.
        v.offset_band(jaw0, face1, 1)

    v.paint_all(M_PLATE)
    v.paint_layers(neck0, neck1, M_SHADOW)
    v.paint_layers(crown0, crown1, M_PLATE)
    if sx >= 6:
        v.paint_region(1, brow0, 1, sx - 2, brow1, sz - 1, M_STEEL)
    else:
        v.paint_layers(brow0, brow1, M_STEEL)
    # Visor: a lit slot across the eyes, on the front face only. The strongest identity cue a
    # voxel head has — and the reason the head is worth more than four layers.
    if sx >= 4:
        v.paint_front(2, brow0, sx - 3, brow1, M_GLOW)
    return v


def sculpt_limb(sx: int, sy: int, sz: int, boot: bool = False) -> Vox:
    """Arms and legs as four segments rather than one cone.

    y = 0 is the foot or the hand and y = max the hip or shoulder, because both hang from their
    joint. The segments — extremity, narrow joint, shaft, hard joint cap, upper shaft — are what
    the eye reads as a knee and an elbow. A single taper has none of them, which is why the legs
    came out as two large rectangles.
    """
    v = Vox(sx, sy, sz)
    ext0, ext1 = _band(sy, 0.00, 0.14)  # boot / gauntlet
    ankle0, ankle1 = _band(sy, 0.15, 0.24)  # the narrow bit above it
    lower0, lower1 = _band(sy, 0.25, 0.50)  # shin / forearm
    joint0, joint1 = _band(sy, 0.51, 0.62)  # knee cop / elbow
    upper0, upper1 = _band(sy, 0.63, 1.00)  # thigh / upper arm

    def width(y: int) -> tuple[float, float]:
        if y <= ext1:
            return 0.92, 1.0
        if y <= ankle1:
            return 0.62, 0.62
        if y <= lower1:
            t = (y - ankle1) / max(1, lower1 - ankle1)
            return 0.70 + 0.14 * t, 0.70 + 0.12 * t
        if y <= joint1:
            return 0.94, 0.94
        t = (y - joint1) / max(1, upper1 - joint1)
        return 0.82 + 0.18 * _ease(t), 0.80 + 0.20 * _ease(t)

    v.taper_by_layer(width)
    v.chamfer_vertical(1)
    v.chamfer_cap(1, top=True)
    if boot:
        # A toe, forward only. Flaring both ways gave a symmetric plinth that read as a plant pot
        # and left the figure with no facing at all below the waist.
        v.extend_forward(ext0, ext1, max(1, sz // 4))
    else:
        # A fist. The extremity band existed on arms too but was painted the same steel as the rest
        # of the limb, so an arm was a featureless bar with no hand on the end of it — legs read
        # correctly only because their band is leather and a different colour. Pushed forward half
        # as far as a toe, so it reads as a closed hand rather than a boot on the wrong limb.
        v.extend_forward(ext0, ext1, max(1, sz // 6))
    if sz >= 5:
        # A leg in profile: the calf sits behind the ankle, the knee leads. Width alone cannot
        # express this — on a six-voxel leg the parity rule leaves only 4 and 6 to choose from.
        v.offset_band(lower0, lower1, -1)
        v.offset_band(joint0, joint1, 1)

    elif sz >= 4:
        # An arm hangs with the elbow behind the wrist.
        v.offset_band(joint0, upper1, -1)

    v.paint_all(M_PLATE)
    v.paint_layers(ankle0, ankle1, M_SHADOW)
    v.paint_layers(joint0, joint1, M_STEEL)
    # Leather either way: a boot on the leg, a glove on the arm. Steel here made the hand vanish
    # into the vambrace above it.
    v.paint_layers(ext0, ext1, M_LEATHER)
    return v


def sculpt_block(sx: int, sy: int, sz: int) -> Vox:
    """Fallback for pauldrons, trims, weapons and anything else: bevel it, never ship a raw box.

    Parts thinner than three voxels across are left alone. A chamfer needs a corner to cut, and on
    a two-wide bow stave the cap bevel simply deleted the top layer — it shortened the weapon
    instead of shaping it.
    """
    v = Vox(sx, sy, sz)
    if min(sx, sz) < 3:
        v.paint_all(M_STEEL)
        return v
    v.chamfer_vertical(1)
    v.chamfer_cap(1, top=True)
    v.paint_all(M_PLATE)
    # A rim on the outermost layer catches the light and keeps a pauldron from reading as a lump.
    v.paint_layers(sy - 1, sy - 1, M_STEEL)
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


# --- hair -------------------------------------------------------------------------------------
#
# Hair is authored in *head-local* coordinates: a hair volume is the same size as the head it caps,
# with cells only where there is hair. Anything else needs a magic vertical offset at the call
# site, and the one that existed (`EDGE * 3`) put a short crop across the middle of the face.
#
# The two hair files that shipped had an empty `cells` array. The runtime reads that as "fill the
# bounding box", so both rendered as solid 7x2x7 slabs — and because the hair holder never applied
# the centring offset that every other part gets, the slab grew out of the head's corner and stuck
# out sideways. That is the bill on the front of every warden in the game.


#: Every style as parameters rather than a branch.
#:
#: Six styles used to be six `if` arms, which is fine for six and unmaintainable for twenty-five —
#: and it is the shape that lets two styles drift apart in ways nobody intended. A table means a new
#: style is a row, every style is built by the same code, and "consistent with the others" is
#: structural rather than a thing to remember.
#:
#: * ``cap``    — skullcap depth in voxels, from the crown down. Every style has one.
#: * ``back``   — (length, inset) of a sheet down the back of the head. 0 disables it.
#: * ``sides``  — (length, inset) of a fall beside each jaw. 0 disables it.
#: * ``tail``   — (length, width) of a narrow tail off the back of the crown.
#: * ``crest``  — "none" | "spikes" | "mohawk" | "topknot", worked on the crown.
#: * ``fringe`` — rows of hair hanging over the brow at the front.
HAIR_RECIPES: dict[str, dict] = {
    "shaven":     dict(cap=1),
    "short":      dict(cap=2),
    "crop":       dict(cap=2, fringe=1),
    "bowl":       dict(cap=2, fringe=1, sides=(2, 1), back=(2, 1)),
    "tied":       dict(cap=2, tail=(3, 2)),
    "topknot":    dict(cap=2, crest="topknot", tail=(3, 2)),
    "ponytail":   dict(cap=2, tail=(6, 2)),
    "braided":    dict(cap=2, sides=(5, 1)),
    "twin_falls": dict(cap=2, sides=(7, 1)),
    "long":       dict(cap=2, back=(6, 1)),
    "flowing":    dict(cap=2, back=(8, 1), sides=(4, 1)),
    "mane":       dict(cap=3, back=(7, 0), sides=(5, 0)),
    "wild":       dict(cap=3, crest="spikes"),
    "windswept":  dict(cap=2, crest="spikes", back=(3, 1)),
    "mohawk":     dict(cap=1, crest="mohawk"),
    "crest":      dict(cap=1, crest="mohawk", back=(4, 2)),
    "tonsure":    dict(cap=1, sides=(2, 0)),
    "widow":      dict(cap=2, fringe=2),
    "shag":       dict(cap=2, fringe=1, sides=(3, 1), crest="spikes"),
    "bob":        dict(cap=2, sides=(3, 0), back=(3, 0), fringe=1),
    "cropped_tail": dict(cap=1, tail=(4, 1)),
    "warrior":    dict(cap=2, crest="mohawk", tail=(5, 2)),
    "loose":      dict(cap=2, back=(4, 1), fringe=1),
    "shorn_sides": dict(cap=2, crest="mohawk", fringe=1),
    "veiled":     dict(cap=2, back=(9, 0), sides=(6, 0)),
}


def sculpt_hair(style: str, sx: int, sy: int, sz: int) -> Vox:
    """A hair volume sized to the head, filled only where the style has hair."""
    recipe = HAIR_RECIPES.get(style, HAIR_RECIPES["short"])
    v = Vox(sx, sy, sz, solid=False)
    crown = sy - 1
    depth = int(recipe.get("cap", 2))
    back = 0  # -z is behind the warden; the face is at +z.
    front = sz - 1

    # The skullcap: every style has one, inset by a voxel at the crown so it reads as hair sitting
    # *on* the head rather than as a wider hat brim.
    for y in range(max(0, crown - depth + 1), crown + 1):
        inset = 0 if y < crown else 1
        for x in range(inset, sx - inset):
            for z in range(inset, sz - inset):
                if min(x, sx - 1 - x) + min(z, sz - 1 - z) < (1 if y == crown else 0):
                    continue
                v.cells.add((x, y, z))

    sheet = recipe.get("back", (0, 1))
    if sheet[0]:
        length, inset = sheet
        for y in range(max(0, crown - length), crown):
            for x in range(inset, sx - inset):
                v.cells.add((x, y, back))
                if inset == 0:
                    v.cells.add((x, y, back + 1))

    falls = recipe.get("sides", (0, 1))
    if falls[0]:
        length, inset = falls
        for y in range(max(0, crown - length), crown):
            for z in (back, back + 1):
                v.cells.add((inset, y, z))
                v.cells.add((sx - 1 - inset, y, z))

    tail = recipe.get("tail", (0, 0))
    if tail[0]:
        length, width = tail
        half = max(1, width) // 2
        for y in range(max(0, crown - length), crown - 1):
            for x in range(sx // 2 - half, sx // 2 - half + max(1, width)):
                v.cells.add((min(max(x, 0), sx - 1), y, back))

    crest = str(recipe.get("crest", "none"))
    if crest == "spikes":
        for x in range(0, sx, 2):
            for z in range(0, sz, 2):
                v.cells.add((x, crown, z))
    elif crest == "mohawk":
        for z in range(sz):
            for x in (sx // 2 - 1, sx // 2):
                v.cells.add((max(0, min(x, sx - 1)), crown, z))
    elif crest == "topknot":
        # There is no room *above* the crown — the volume is exactly as tall as the head — so a
        # knot has to be built out of the ring the skullcap's crown inset leaves free. Gathered at
        # the back, which is also what stops this coming out byte-identical to `short`: the first
        # version wrote only cells the cap had already filled, and the two meshes were the same.
        for x in (sx // 2 - 1, sx // 2):
            v.cells.add((max(0, min(x, sx - 1)), crown, back))
        for z in (back, back + 1):
            v.cells.add((sx // 2, crown, max(0, min(z, sz - 1))))

    for row in range(int(recipe.get("fringe", 0))):
        y = crown - depth - row
        if y < 0:
            continue
        for x in range(1, sx - 1):
            v.cells.add((x, y, front))

    v.paint_all(M_HAIR)
    return v


# --- faces ------------------------------------------------------------------------------------
#
# A face plate is a thin slab that sits on the front of the head. It is a *separate* mesh instance,
# which is the whole point: the body's colours come from the biome palette, but skin does not, and
# only a separate instance can carry its own tint.
#
# Two materials, and they are literal rather than palette slots. Index 0 is white and index 1 is
# near-black; the runtime multiplies the whole plate by the chosen skin colour, so the white field
# becomes skin and the dark features stay dark whatever tone is picked.
#
# Six styles that had, between them, two implementations: `stern` and `kind` drew accent boxes
# positioned against `PROFILES["player"]` — a hardcoded box spec that is not the size of the voxel
# head actually being built — and `weary`, `scarred` and `hollow` did nothing at all.

FACE_SKIN = 0
FACE_MARK = 1

#: Rows read top (brow) to bottom (chin); `#` is a feature, `.` is skin. Six columns of the head's
#: eight and four rows of its eight: the head tapers toward the crown, so a full-width plate hangs
#: over the sides, and a full-height one leaves no helm around the face at all.
#:
#: Density matters more than cleverness here. A first pass used six columns with two or three marks
#: per face and every style rendered as a flat coloured slab: at this size the eye is looking for a
#: *pattern*, and three dark cells in thirty do not make one.
FACE_MASKS: dict[str, tuple[str, ...]] = {
    "open":      ("......", ".#..#.", "......", "..##.."),
    "stern":     ("##..##", ".#..#.", "......", "..##.."),
    "kind":      (".#..#.", "##..##", "......", "#.##.#"),
    "weary":     ("......", ".#..#.", ".#..#.", "..##.."),
    "scarred":   ("....##", ".#..#.", "...#..", "..##.."),
    "hollow":    ("......", "##..##", "#....#", "..##.."),
    "grim":      ("##..##", "##..##", "......", ".####."),
    "watchful":  (".#..#.", "#.##.#", "......", "..##.."),
    "hardened":  ("#....#", "##..##", "#....#", ".####."),
    "gaunt":     ("......", "#....#", "#....#", "..##.."),
    "wry":       ("......", ".#..#.", "......", "#..##."),
    "grave":     ("##..##", ".#..#.", "......", ".####."),
    "young":     ("......", ".#..#.", "......", "...#.."),
    "seamed":    ("#....#", ".#..#.", "#....#", "..##.."),
    "burned":    ("###...", ".#..#.", "##....", "..##.."),
    "veteran":   ("##...#", ".#..#.", "....#.", ".####."),
    "sleepless": ("......", ".#..#.", "##..##", "..##.."),
    "resolute":  (".####.", ".#..#.", "......", ".####."),
    "wolfish":   ("#....#", ".#..#.", "......", "#.##.#"),
    "sunken":    (".#..#.", "##..##", ".#..#.", "..##.."),
    "brand":     ("..##..", ".#..#.", "......", "..##.."),
    "split":     ("...##.", ".#..#.", "...#..", "..##.."),
    "patient":   ("......", ".#..#.", "......", ".####."),
    "cold":      ("##..##", "#....#", "......", "..##.."),
    "ruined":    ("##.###", "##..#.", "#...#.", ".###.."),
}


def sculpt_face(style: str, width: int = 6, height: int = 4, depth: int = 1) -> Vox:
    """A face plate for one style, one voxel deep."""
    rows = FACE_MASKS.get(style, FACE_MASKS["open"])
    v = Vox(width, height, depth, solid=False)
    for row_index, row in enumerate(rows[:height]):
        # Row 0 of the mask is the brow, which is the *top* of the volume.
        y = height - 1 - row_index
        for x in range(min(width, len(row))):
            for z in range(depth):
                cell = (x, y, z)
                v.cells.add(cell)
                v.materials[cell] = FACE_MARK if row[x] == "#" else FACE_SKIN
    return v


# --- class garments ----------------------------------------------------------------------------
#
# What an unequipped character wears, and the only thing that distinguishes one class from another
# before a single item is picked up.
#
# What this replaces: one `add_box` per class for five of the seven — herald and hunter had nothing
# — each positioned against `PROFILES["player"]`, a hardcoded box spec that is not the size of the
# voxel torso actually being built, and each coloured from the biome palette so that every class in
# a given dungeon came out the same colour anyway.
#
# Colours here are literal and deliberately strong. A class silhouette has to read at a glance and
# from behind, and the palette slots are all muted stone and metal by design — correct for a room,
# useless for telling a scholar from a sentinel.
#
# The volume wraps the torso with one voxel of clearance on each side and extends six voxels below
# it, which is the room a skirt or a set of faulds needs. `SKIRT_DROP` is that overhang; the runtime
# aligns `y = SKIRT_DROP` with the base of the torso mesh.

SKIRT_DROP = 6

G_PRIMARY, G_TRIM, G_LEATHER, G_FOLD = 0, 1, 2, 3

#: primary, trim, leather, fold — per class.
#:
#: `fold` is the primary darkened. Cloth panels are large flat areas of one colour, and at this
#: scale the surface shader's stitch pattern is the only thing varying across them, which reads as
#: graph paper rather than as fabric. A column of the darker tone every few voxels reads as a fold
#: and gives the panel a direction.
#:
#: Rogue is near-black rather than the dark teal it started as: beside the hunter's forest green the
#: two were the same silhouette in two shades of the same colour, and a rogue reading as "the dark
#: one" is worth more than a rogue reading as "the other green one".
GARMENT_PALETTES: dict[str, list[list[float]]] = {
    "knight":    [[0.20, 0.34, 0.62], [0.86, 0.88, 0.92], [0.28, 0.22, 0.18], [0.13, 0.23, 0.44]],
    "sentinel":  [[0.30, 0.33, 0.38], [0.94, 0.70, 0.22], [0.24, 0.20, 0.17], [0.20, 0.22, 0.26]],
    "berserker": [[0.62, 0.20, 0.16], [0.82, 0.62, 0.34], [0.34, 0.24, 0.16], [0.42, 0.13, 0.11]],
    "rogue":     [[0.11, 0.12, 0.15], [0.42, 0.52, 0.30], [0.20, 0.16, 0.13], [0.07, 0.08, 0.10]],
    "hunter":    [[0.20, 0.42, 0.24], [0.78, 0.64, 0.36], [0.30, 0.22, 0.15], [0.13, 0.29, 0.16]],
    "scholar":   [[0.34, 0.20, 0.52], [0.92, 0.78, 0.32], [0.24, 0.18, 0.26], [0.23, 0.13, 0.37]],
    "herald":    [[0.90, 0.90, 0.92], [0.74, 0.14, 0.20], [0.28, 0.24, 0.22], [0.72, 0.72, 0.76]],
}


def _fill(v: Vox, x0: int, y0: int, z0: int, x1: int, y1: int, z1: int, material: int) -> None:
    """Fill an inclusive box, clipped to the volume."""
    for x in range(max(0, x0), min(v.sx, x1 + 1)):
        for y in range(max(0, y0), min(v.sy, y1 + 1)):
            for z in range(max(0, z0), min(v.sz, z1 + 1)):
                cell = (x, y, z)
                v.cells.add(cell)
                v.materials[cell] = material


def _torso_skin(torso: Vox, drop: int) -> dict[tuple[int, int, int], str]:
    """The layer of cells sitting one voxel outside the torso's surface, tagged by which face.

    Clothing is built by dilating the body rather than by boxing it in. A garment authored as a
    rectangular shell is a sandwich board: the torso pinches at the waist and flares at the ribs, so
    a constant-width shell stands a voxel proud at the chest and three proud at the belt, hides the
    body it is supposed to be worn by, and hangs past the shoulders. Growing it out of the torso's
    own occupancy means it follows every taper for free, and it fits every stature and build without
    a separate volume per body shape.

    Coordinates are shifted by (+1, +drop, +1) so the dilated layer stays inside a volume that is
    two voxels wider and `drop` voxels taller than the torso.
    """
    out: dict[tuple[int, int, int], str] = {}
    occupied = torso.cells
    faces = (
        ((0, 0, 1), "front"),
        ((0, 0, -1), "back"),
        ((1, 0, 0), "side"),
        ((-1, 0, 0), "side"),
    )
    for (x, y, z) in occupied:
        for (dx, dy, dz), tag in faces:
            neighbour = (x + dx, y + dy, z + dz)
            if neighbour in occupied:
                continue
            cell = (neighbour[0] + 1, neighbour[1] + drop, neighbour[2] + 1)
            # Front and back win over side, so a corner reads as part of the panel it belongs to.
            if out.get(cell) in (None, "side"):
                out[cell] = tag
    return out


def _wear(
    v: Vox,
    skin: dict[tuple[int, int, int], str],
    y0: int,
    y1: int,
    material: int,
    faces: tuple[str, ...] = ("front", "back", "side"),
) -> None:
    """Clothe the body between two heights, on the named faces."""
    for cell, tag in skin.items():
        if y0 <= cell[1] <= y1 and tag in faces:
            v.cells.add(cell)
            v.materials[cell] = material


def _hem(v: Vox, skin: dict[tuple[int, int, int], str], y0: int, y1: int, material: int) -> None:
    """A skirt: the torso's footprint at its lowest clothed layer, repeated downward.

    A robe does not stop where the body does, and the dilated layer has nothing below the torso to
    grow from, so the hem is extruded from the lowest ring instead.
    """
    lowest = min((c[1] for c in skin), default=None)
    if lowest is None:
        return
    ring = [c for c, tag in skin.items() if c[1] == lowest and tag != "none"]
    for y in range(y0, y1 + 1):
        for (x, _y, z) in ring:
            cell = (x, y, z)
            v.cells.add(cell)
            v.materials[cell] = material


def _sash(v: Vox, skin: dict[tuple[int, int, int], str], y0: int, y1: int, material: int) -> None:
    """A strap running corner to corner across the chest — the fastest read there is."""
    front = [c for c, tag in skin.items() if tag == "front" and y0 <= c[1] <= y1]
    if not front:
        return
    xs = [c[0] for c in front]
    lo, hi = min(xs), max(xs)
    span = max(1, y1 - y0)
    for cell in front:
        t = (cell[1] - y0) / span
        target = lo + t * (hi - lo)
        if abs(cell[0] - target) <= 0.9:
            v.cells.add(cell)
            v.materials[cell] = material


def _folds(v: Vox, skin: dict[tuple[int, int, int], str], y0: int, y1: int, period: int = 3) -> None:
    """Darken a column of cloth every `period` voxels, on the panels only."""
    for cell, tag in skin.items():
        if tag == "side" or not (y0 <= cell[1] <= y1):
            continue
        if cell not in v.cells:
            continue
        if v.materials.get(cell) != G_PRIMARY:
            continue
        if cell[0] % period == 0:
            v.materials[cell] = G_FOLD


def sculpt_garment(class_id: str, torso: Vox) -> Vox:
    """The default clothing for one class, grown out of the torso it is worn on."""
    sx, sy, sz = torso.sx + 2, torso.sy + SKIRT_DROP + 1, torso.sz + 2
    v = Vox(sx, sy, sz, solid=False)
    skin = _torso_skin(torso, SKIRT_DROP)
    ty = torso.sy
    base = SKIRT_DROP
    waist = base + ty // 3
    chest = base + (ty * 2) // 3
    top = base + ty - 1

    if class_id == "knight":
        # Surcoat over plate: panels front and back to mid-thigh, a bold centre stripe, steel yoke.
        _wear(v, skin, waist, chest + 1, G_PRIMARY)
        _hem(v, skin, base - 4, waist - 1, G_PRIMARY)
        _wear(v, skin, chest + 2, top, G_TRIM)
        for cell, tag in skin.items():
            if tag == "front" and waist <= cell[1] <= chest + 1 and abs(cell[0] - sx // 2) <= 1:
                v.cells.add(cell)
                v.materials[cell] = G_TRIM
        _wear(v, skin, waist - 1, waist - 1, G_LEATHER)
    elif class_id == "sentinel":
        # Faulds — overlapping plate skirt — and a heavy gorget at the throat.
        _wear(v, skin, waist, chest + 1, G_PRIMARY)
        _wear(v, skin, top - 1, top, G_TRIM)
        for i in range(3):
            band = base - 1 - i * 2
            _hem(v, skin, band - 1, band, G_TRIM if i % 2 else G_PRIMARY)
        _wear(v, skin, waist - 1, waist - 1, G_LEATHER)
    elif class_id == "berserker":
        # A fur mantle over the shoulders with a ragged hem, bare below, and one strap.
        _wear(v, skin, chest, top, G_TRIM)
        for cell, tag in skin.items():
            if cell[1] == chest - 1 and cell[0] % 2 == 0 and tag != "side":
                v.cells.add(cell)
                v.materials[cell] = G_TRIM
        _wear(v, skin, waist - 1, waist, G_LEATHER)
        _sash(v, skin, waist + 1, chest - 1, G_PRIMARY)
    elif class_id == "rogue":
        # Close wrap, wide belt, baldric across the chest.
        _wear(v, skin, waist, chest + 2, G_PRIMARY)
        _wear(v, skin, waist - 2, waist - 1, G_LEATHER)
        _sash(v, skin, waist + 1, chest + 2, G_TRIM)
        _wear(v, skin, top - 1, top, G_PRIMARY)
    elif class_id == "hunter":
        # Light jerkin, quiver strap, short cape at the back.
        _wear(v, skin, waist, chest + 1, G_PRIMARY)
        _sash(v, skin, waist + 1, chest + 1, G_LEATHER)
        _wear(v, skin, base - 3, chest + 2, G_TRIM, faces=("back",))
        _wear(v, skin, waist - 1, waist - 1, G_LEATHER)
    elif class_id == "scholar":
        # Full-length robe with a stole hanging down the front.
        _wear(v, skin, base, chest + 1, G_PRIMARY)
        _hem(v, skin, 0, base - 1, G_PRIMARY)
        for cell, tag in skin.items():
            if tag == "front" and base <= cell[1] <= top and abs(abs(cell[0] - sx // 2) - 2) < 0.6:
                v.cells.add(cell)
                v.materials[cell] = G_TRIM
        _wear(v, skin, top - 1, top, G_TRIM)
        _wear(v, skin, waist, waist, G_LEATHER)
    elif class_id == "herald":
        # Party per pale: a tabard split straight down the middle, mirrored back to front.
        _wear(v, skin, waist, chest + 1, G_PRIMARY)
        _hem(v, skin, base - 4, waist - 1, G_PRIMARY)
        for cell, tag in skin.items():
            if not (base - 4 <= cell[1] <= chest + 1):
                continue
            if tag == "front" and cell[0] >= sx // 2:
                v.cells.add(cell)
                v.materials[cell] = G_TRIM
            elif tag == "back" and cell[0] < sx // 2:
                v.cells.add(cell)
                v.materials[cell] = G_TRIM
        _wear(v, skin, top - 1, top, G_TRIM)
        _wear(v, skin, waist - 1, waist - 1, G_LEATHER)
    _folds(v, skin, 0, top)
    return v


# --- hood -------------------------------------------------------------------------------------


HOOD_DROP = 3


def sculpt_hood(head: Vox, drop: int = HOOD_DROP) -> Vox:
    """A cowl that wraps the head: crown, back and sides, open at the face.

    Grown from the head's own occupancy, like the class garments are grown from the torso, so it
    follows the skull instead of hanging off it. What it replaces was an 8x4x7 box offset behind the
    head — a slab that neither covered the crown nor closed at the sides, and left whatever hair the
    player had chosen sticking through it.

    `drop` is how far the cowl continues below the head, which is what gives it a neck rather than
    stopping in a straight line at the jaw.
    """
    pad = 1
    sx, sy, sz = head.sx + pad * 2, head.sy + pad, head.sz + pad * 2
    v = Vox(sx, sy, sz, solid=False)
    occupied = head.cells
    if not occupied:
        return v
    front = max(z for (_x, _y, z) in occupied)
    top = max(y for (_x, y, _z) in occupied)
    base = min(y for (_x, y, _z) in occupied)

    # One layer out from the skull, on every face except the one the player looks at.
    for (x, y, z) in occupied:
        for dx, dy, dz in ((1, 0, 0), (-1, 0, 0), (0, 0, -1), (0, 1, 0)):
            neighbour = (x + dx, y + dy, z + dz)
            if neighbour in occupied:
                continue
            # Leave the face open. The opening is the front plane and the row just behind it, so the
            # cowl reads as an edge standing proud of the face rather than a mask cut flush with it.
            if neighbour[2] >= front and dy == 0:
                continue
            v.cells.add((neighbour[0] + pad, neighbour[1], neighbour[2] + pad))

    # Cap the crown so there is no hole where the head's own chamfer pulls in.
    for (x, y, z) in list(occupied):
        if y == top:
            v.cells.add((x + pad, y + 1, z + pad))

    # Carry the cowl down past the jaw at the back and sides.
    ring = [
        (x, z) for (x, y, z) in occupied
        if y == base and (z < front)
    ]
    for i in range(1, drop + 1):
        for (x, z) in ring:
            if x in (min(p[0] for p in ring), max(p[0] for p in ring)) or z == min(p[1] for p in ring):
                v.cells.add((x + pad, base - i, z + pad))

    v.paint_all(M_PLATE)
    # A lighter lip around the opening, so the hood has an edge instead of a silhouette.
    rim = [c for c in v.cells if c[2] == max(cell[2] for cell in v.cells)]
    for cell in rim:
        v.materials[cell] = M_STEEL
    return v
