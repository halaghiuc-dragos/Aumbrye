class_name DioramaEquipmentKit
extends RefCounted

## Procedural voxel models for worn equipment.
##
## Armour used to be authored one `.voxels.json` per item, and only three items ever got one — each
## of those with an empty `cells` array, which the mesh builder fills in as its whole bounding box.
## So a helmet was a solid block over the head and a cuirass was a solid block over the torso, and
## every other piece in the game wore nothing at all.
##
## There are around eighty wearable pieces across five slots, which is too many to sculpt by hand and
## far too many to keep in step with the item catalogue. Instead each piece resolves to a *shape*
## (what kind of thing it is: a helm, a crown, a cowl, a cuirass, a cloak…) and a *family* (what it
## is made of: pit iron, hoarfrost, spellglass…). The shape carries the silhouette, the family
## carries the colour, and every item in the catalogue gets a model that reads as itself.
##
## Models are built in a canonical voxel grid and then fitted to whatever body part they hang on, so
## they do not depend on any one rig's proportions. The character faces +Z.

const VoxelGridScript := preload("res://scripts/art/characters/voxel_grid.gd")

const EDGE := VoxelGridScript.EDGE

# Palette indices used by every shape below.
const MAT_METAL := 0
const MAT_DARK := 1
const MAT_ACCENT := 2
const MAT_CLOTH := 3

## Material families, as [metal, dark, accent, cloth].
##
## Values run dark and every family is given a definite hue. The first pass at this used honest
## metal greys around 0.55 and every piece came out of the scene lighting as a white block: at the
## exposure the game actually renders at, a desaturated mid grey is white, and eighteen different
## materials all landed on the same non-colour. Dark and tinted is what keeps pit iron, hoarfrost and
## mirebrass telling themselves apart on a lit character.
const FAMILIES := {
	"iron": [
		Color(0.26, 0.27, 0.30), Color(0.11, 0.12, 0.14),
		Color(0.46, 0.36, 0.16), Color(0.20, 0.14, 0.10),
	],
	"steel": [
		Color(0.34, 0.37, 0.43), Color(0.15, 0.17, 0.21),
		Color(0.52, 0.45, 0.22), Color(0.18, 0.14, 0.12),
	],
	"graysteel": [
		Color(0.29, 0.31, 0.34), Color(0.13, 0.14, 0.16),
		Color(0.44, 0.42, 0.34), Color(0.19, 0.17, 0.15),
	],
	"castle": [
		Color(0.33, 0.29, 0.24), Color(0.15, 0.13, 0.11),
		Color(0.58, 0.44, 0.16), Color(0.30, 0.10, 0.12),
	],
	"cathedral": [
		Color(0.20, 0.19, 0.26), Color(0.09, 0.08, 0.12),
		Color(0.58, 0.46, 0.18), Color(0.44, 0.42, 0.40),
	],
	"reliquary": [
		Color(0.42, 0.36, 0.22), Color(0.18, 0.15, 0.09),
		Color(0.62, 0.50, 0.20), Color(0.34, 0.31, 0.28),
	],
	"hoarfrost": [
		Color(0.28, 0.42, 0.52), Color(0.11, 0.19, 0.27),
		Color(0.46, 0.62, 0.74), Color(0.20, 0.28, 0.36),
	],
	"frost": [
		Color(0.26, 0.39, 0.49), Color(0.10, 0.17, 0.25),
		Color(0.44, 0.60, 0.72), Color(0.18, 0.26, 0.34),
	],
	"crystal": [
		Color(0.24, 0.36, 0.52), Color(0.10, 0.15, 0.26),
		Color(0.36, 0.60, 0.70), Color(0.18, 0.22, 0.34),
	],
	"spellglass": [
		Color(0.26, 0.20, 0.40), Color(0.11, 0.08, 0.18),
		Color(0.52, 0.34, 0.72), Color(0.19, 0.15, 0.28),
	],
	"mirebrass": [
		Color(0.38, 0.30, 0.12), Color(0.16, 0.13, 0.06),
		Color(0.18, 0.38, 0.30), Color(0.20, 0.19, 0.10),
	],
	"pitiron": [
		Color(0.17, 0.16, 0.16), Color(0.07, 0.07, 0.07),
		Color(0.62, 0.26, 0.08), Color(0.15, 0.12, 0.11),
	],
	"swamp": [
		Color(0.24, 0.28, 0.16), Color(0.10, 0.13, 0.07),
		Color(0.44, 0.50, 0.16), Color(0.19, 0.16, 0.10),
	],
	"tide": [
		Color(0.17, 0.31, 0.33), Color(0.07, 0.14, 0.16),
		Color(0.38, 0.62, 0.58), Color(0.14, 0.20, 0.20),
	],
	"ember": [
		Color(0.30, 0.14, 0.10), Color(0.13, 0.06, 0.05),
		Color(0.72, 0.34, 0.08), Color(0.18, 0.10, 0.08),
	],
	"gold": [
		Color(0.52, 0.40, 0.12), Color(0.24, 0.17, 0.04),
		Color(0.76, 0.62, 0.26), Color(0.24, 0.17, 0.08),
	],
	"silver": [
		Color(0.42, 0.44, 0.48), Color(0.19, 0.20, 0.24),
		Color(0.52, 0.55, 0.62), Color(0.18, 0.18, 0.21),
	],
	"jade": [
		Color(0.18, 0.38, 0.27), Color(0.07, 0.17, 0.12),
		Color(0.42, 0.68, 0.48), Color(0.15, 0.22, 0.17),
	],
	"ruby": [
		Color(0.40, 0.10, 0.13), Color(0.17, 0.04, 0.05),
		Color(0.72, 0.24, 0.26), Color(0.19, 0.09, 0.09),
	],
	"void": [
		Color(0.13, 0.11, 0.19), Color(0.05, 0.04, 0.08),
		Color(0.40, 0.22, 0.62), Color(0.10, 0.09, 0.14),
	],
	"mythic": [
		Color(0.48, 0.43, 0.20), Color(0.21, 0.18, 0.08),
		Color(0.64, 0.57, 0.28), Color(0.30, 0.24, 0.11),
	],
}


