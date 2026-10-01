class_name DioramaEquipmentKit
extends RefCounted

## Blender-built models for worn equipment (tools/blender/equipment.py).
##
## There are around eighty wearable pieces across five slots, which is too many to model one by one
## and far too many to keep in step with the item catalogue. Instead each piece resolves to a *shape*
## (what kind of thing it is: a helm, a crown, a cowl, a cuirass, a cloak…) and a *family* (what it
## is made of: pit iron, hoarfrost, spellglass…). The shape carries the silhouette, the family
## carries the colour, and every item in the catalogue gets a model that reads as itself.
##
## Models are fitted to whatever body part they hang on by their bounding box, so they do not depend
## on any one rig's proportions. The character faces +Z.

## Every shape that has a model in `assets/equipment/`.
const SHAPES: Array[String] = [
	"helm", "crown", "hood", "cuirass", "cloak", "buckler", "kiteshield", "towershield",
]

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
	"shield": "kiteshield",
	"ward": "kiteshield",
	"vigil": "kiteshield",
}

## The default shape for a slot, when nothing in the item names one.
const SLOT_DEFAULT_SHAPE := {
	"helmet": "helm",
	"chest": "cuirass",
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


## Shapes that do not fit the way their slot's default does. A circlet sits on top of the head
## instead of enclosing it, so it is a low band resting on the crown.
const SHAPE_MOUNT_OVERRIDES := {
	"crown": {"fit": Vector3(1.06, 0.42, 1.06), "anchor": Vector3(0.0, 1.0, 0.0)},
}


## How far in front of the torso the neckwear sits, as a multiple of the torso's depth.
##
## The chest slot's own `fit` reaches 0.17 of a torso depth past the front face, so anything less
## than that leaves a pendant buried inside a breastplate. This clears it with room to spare, which
## is what makes a chain read as worn *over* armour rather than embedded in it.


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
	if not SHAPES.has(shape):
		return {}
	var out := {
		"attach": (mount["attach"] as Array).duplicate(),
		"hide": (mount["hide"] as Array).duplicate(),
		"fit": mount["fit"],
		"anchor": mount["anchor"],
		"mirror_after_first": true,
		"cache_key": "%s|%s" % [item_id, slot],
		"mesh": "res://assets/equipment/%s.glb" % shape,
		"palette": _palette_arrays(family),
	}
	if SHAPE_MOUNT_OVERRIDES.has(shape):
		for key in SHAPE_MOUNT_OVERRIDES[shape]:
			out[key] = SHAPE_MOUNT_OVERRIDES[shape][key]
	if mount.has("offset"):
		out["offset"] = mount["offset"]
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
		"buckler", "kiteshield", "towershield":
			return "secondary"
	return ""
