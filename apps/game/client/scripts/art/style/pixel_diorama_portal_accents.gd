extends RefCounted
class_name PixelDioramaPortalAccents

## Portal trim, by the ids a portal definition lists. Each accent is a Blender model; the portal's
## material set colours it (see tools/blender/props_portals.py for the roles).

const KNOWN_ACCENTS: Array[String] = [
	"torch_pair", "rune_ring", "training_torches", "dragon_horns", "cathedral_trim",
]


static func add_accents(visuals: Node3D, mats: Dictionary, def: Dictionary) -> void:
	var accent_material: Material = mats.accent
	var overrides := {"accent": accent_material}
	for role in ["umbral", "training", "dragon", "cathedral"]:
		overrides[role] = mats.get(role, accent_material)
	overrides["forge"] = mats.get("forge", overrides["dragon"])
	for accent_id in def.get("accents", []):
		if not KNOWN_ACCENTS.has(str(accent_id)):
			continue
		var holder := Node3D.new()
		holder.name = "Accent_%s" % str(accent_id)
		visuals.add_child(holder)
		PropLibrary.attach_themed(
			holder, "portal_accent_%s" % str(accent_id), PixelDioramaStyle.PaletteTheme.CASTLE,
			{"materials": overrides}
		)
