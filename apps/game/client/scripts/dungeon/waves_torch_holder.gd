extends Node3D


const DioramaSkin := preload("res://scripts/art/props/diorama_interactable_skin.gd")
const PixelStyle := preload("res://scripts/art/style/pixel_diorama_style.gd")
const InputGlyphServiceScript := preload("res://scripts/ui/input_glyph_service.gd")

const DISPLAY_NAME := "Cresset"

var _label: Label3D
var _player: Node3D
var _flame: Node3D
var _flame_light: OmniLight3D
var _lit := false
var _phase := 0.0


func _ready() -> void:
	name = "WavesTorchHolder"
	_build_visual()
	_build_zone()
	_label = Label3D.new()
	_label.name = "NameLabel"
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 20
	_label.position = Vector3(0.0, 2.35, 0.0)
	_label.visible = false
	add_child(_label)
	if WavesRunService and not WavesRunService.waves_changed.is_connected(_refresh_label):
		WavesRunService.waves_changed.connect(_refresh_label)
	if WavesRunService and not WavesRunService.inventory_changed.is_connected(_refresh_label):
		WavesRunService.inventory_changed.connect(_refresh_label)
	set_lit(WavesRunService.torch_placed if WavesRunService else false)


func _exit_tree() -> void:
	if WavesRunService == null:
		return
	if WavesRunService.waves_changed.is_connected(_refresh_label):
		WavesRunService.waves_changed.disconnect(_refresh_label)
	if WavesRunService.inventory_changed.is_connected(_refresh_label):
		WavesRunService.inventory_changed.disconnect(_refresh_label)


func _build_visual() -> void:
	var theme := PixelStyle.theme_from_biome(BiomeRegistry.BIOME_UMBRAL)
	var stone := PixelStyle.make_wall_material(theme)
	var iron := PixelStyle.make_metal_material(Color(0.23, 0.22, 0.26), 0.34)
	var root := Node3D.new()
	root.name = "Visual"
	add_child(root)
	PixelStyle.add_box(root, Vector3(2.6, 0.22, 2.6), Vector3(0.0, 0.11, 0.0), stone, "PlinthLower")
	PixelStyle.add_box(root, Vector3(2.0, 0.2, 2.0), Vector3(0.0, 0.32, 0.0), stone, "PlinthUpper")
	PixelStyle.add_box(root, Vector3(1.5, 0.14, 1.5), Vector3(0.0, 0.49, 0.0), iron, "PlinthCap")
	PixelStyle.add_box(root, Vector3(0.26, 1.1, 0.26), Vector3(0.0, 1.05, 0.0), iron, "Stem")
	for i in 3:
		var angle := TAU * float(i) / 3.0
		var brace := PixelStyle.add_box(
			root,
			Vector3(0.12, 0.8, 0.12),
			Vector3(cos(angle) * 0.34, 0.9, sin(angle) * 0.34),
			iron,
			"Brace%d" % i
		)
		brace.rotation.z = cos(angle) * 0.3
		brace.rotation.x = -sin(angle) * 0.3
	PixelStyle.add_box(root, Vector3(1.05, 0.34, 1.05), Vector3(0.0, 1.72, 0.0), iron, "Bowl")
	PixelStyle.add_box(root, Vector3(1.25, 0.1, 1.25), Vector3(0.0, 1.92, 0.0), iron, "BowlRim")

	_flame = Node3D.new()
	_flame.name = "Flame"
	_flame.position = Vector3(0.0, 1.98, 0.0)
	_flame.visible = false
	root.add_child(_flame)
	var ember := PixelStyle.make_custom_emissive(Color(0.95, 0.36, 0.12), 2.0)
	var core := PixelStyle.make_custom_emissive(Color(1.0, 0.62, 0.20), 2.4)
	var tip := PixelStyle.make_custom_emissive(Color(1.0, 0.86, 0.46), 2.8)
	PixelStyle.add_box(_flame, Vector3(0.62, 0.18, 0.62), Vector3(0.0, 0.04, 0.0), ember, "Embers")
	PixelStyle.add_box(_flame, Vector3(0.46, 0.34, 0.46), Vector3(0.0, 0.26, 0.0), core, "FlameLow")
	PixelStyle.add_box(_flame, Vector3(0.3, 0.28, 0.3), Vector3(0.06, 0.54, -0.03), core, "FlameMid")
	PixelStyle.add_box(_flame, Vector3(0.16, 0.22, 0.16), Vector3(-0.04, 0.76, 0.04), tip, "FlameTip")
	_flame_light = OmniLight3D.new()
	_flame_light.name = "FlameLight"
	_flame_light.light_color = Color(1.0, 0.68, 0.32)
	_flame_light.light_energy = 3.2
	_flame_light.omni_range = 22.0
	_flame_light.shadow_enabled = false
	_flame_light.position = Vector3(0.0, 0.7, 0.0)
	_flame.add_child(_flame_light)
	LightEmbers.attach(_flame, Vector3(0.0, 0.5, 0.0), _flame_light.light_color, 3.0, 1.8)


func _build_zone() -> void:
	var area := Area3D.new()
	area.name = "InteractArea"
	area.collision_layer = 0
	area.collision_mask = 2
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.0, 3.0, 4.0)
	shape.shape = box
	shape.position = Vector3(0.0, 1.5, 0.0)
	area.add_child(shape)
	add_child(area)
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)


func set_lit(lit: bool) -> void:
	_lit = lit
	if _flame:
		_flame.visible = lit
	_refresh_label()


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
	if _player == null or _lit:
		_label.visible = false
		return
	_label.visible = true
	if WavesRunService.has_torch():
		_label.text = "%s (%s)" % [DISPLAY_NAME, _interact_glyph()]
	else:
		_label.text = "%s — no torch" % DISPLAY_NAME


static func _interact_glyph() -> String:
	var glyph := InputGlyphServiceScript.get_action_glyph("interact")
	return glyph if glyph != "" else "E"


func _unhandled_input(event: InputEvent) -> void:
	if _lit or _player == null:
		return
	if not PlayerInput.interact_just_pressed(event):
		return
	if not WavesRunService.has_torch():
		return
	get_viewport().set_input_as_handled()
	var run := get_tree().get_first_node_in_group("waves_run")
	if run and run.has_method("light_cresset"):
		run.call("light_cresset")


func _process(delta: float) -> void:
	if not _lit or _flame == null or not is_instance_valid(_flame):
		return
	_phase += delta
	var flicker := 0.9 + sin(_phase * 9.0) * 0.06 + sin(_phase * 23.0) * 0.03
	_flame.scale = Vector3(flicker, 1.0 + (flicker - 0.9) * 1.6, flicker)
	if _flame_light and is_instance_valid(_flame_light):
		_flame_light.light_energy = 3.2 * flicker