## Which family a biome's loot is made of, for items that name neither a tier nor a material.
const BIOME_FAMILY := {
	"forgotten_castle": "castle",
	"iron_vault": "graysteel",
	"frozen_fortress": "hoarfrost",
	"crystal_caverns": "crystal",
	"poison_swamp": "mirebrass",
	"dark_cathedral": "reliquary",
	"umbral_chapel": "void",
}

## Tokens in an item id that name its material outright. Longest match wins, so "hoarfrost" is
## tested before "frost".
const ID_FAMILY_TOKENS: Array[String] = [
	"hoarfrost", "spellglass", "graysteel", "reliquary", "mirebrass", "cathedral", "crystal",
	"pitiron", "mythic", "castle", "silver", "swamp", "frost", "steel", "ember", "gold", "jade",
	"ruby", "void", "tide", "iron", "mire",
]

const TOKEN_FAMILY := {
	"mire": "swamp",
}

## Tokens in an item id that name its shape. Order matters: the first hit wins.
const ID_SHAPE_TOKENS: Array[String] = [
	"crown", "coronet", "veil", "hood", "cowl", "helm", "cap",
	"cloak", "robe", "cuirass", "plate", "aegis", "mail", "harness",
	"gauntlet", "glove", "greave", "boot", "sabaton",
	"pendant", "amulet", "charm", "censer", "banner", "necklace", "torc", "locket", "ledger",
	"towershield", "kiteshield", "buckler", "shield", "ward", "vigil",
]

const SHAPE_ALIASES := {
	"coronet": "crown",
	"veil": "hood",
	"cowl": "hood",
	"cap": "helm",
	"plate": "cuirass",
	"aegis": "cuirass",
	"mail": "cuirass",
	"harness": "cuirass",
	"robe": "cloak",
	"gauntlet": "gauntlets",
	"glove": "gauntlets",
	"greave": "boots",
	"boot": "boots",
	"sabaton": "boots",
	"amulet": "pendant",
	"charm": "pendant",
	"necklace": "pendant",
	"torc": "pendant",
	"locket": "pendant",
	"ledger": "pendant",
	"censer": "censer",
	"banner": "banner",
	"shield": "kiteshield",
	"ward": "kiteshield",
	"vigil": "kiteshield",
}

