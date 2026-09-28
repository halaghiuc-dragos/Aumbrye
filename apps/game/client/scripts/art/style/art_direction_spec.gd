## Central, validated presentation baseline for the pixel diorama.
## This deliberately checks authored numeric contracts only; a rendered motion review remains a
## separate acceptance activity and must not be inferred from this source-level contract.
class_name ArtDirectionSpec
extends RefCounted


const SPEC_PATH := "content/art/readability_spec.json"
const PaletteStyle := preload("res://scripts/art/style/pixel_diorama_style.gd")
const PixelSettings := preload("res://scripts/art/pipeline/pixel_diorama_settings.gd")
const VisualLightingScript := preload("res://scripts/art/lighting/visual_lighting.gd")
const AccessibilitySettingsScript := preload("res://scripts/accessibility/accessibility_settings.gd")
const OrbitCameraScript := preload("res://scripts/camera/orbit_camera.gd")


static func load_spec() -> Dictionary:
	return ContentLoader.load_json(SPEC_PATH)


static func validate_authored_contract() -> PackedStringArray:
	var failures := PackedStringArray()
	var spec := load_spec()
	if spec.is_empty():
		failures.append("missing art readability specification")
		return failures
	var camera: Dictionary = spec.get("reference_camera", {})
	var target: Array = camera.get("default_render_size", [])
	if target.size() != 2:
		failures.append("reference camera render size is invalid")
	elif PixelSettings.DEFAULT_VIEWPORT_WIDTH != int(target[0]) or PixelSettings.DEFAULT_VIEWPORT_HEIGHT != int(target[1]):
		failures.append("pixel render target differs from the authored reference camera")
	if not is_equal_approx(AccessibilitySettingsScript.CAMERA_FOV_DEFAULT, float(camera.get("third_person_fov", -1.0))):
		failures.append("third-person FOV differs from the authored reference camera")
	var zoom: Array = camera.get("third_person_zoom", [])
	if zoom.size() != 2 or not is_equal_approx(OrbitCameraScript.MIN_ZOOM, float(zoom[0])) or not is_equal_approx(OrbitCameraScript.MAX_ZOOM, float(zoom[1])):
		failures.append("third-person zoom limits differ from the authored reference camera")
	var scale: Dictionary = spec.get("character_scale", {})
	if not is_equal_approx(PaletteStyle.WORLD_PIXEL, float(scale.get("world_pixel", -1.0))):
		failures.append("voxel world pixel differs from the authored character scale")
	_validate_outlines(spec.get("outline", {}), failures)
	_validate_palettes(spec.get("palette_roles", {}), failures)
	_validate_lighting(spec.get("lighting", {}), failures)
	return failures


static func _validate_outlines(contract: Dictionary, failures: PackedStringArray) -> void:
	var thickness: Array = contract.get("thickness_px", [])
	var strength: Array = contract.get("strength", [])
	var interior: Array = contract.get("interior_scale", [])
	if not _in_range(PixelSettings.DEFAULT_OUTLINE_THICKNESS, thickness):
		failures.append("default outline thickness is outside the authored readability range")
	if not _in_range(PixelSettings.DEFAULT_OUTLINE_STRENGTH, strength):
		failures.append("default outline strength is outside the authored readability range")
	if not _in_range(PixelSettings.DEFAULT_OUTLINE_INTERIOR, interior):
		failures.append("default outline interior scale is outside the authored readability range")


static func _validate_palettes(contract: Dictionary, failures: PackedStringArray) -> void:
	var palettes: Dictionary = ContentLoader.load_json(PaletteStyle.PALETTE_JSON_PATH).get("palettes", {})
	var surface_delta := float(contract.get("min_surface_value_delta", 0.0))
	var accent_delta := float(contract.get("min_accent_shadow_value_delta", 0.0))
	var emissive_min := float(contract.get("min_emissive_value", 0.0))
	for theme_id in PaletteStyle.THEME_IDS:
		var palette: Dictionary = palettes.get(theme_id, {})
		if palette.is_empty():
			failures.append("%s palette is missing" % theme_id)
			continue
		var floor_base := Color.html(str(palette.get("floor_base", "#000000"))).get_luminance()
		var floor_shadow := Color.html(str(palette.get("floor_shadow", "#000000"))).get_luminance()
		var wall_base := Color.html(str(palette.get("wall_base", "#000000"))).get_luminance()
		var wall_shadow := Color.html(str(palette.get("wall_shadow", "#000000"))).get_luminance()
		if absf(floor_base - floor_shadow) < surface_delta or absf(wall_base - wall_shadow) < surface_delta:
			failures.append("%s palette lacks the authored surface/shadow separation" % theme_id)
		if absf(Color.html(str(palette.get("accent", "#000000"))).get_luminance() - minf(floor_shadow, wall_shadow)) < accent_delta:
			failures.append("%s palette accent is too close to its shadow role" % theme_id)
		var emissive := Color.html(str(palette.get("emissive", "#000000")))
		# Saturated blue/green lights can have a low physical luminance while still being a
		# deliberately readable pixel accent. The authored role is their peak channel, not a
		# photometric brightness claim.
		if maxf(emissive.r, maxf(emissive.g, emissive.b)) < emissive_min:
			failures.append("%s palette emissive role is too dim" % theme_id)


static func _validate_lighting(contract: Dictionary, failures: PackedStringArray) -> void:
	var profiles: Dictionary = ContentLoader.load_json(VisualLightingScript.LIGHTING_DATA_PATH).get("profiles", {})
	var range_contract: Array = contract.get("torch_range", [])
	var energy_contract: Array = contract.get("torch_energy", [])
	var ambient_contract: Array = contract.get("ambient_energy", [])
	for profile_id in profiles:
		var profile: Dictionary = profiles[profile_id]
		var torch: Dictionary = profile.get("torch", {})
		if not torch.is_empty():
			if not _in_range(float(torch.get("range", VisualLightingScript.TORCH_OMNI_RANGE)), range_contract):
				failures.append("%s torch range is outside the authored readability range" % profile_id)
			if not _in_range(float(torch.get("energy", VisualLightingScript.TORCH_OMNI_ENERGY)), energy_contract):
				failures.append("%s torch energy is outside the authored readability range" % profile_id)
		var ambient: Dictionary = profile.get("ambient", {})
		if not ambient.is_empty() and not _in_range(float(ambient.get("energy", 0.0)), ambient_contract):
			failures.append("%s ambient energy is outside the authored readability range" % profile_id)


static func _in_range(value: float, allowed_range: Array) -> bool:
	return (
		allowed_range.size() == 2
		and value >= float(allowed_range[0])
		and value <= float(allowed_range[1])
	)
