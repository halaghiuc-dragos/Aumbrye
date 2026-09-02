extends Node3D

## The wizard's portal. It opens beside the cresset at every intermission from
## `cashOutFromWave` on, and it is the only way to take anything out of the Vigil before wave 50.
##
## The offer is deliberately cruel: one item, chosen, and the run ends there. Everything else the
## player is carrying is left behind. That single decision — bank the good sword now, or push for
## ten more waves and risk the lot — is the whole reason the mode has a separate loadout.

const PixelStyle := preload("res://scripts/art/style/pixel_diorama_style.gd")
const InputGlyphServiceScript := preload("res://scripts/ui/input_glyph_service.gd")

const DISPLAY_NAME := "The Summoner"
const PORTAL_POSITION := Vector3(-9.5, 0.0, 0.0)
const PORTAL_TINT := Color(0.62, 0.42, 0.95)

var _label: Label3D
var _player: Node3D
var _run: Node
var _phase := 0.0
var _glow: Node3D


func setup(run: Node) -> void:
	_run = run
	position = PORTAL_POSITION
	_build_visual()
	_build_zone()
	_build_label()


func _build_visual() -> void:
	var theme := PixelStyle.theme_from_biome(BiomeRegistry.BIOME_UMBRAL)
	var stone := PixelStyle.make_wall_material(theme)
	var robe := PixelStyle.make_metal_material(Color(0.19, 0.16, 0.28), 0.2)
	var root := Node3D.new()
	root.name = "Visual"
	add_child(root)

	# Arch.
	PixelStyle.add_box(root, Vector3(3.4, 0.3, 1.4), Vector3(0.0, 0.15, 0.0), stone, "Base")
	PixelStyle.add_box(root, Vector3(0.5, 3.6, 0.7), Vector3(-1.35, 1.9, 0.0), stone, "PillarL")
	PixelStyle.add_box(root, Vector3(0.5, 3.6, 0.7), Vector3(1.35, 1.9, 0.0), stone, "PillarR")
	PixelStyle.add_box(root, Vector3(3.2, 0.5, 0.7), Vector3(0.0, 3.9, 0.0), stone, "Lintel")

	_glow = Node3D.new()
	_glow.name = "PortalGlow"
	root.add_child(_glow)
	var sheet := PixelStyle.make_custom_emissive(PORTAL_TINT, 2.2)
	PixelStyle.add_box(_glow, Vector3(2.3, 3.3, 0.14), Vector3(0.0, 1.95, 0.0), sheet, "Sheet")
	var light := OmniLight3D.new()
	light.name = "PortalLight"
	light.light_color = PORTAL_TINT
	light.light_energy = 2.6
	light.omni_range = 16.0
	light.shadow_enabled = false
	light.position = Vector3(0.0, 2.0, 0.0)
	_glow.add_child(light)

	# The summoner, standing just off the threshold.
	var wizard := Node3D.new()
	wizard.name = "Summoner"
	wizard.position = Vector3(1.9, 0.0, 0.6)
	root.add_child(wizard)
	PixelStyle.add_box(wizard, Vector3(0.7, 1.15, 0.55), Vector3(0.0, 0.58, 0.0), robe, "Robe")
	PixelStyle.add_box(wizard, Vector3(0.5, 0.42, 0.45), Vector3(0.0, 1.36, 0.0), robe, "Cowl")
	PixelStyle.add_box(
		wizard,
		Vector3(0.1, 1.9, 0.1),
		Vector3(0.42, 0.95, 0.0),
		PixelStyle.make_metal_material(Color(0.32, 0.27, 0.2), 0.3),
		"Staff"
	)
	PixelStyle.add_box(
		wizard,
		Vector3(0.22, 0.22, 0.22),
		Vector3(0.42, 1.98, 0.0),
		PixelStyle.make_custom_emissive(Color(0.85, 0.72, 1.0), 2.8),
		"StaffLight"
	)


func _build_zone() -> void:
	var area := Area3D.new()
	area.name = "InteractArea"
	area.collision_layer = 0
	area.collision_mask = 2
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(5.0, 3.5, 4.0)
	shape.shape = box
	shape.position = Vector3(0.0, 1.75, 0.0)
	area.add_child(shape)
	add_child(area)
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)


func _build_label() -> void:
	_label = Label3D.new()
	_label.name = "NameLabel"
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 20
	_label.outline_size = 9
	_label.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	_label.position = Vector3(0.0, 4.4, 0.0)
	_label.visible = false
	add_child(_label)


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	_player = body
	_refresh_label()


func _on_body_exited(body: Node3D) -> void:
	if body != _player:
		return
	_player = null
	if _label:
		_label.visible = false


func _refresh_label() -> void:
	if _label == null or not is_instance_valid(_label):
		return
	if _player == null:
		_label.visible = false
		return
	_label.visible = true
	_label.text = "%s — leave with one thing (%s)" % [DISPLAY_NAME, _interact_glyph()]


static func _interact_glyph() -> String:
	var glyph := InputGlyphServiceScript.get_action_glyph("interact")
	return glyph if glyph != "" else "E"


func _unhandled_input(event: InputEvent) -> void:
	if _player == null:
		return
	if not PlayerInput.interact_just_pressed(event):
		return
	get_viewport().set_input_as_handled()
	AudioDirector.play_sfx("ui_interact_near", global_position)
	if _run and is_instance_valid(_run) and _run.has_method("open_cash_out_picker"):
		_run.call("open_cash_out_picker")


func _process(delta: float) -> void:
	if _glow == null or not is_instance_valid(_glow):
		return
	_phase += delta
	var breathe := 1.0 + sin(_phase * 1.7) * 0.04
	_glow.scale = Vector3(breathe, 1.0, 1.0)