## The default shape for a slot, when nothing in the item names one.
const SLOT_DEFAULT_SHAPE := {
	"helmet": "helm",
	"chest": "cuirass",
	"gloves": "gauntlets",
	"boots": "boots",
	"amulet": "pendant",
	"secondary": "kiteshield",
}

## Which body part each slot hangs on, and how the model is fitted to it.
##
## `fit` is the model's bounding box as a multiple of the mount's own box, and `anchor` is the point
## of both boxes that is made to coincide, in [-1, 1] per axis — so a helmet with anchor y = -1 rests
## its brim on the bottom of the head however tall its crest is, and a boot with anchor z = -1 grows
## its toe forwards rather than pushing the ankle back.
const SLOT_MOUNTS := {
	"helmet": {
		"attach": ["Head"],
		"hide": ["Head"],
		"fit": Vector3(1.05, 1.36, 1.06),
		"anchor": Vector3(0.0, -1.0, 0.0),
	},
	"chest": {
		"attach": ["Torso"],
		"hide": [],
		"fit": Vector3(1.48, 0.95, 1.20),
		"anchor": Vector3(0.0, 1.0, 0.0),
	},
	"gloves": {
		"attach": ["ArmR", "ArmL"],
		"hide": [],
		"fit": Vector3(1.25, 0.30, 1.15),
		"anchor": Vector3(0.0, -1.0, 0.0),
	},
	"boots": {
		"attach": ["LegR", "LegL"],
		"hide": [],
		"fit": Vector3(1.30, 0.56, 1.55),
		"anchor": Vector3(0.0, -1.0, -1.0),
	},
	"amulet": {
		"attach": ["Torso"],
		"hide": [],
		"fit": Vector3(0.55, 0.42, 0.09),
		"anchor": Vector3(0.0, 1.0, 1.0),
	},
	# The shield mount is a bare pivot with no geometry of its own, so there is no box to fit a
	# model to. Shields are modelled at true size instead and simply hung off it.
	"secondary": {
		"attach": ["ShieldMount"],
		"hide": [],
		"fit": Vector3.ONE,
		"anchor": Vector3.ZERO,
		"offset": Vector3(0.0, 0.08, 0.04),
	},
}


## How far in front of the torso the neckwear sits, as a multiple of the torso's depth.
##
## The chest slot's own `fit` reaches 0.17 of a torso depth past the front face, so anything less
## than that leaves a pendant buried inside a breastplate. This clears it with room to spare, which
## is what makes a chain read as worn *over* armour rather than embedded in it.
const AMULET_FORWARD := 0.22


## The model for one worn item, or an empty dictionary for a slot that has none.
##
## Rings are deliberately absent: a band a few millimetres across is below the resolution anything
## on this body is drawn at, and at this scale it would only ever be a stray voxel on a knuckle.
static func visual_for(item_id: String, slot: String, def: Dictionary) -> Dictionary:
	if not SLOT_MOUNTS.has(slot):
		return {}
	var mount: Dictionary = SLOT_MOUNTS[slot]
	var shape := _shape_for(item_id, slot, def)
	var family := _family_for(item_id, def)
	var cells := _build_shape(shape)
	if cells.is_empty():
		return {}
	var out := {
		"attach": (mount["attach"] as Array).duplicate(),
		"hide": (mount["hide"] as Array).duplicate(),
		"fit": mount["fit"],
		"anchor": mount["anchor"],
		"mirror_after_first": true,
		"cache_key": "%s|%s" % [item_id, slot],
		"voxels": {
			"edge": EDGE,
			"snapToTheme": false,
			"palette": _palette_arrays(family),
			"cells": cells,
		},
	}
	if mount.has("offset"):
		out["offset"] = mount["offset"]
	if slot == "amulet":
		out["forward"] = AMULET_FORWARD
	if shape == "hood" or shape == "crown":
		# A cowl frames the face and a circlet sits on top of the hair; neither replaces the head.
		out["hide"] = []
	return out


