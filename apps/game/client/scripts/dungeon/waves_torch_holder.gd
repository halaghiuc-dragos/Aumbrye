extends Node3D


const InputGlyphServiceScript := preload("res://scripts/ui/input_glyph_service.gd")

const DISPLAY_NAME := "Cresset"
const INTERACT_RANGE := 3.0

var _label: Label3D
var _selected := false
var _flame: Node3D
var _flame_light: OmniLight3D
var _lit := false
var _phase := 0.0


func _ready() -> void:
	name = "WavesTorchHolder"
	_build_visual()
	_label = Label3D.new()
	_label.name = "NameLabel"
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 20
	_label.outline_size = 9
	_label.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	_label.position = Vector3(0.0, 2.35, 0.0)
	_label.visible = false
	add_child(_label)
	DungeonInteractionService.register_candidate(
		self,
		self,
		INTERACT_RANGE,
		3,
		Callable(self, "_interact"),
		Callable(),
		Callable(self, "_set_selected_prompt")
	)
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
	var root := Node3D.new()
	root.name = "Visual"
	add_child(root)
	PropLibrary.attach(root, "waves/cresset_body", BiomeRegistry.BIOME_UMBRAL)

	_flame = Node3D.new()
	_flame.name = "Flame"
	_flame.position = Vector3(0.0, 1.96, 0.0)
	_flame.visible = false
	root.add_child(_flame)
	PropLibrary.attach(_flame, "waves/cresset_flame", BiomeRegistry.BIOME_UMBRAL)
	_flame_light = OmniLight3D.new()
	_flame_light.name = "FlameLight"
	_flame_light.light_color = Color(1.0, 0.68, 0.32)
	_flame_light.light_energy = 3.2
	_flame_light.omni_range = 22.0
	_flame_light.shadow_enabled = false
	_flame_light.position = Vector3(0.0, 0.7, 0.0)
	_flame.add_child(_flame_light)
	LightEmbers.attach(_flame, Vector3(0.0, 0.5, 0.0), _flame_light.light_color, 3.0, 1.8)


func set_lit(lit: bool) -> void:
	_lit = lit
	if _flame:
		_flame.visible = lit
	_refresh_label()


func _set_selected_prompt(active: bool) -> void:
	_selected = active
	_refresh_label()


func _refresh_label() -> void:
	if _label == null or not is_instance_valid(_label):
		return
	if not _selected:
		_label.visible = false
		return
	# First lobby: the cresset is dark and wants the torch buried in one of the caches.
	# Later intermissions: it is already burning, and the interaction calls the next wave.
	if WavesRunService.is_first_lobby():
		if _lit:
			_label.visible = false
			return
		_label.visible = true
		if WavesRunService.has_torch():
			_label.text = "%s (%s)" % [DISPLAY_NAME, _interact_glyph()]
		else:
			_label.text = "%s — no torch" % DISPLAY_NAME
		return
	if not WavesRunService.prep_active:
		_label.visible = false
		return
	_label.visible = true
	_label.text = (
		"Call wave %d (%s)" % [WavesRunService.current_wave + 1, _interact_glyph()]
	)


static func _interact_glyph() -> String:
	var glyph := InputGlyphServiceScript.get_action_glyph("interact")
	return glyph if glyph != "" else "E"


func _interact() -> void:
	if WavesRunService.is_first_lobby():
		if _lit or not WavesRunService.has_torch():
			return
	elif not WavesRunService.prep_active:
		return
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