static func _palette_arrays(family: String) -> Array:
	var colors: Array = FAMILIES.get(family, FAMILIES["iron"])
	var out: Array = []
	for entry in colors:
		var c: Color = entry
		out.append([c.r, c.g, c.b])
	return out


static func _family_for(item_id: String, def: Dictionary) -> String:
	var tier := str(def.get("materialTier", ""))
	if FAMILIES.has(tier):
		return tier
	var lower := item_id.to_lower()
	for token in ID_FAMILY_TOKENS:
		if lower.contains(token):
			var mapped := str(TOKEN_FAMILY.get(token, token))
			if FAMILIES.has(mapped):
				return mapped
	var biome := str(def.get("biome", ""))
	if BIOME_FAMILY.has(biome):
		return str(BIOME_FAMILY[biome])
	return "iron"


static func _shape_for(item_id: String, slot: String, def: Dictionary) -> String:
	# The id is read before `baseId`. `baseId` is the generic family an item rolls from — every
	# helmet in the game says "helm" — while the id is where a crown, a veil or a censer says what it
	# actually is, and those are exactly the pieces worth giving their own silhouette.
	var candidates: Array[String] = [item_id.to_lower(), str(def.get("baseId", "")).to_lower()]
	for candidate in candidates:
		if candidate == "":
			continue
		for token in ID_SHAPE_TOKENS:
			if candidate.contains(token):
				var shape := str(SHAPE_ALIASES.get(token, token))
				if _shape_slot(shape) == slot:
					return shape
	return str(SLOT_DEFAULT_SHAPE.get(slot, ""))


## Which slot a shape belongs to, so a "cloak" token in a chest item does not turn a helmet into one.
static func _shape_slot(shape: String) -> String:
	match shape:
		"helm", "crown", "hood":
			return "helmet"
		"cuirass", "cloak":
			return "chest"
		"gauntlets":
			return "gloves"
		"boots":
			return "boots"
		"pendant", "censer", "banner":
			return "amulet"
		"buckler", "kiteshield", "towershield":
			return "secondary"
	return ""


static func _build_shape(shape: String) -> Array:
	var cells: Dictionary = {}
	match shape:
		"helm":
			_helm(cells)
		"crown":
			_crown(cells)
		"hood":
			_hood(cells)
		"cuirass":
			_cuirass(cells)
		"cloak":
			_cloak(cells)
		"gauntlets":
			_gauntlet(cells)
		"boots":
			_boot(cells)
		"pendant":
			_pendant(cells)
		"censer":
			_censer(cells)
		"banner":
			_banner(cells)
		"buckler":
			_buckler(cells)
		"kiteshield":
			_kiteshield(cells)
		"towershield":
			_towershield(cells)
		_:
			return []
	var out: Array = []
	for key in cells:
		var k: Vector3i = key
		out.append([k.x, k.y, k.z, int(cells[key])])
	return out


# --- voxel primitives ---------------------------------------------------------------------------


static func _box(
	cells: Dictionary, x: int, y: int, z: int, sx: int, sy: int, sz: int, mat: int
) -> void:
	for dx in sx:
		for dy in sy:
			for dz in sz:
				cells[Vector3i(x + dx, y + dy, z + dz)] = mat


## A box with its inside carved out, leaving walls one voxel thick. What makes armour armour rather
## than a solid lump — and the top and bottom stay open so a body can pass through it.
static func _shell(
	cells: Dictionary, x: int, y: int, z: int, sx: int, sy: int, sz: int, mat: int
) -> void:
	for dx in sx:
		for dy in sy:
			for dz in sz:
				var on_wall := dx == 0 or dx == sx - 1 or dz == 0 or dz == sz - 1
				if on_wall:
					cells[Vector3i(x + dx, y + dy, z + dz)] = mat


static func _clear(cells: Dictionary, x: int, y: int, z: int, sx: int, sy: int, sz: int) -> void:
	for dx in sx:
		for dy in sy:
			for dz in sz:
				cells.erase(Vector3i(x + dx, y + dy, z + dz))


## Rounds the four vertical corners of a slab off by `bite` voxels, so helmets and pauldrons read as
## domed rather than as cubes.
static func _bevel_corners(
	cells: Dictionary, x: int, y: int, z: int, sx: int, sy: int, sz: int, bite: int
) -> void:
	for dy in sy:
		for i in bite:
			for j in range(bite - i):
				cells.erase(Vector3i(x + i, y + dy, z + j))
				cells.erase(Vector3i(x + sx - 1 - i, y + dy, z + j))
				cells.erase(Vector3i(x + i, y + dy, z + sz - 1 - j))
				cells.erase(Vector3i(x + sx - 1 - i, y + dy, z + sz - 1 - j))


# --- helmets ------------------------------------------------------------------------------------


## A closed helm: domed skull, brow band, a vision slit, a nasal bar and a crest along the crown.
static func _helm(cells: Dictionary) -> void:
	var w := 10
	var d := 10
	# Skull, from the jaw up.
	_box(cells, 0, 0, 0, w, 10, d, MAT_METAL)
	_bevel_corners(cells, 0, 0, 0, w, 10, d, 3)
	# Taper the jaw in, so the helm narrows towards the chin instead of ending in a block.
	_bevel_corners(cells, 0, 0, 0, w, 2, d, 4)
	# Dome the crown.
	_bevel_corners(cells, 0, 8, 0, w, 2, d, 4)
	_clear(cells, 0, 10, 0, w, 1, d)
	_box(cells, 2, 9, 2, 6, 1, 6, MAT_METAL)
	_bevel_corners(cells, 2, 9, 2, 6, 1, 6, 2)
	# Brow band.
	_box(cells, 0, 6, 0, w, 1, d, MAT_DARK)
	_bevel_corners(cells, 0, 6, 0, w, 1, d, 3)
	# Vision slit, cut through the face.
	_clear(cells, 2, 5, d - 1, 6, 1, 1)
	_box(cells, 2, 5, d - 2, 6, 1, 1, MAT_DARK)
	# Nasal bar down the middle of the slit.
	_box(cells, 4, 4, d - 1, 2, 3, 1, MAT_METAL)
	# Breaths, as a short row of dark cells over the mouth.
	_box(cells, 3, 2, d - 1, 1, 2, 1, MAT_DARK)
	_box(cells, 6, 2, d - 1, 1, 2, 1, MAT_DARK)
	# Crest.
	_box(cells, 4, 10, 1, 2, 2, 8, MAT_ACCENT)
	_box(cells, 4, 12, 3, 2, 1, 4, MAT_ACCENT)


## An open circlet with points, worn on the head rather than over it.
static func _crown(cells: Dictionary) -> void:
	var w := 10
	var d := 10
	_shell(cells, 0, 0, 0, w, 3, d, MAT_ACCENT)
	_bevel_corners(cells, 0, 0, 0, w, 3, d, 3)
	# Points: tall at the front and over each temple, short between.
	var points := [
		[4, 4], [1, 3], [7, 3], [0, 1], [w - 1, 1],
	]
	for point in points:
		var px: int = point[0]
		var ph: int = point[1]
		_box(cells, px, 3, d - 2, 2, ph, 2, MAT_ACCENT)
		_box(cells, px, 3, 0, 2, ph, 2, MAT_ACCENT)
	# A stone set at the brow.
	_box(cells, 4, 1, d - 1, 2, 2, 1, MAT_DARK)


## A drawn cowl: a hood shell open at the face, with the fabric gathered at the shoulders.
static func _hood(cells: Dictionary) -> void:
	var w := 12
	var d := 12
	_box(cells, 0, 0, 0, w, 11, d, MAT_CLOTH)
	_bevel_corners(cells, 0, 0, 0, w, 11, d, 4)
	_bevel_corners(cells, 0, 9, 0, w, 2, d, 5)
	# Hollow it out, then open the face.
	_clear(cells, 2, 1, 2, w - 4, 9, d - 4)
	_clear(cells, 3, 1, d - 4, w - 6, 7, 4)
	# A shadowed void where the face would be.
	_box(cells, 3, 2, d - 5, w - 6, 6, 1, MAT_DARK)
	# The mantle over the shoulders.
	_box(cells, 0, 0, 0, w, 2, d, MAT_CLOTH)
	_bevel_corners(cells, 0, 0, 0, w, 2, d, 3)


# --- chest --------------------------------------------------------------------------------------


## A cuirass: breastplate and backplate joined at the sides, a raised collar, pauldrons that flare
## past the shoulders and a skirt of faulds hanging below the belt.
##
## The body of it is narrower than the model's full width — the pauldrons are what reach the edges.
## Sized the other way round the plate came out as wide as the shoulders and swallowed the arms.
static func _cuirass(cells: Dictionary) -> void:
	var w := 14
	var d := 10
	var h := 16
	var bx := 2
	var bw := w - 4
	# The body of the cuirass.
	_shell(cells, bx, 4, 0, bw, 12, d, MAT_METAL)
	_bevel_corners(cells, bx, 4, 0, bw, 12, d, 2)
	# Taper the waist in.
	_bevel_corners(cells, bx, 4, 0, bw, 3, d, 3)
	# Belt.
	_box(cells, bx, 4, 0, bw, 1, d, MAT_CLOTH)
	_bevel_corners(cells, bx, 4, 0, bw, 1, d, 3)
	# Faulds: hanging plates front and back, with a gap at the hips so the legs still swing.
	_box(cells, bx + 1, 1, 0, bw - 2, 3, 1, MAT_METAL)
	_box(cells, bx + 1, 1, d - 1, bw - 2, 3, 1, MAT_METAL)
	_box(cells, bx + 2, 0, 0, bw - 4, 1, 1, MAT_METAL)
	_box(cells, bx + 2, 0, d - 1, bw - 4, 1, 1, MAT_METAL)
	# A ridge down the breastplate, which is what keeps the front from reading as a flat panel.
	_box(cells, 6, 6, d - 1, 2, 9, 1, MAT_DARK)
	# Collar.
	_box(cells, bx + 1, h - 1, 1, bw - 2, 1, d - 2, MAT_DARK)
	_bevel_corners(cells, bx + 1, h - 1, 1, bw - 2, 1, d - 2, 2)
	# Pauldrons.
	#
	# Stepped down towards the arm rather than squared off: a full-height slab out to the edge reads
	# as a yoke across the shoulders, and a bright trim along the top of it reads as a shelf.
	for left in [true, false]:
		for i in 3:
			var sx := (2 - i) if left else (w - 3 + i)
			_box(cells, sx, h - 4 - i, 2, 1, 3, d - 4, MAT_METAL)
		var rivet := 0 if left else w - 1
		_box(cells, rivet, h - 5, 3, 1, 1, d - 6, MAT_ACCENT)


## A cloak: a shoulder mantle with a clasp, and a drape falling down the back.
static func _cloak(cells: Dictionary) -> void:
	var w := 14
	var d := 10
	var h := 16
	var bx := 3
	var bw := w - 6
	# The garment under it, so a cloak still covers a chest.
	_shell(cells, bx, 3, 1, bw, 12, d - 2, MAT_DARK)
	_bevel_corners(cells, bx, 3, 1, bw, 12, d - 2, 2)
	_box(cells, bx, 4, 1, bw, 1, d - 2, MAT_CLOTH)
	# Mantle over the shoulders.
	_box(cells, 0, h - 4, 0, w, 4, d, MAT_CLOTH)
	_bevel_corners(cells, 0, h - 4, 0, w, 4, d, 3)
	_clear(cells, 4, h - 4, d - 2, w - 8, 3, 2)
	# The drape down the back. Tapered and seamed rather than one flat panel, which from behind is
	# a board rather than cloth.
	for y in range(0, h - 4):
		var pinch := 1 if y > h - 9 else 0
		_box(cells, 2 + pinch, y, 0, w - 4 - pinch * 2, 1, 1, MAT_CLOTH)
	_box(cells, 6, 0, 0, 2, h - 6, 1, MAT_DARK)
	# The hem, a little wider than the fall above it.
	_box(cells, 1, 0, 0, w - 2, 2, 1, MAT_CLOTH)
	# Clasp at the throat.
	_box(cells, 6, h - 3, d - 1, 2, 2, 1, MAT_ACCENT)


# --- hands and feet -----------------------------------------------------------------------------


## A gauntlet: a flared cuff up the forearm, knuckle plates and a thumb.
static func _gauntlet(cells: Dictionary) -> void:
	var w := 7
	var d := 7
	# Cuff, flared where it meets the forearm.
	_box(cells, 0, 6, 0, w, 3, d, MAT_METAL)
	_bevel_corners(cells, 0, 6, 0, w, 3, d, 2)
	_box(cells, 1, 5, 1, w - 2, 1, d - 2, MAT_DARK)
	# The hand itself.
	_box(cells, 1, 0, 1, w - 2, 5, d - 2, MAT_METAL)
	_bevel_corners(cells, 1, 0, 1, w - 2, 5, d - 2, 2)
	# Knuckle plates across the back of the hand.
	_box(cells, 1, 3, 1, w - 2, 1, d - 2, MAT_ACCENT)
	# Thumb, on the +X side so the mirrored copy puts it on the inside of both hands.
	_box(cells, w - 1, 1, 2, 1, 3, 2, MAT_METAL)


## A boot: a sole and toe running forward, an ankle, and a shin greave with a knee cop.
##
## The shin is deliberately shallower than the foot — a greave that is as deep as the toe reads as a
## stack of plates rather than as a leg in a boot.
static func _boot(cells: Dictionary) -> void:
	var w := 7
	var d := 12
	# Sole and toe.
	_box(cells, 0, 0, 0, w, 2, d, MAT_DARK)
	_bevel_corners(cells, 0, 0, 0, w, 2, d, 2)
	# The foot, capped short of the toe.
	_box(cells, 0, 2, 0, w, 3, d - 3, MAT_METAL)
	_bevel_corners(cells, 0, 2, 0, w, 3, d - 3, 2)
	# Ankle and shin, narrower and shallower than the foot.
	_box(cells, 1, 5, 1, w - 2, 8, 5, MAT_METAL)
	_bevel_corners(cells, 1, 5, 1, w - 2, 8, 5, 1)
	# Knee cop.
	_box(cells, 1, 11, 2, w - 2, 2, 4, MAT_METAL)
	_bevel_corners(cells, 1, 11, 2, w - 2, 2, 4, 1)
	# A strap across the shin.
	_box(cells, 1, 8, 1, w - 2, 1, 5, MAT_CLOTH)
	# Toe cap.
	_box(cells, 1, 2, d - 2, w - 2, 1, 2, MAT_ACCENT)


# --- neckwear -----------------------------------------------------------------------------------


## A pendant: a chain over both shoulders meeting in a V, with a stone hanging at the point.
static func _pendant(cells: Dictionary) -> void:
	var w := 13
	# The chain, stepping down from each shoulder to the middle of the chest.
	for i in 5:
		_box(cells, i, 10 - i * 2, 0, 1, 2, 1, MAT_ACCENT)
		_box(cells, w - 1 - i, 10 - i * 2, 0, 1, 2, 1, MAT_ACCENT)
	_box(cells, 5, 2, 0, 3, 1, 1, MAT_ACCENT)
	# Setting and stone.
	_box(cells, 5, 0, 0, 3, 2, 1, MAT_ACCENT)
	_box(cells, 5, 0, 1, 3, 2, 1, MAT_DARK)
	_box(cells, 6, 0, 1, 1, 1, 1, MAT_ACCENT)


## A censer: a chain and a pierced burner swinging from it.
static func _censer(cells: Dictionary) -> void:
	var w := 13
	for i in 5:
		_box(cells, i, 11 - i * 2, 0, 1, 2, 1, MAT_ACCENT)
		_box(cells, w - 1 - i, 11 - i * 2, 0, 1, 2, 1, MAT_ACCENT)
	_box(cells, 5, 3, 0, 3, 1, 1, MAT_ACCENT)
	# The burner.
	_box(cells, 4, 0, 0, 5, 3, 2, MAT_ACCENT)
	_bevel_corners(cells, 4, 0, 0, 5, 3, 2, 1)
	_box(cells, 5, 1, 1, 3, 1, 1, MAT_DARK)
	_box(cells, 6, 3, 0, 1, 1, 1, MAT_DARK)


## A banner: a short staff across the back of the shoulders with a pennant hanging from it.
static func _banner(cells: Dictionary) -> void:
	var w := 12
	_box(cells, 0, 11, 0, w, 1, 1, MAT_DARK)
	_box(cells, 1, 2, 0, w - 2, 9, 1, MAT_CLOTH)
	# Swallow-tail.
	_box(cells, 1, 0, 0, 3, 2, 1, MAT_CLOTH)
	_box(cells, w - 4, 0, 0, 3, 2, 1, MAT_CLOTH)
	# A charge in the middle of the field.
	_box(cells, 5, 5, 1, 2, 3, 1, MAT_ACCENT)
	_box(cells, 4, 6, 1, 4, 1, 1, MAT_ACCENT)


# --- shields ------------------------------------------------------------------------------------


## A buckler: a small round shield with a domed boss in the middle.
static func _buckler(cells: Dictionary) -> void:
	var r := 5
	var size := r * 2 + 1
	for x in size:
		for y in size:
			var dx := x - r
			var dy := y - r
			if dx * dx + dy * dy > r * r:
				continue
			var rim := dx * dx + dy * dy > (r - 1) * (r - 1)
			_box(cells, x, y, 0, 1, 1, 2, MAT_DARK if rim else MAT_METAL)
	# Boss.
	_box(cells, r - 1, r - 1, 2, 3, 3, 1, MAT_ACCENT)
	_box(cells, r, r, 3, 1, 1, 1, MAT_ACCENT)


## A kite shield: square at the shoulder, tapering to a point at the foot, with a boss and a band.
static func _kiteshield(cells: Dictionary) -> void:
	var w := 9
	var h := 15
	for y in h:
		# The taper starts two thirds of the way down and closes to a point.
		var inset := 0
		if y < 6:
			@warning_ignore("integer_division")
			inset = (6 - y) * 2 / 3
		var x0 := inset
		var x1 := w - inset
		if x1 - x0 < 1:
			continue
		for x in range(x0, x1):
			var edge := x == x0 or x == x1 - 1 or y == h - 1
			_box(cells, x, y, 0, 1, 1, 2, MAT_DARK if edge else MAT_METAL)
	# Boss and the band it sits on.
	_box(cells, 1, 9, 2, w - 2, 1, 1, MAT_ACCENT)
	_box(cells, 3, 8, 2, 3, 3, 1, MAT_ACCENT)
	_box(cells, 4, 9, 3, 1, 1, 1, MAT_DARK)


## A tower shield: a tall rectangle with a rolled top edge and a central rib.
static func _towershield(cells: Dictionary) -> void:
	var w := 10
	var h := 18
	_box(cells, 0, 0, 0, w, h, 2, MAT_METAL)
	_bevel_corners(cells, 0, 0, 0, w, 2, 2, 2)
	_bevel_corners(cells, 0, h - 2, 0, w, 2, 2, 2)
	# Edging.
	_box(cells, 0, 0, 0, 1, h, 2, MAT_DARK)
	_box(cells, w - 1, 0, 0, 1, h, 2, MAT_DARK)
	_box(cells, 0, h - 1, 0, w, 1, 2, MAT_DARK)
	# Central rib and a boss.
	_box(cells, 4, 1, 2, 2, h - 2, 1, MAT_ACCENT)
	_box(cells, 3, 9, 2, 4, 3, 1, MAT_ACCENT)
