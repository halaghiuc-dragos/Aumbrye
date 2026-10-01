extends Node3D

## The wizard's portal. It opens beside the cresset at every intermission from
## `cashOutFromWave` on, and it is the only way to take anything out of the Vigil before wave 50.
##
## The offer grows with the reached milestone, and the run ends when it is accepted. Everything
## else the player is carrying is left behind.

const InputGlyphServiceScript := preload("res://scripts/ui/input_glyph_service.gd")

const DISPLAY_NAME := "The Summoner"
const INTERACT_RANGE := 3.4
const PORTAL_POSITION := Vector3(-9.5, 0.0, 0.0)
const PORTAL_TINT := Color(0.62, 0.42, 0.95)

var _label: Label3D
var _selected := false
var _run: Node
var _phase := 0.0
var _glow: Node3D


func setup(run: Node) -> void:
	_run = run
	position = PORTAL_POSITION
	_build_visual()
	_build_label()
	DungeonInteractionService.register_candidate(
		self,
		self,
		INTERACT_RANGE,
		4,
		Callable(self, "_interact"),
		Callable(),
		Callable(self, "_set_selected_prompt")
	)


func _build_visual() -> void:
	var root := Node3D.new()
	root.name = "Visual"
	add_child(root)
	PropLibrary.attach(root, "waves/summoner_arch", BiomeRegistry.BIOME_UMBRAL)

	_glow = Node3D.new()
	_glow.name = "PortalGlow"
	root.add_child(_glow)
	PropLibrary.attach(_glow, "waves/summoner_sheet", BiomeRegistry.BIOME_UMBRAL)
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
	PropLibrary.attach(wizard, "waves/summoner", BiomeRegistry.BIOME_UMBRAL)


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


func _set_selected_prompt(active: bool) -> void:
	_selected = active
	_refresh_label()


func _refresh_label() -> void:
	if _label == null or not is_instance_valid(_label):
		return
	if not _selected:
		_label.visible = false
		return
	_label.visible = true
	var bank_count := WavesRunService.cash_out_bank_count(WavesRunService.current_wave)
	var offer_key := "WAVES_PORTAL_OFFER_ONE" if bank_count == 1 else "WAVES_PORTAL_OFFER_MANY"
	_label.text = "%s — %s (%s)" % [
		tr("WAVES_SUMMONER_NAME"),
		tr(offer_key).format({"count": bank_count}),
		_interact_glyph(),
	]


static func _interact_glyph() -> String:
	var glyph := InputGlyphServiceScript.get_action_glyph("interact")
	return glyph if glyph != "" else "E"


func _interact() -> void:
	AudioDirector.play_sfx("ui_interact_near", global_position)
	if _run and is_instance_valid(_run) and _run.has_method("open_cash_out_picker"):
		_run.call("open_cash_out_picker")


func _process(delta: float) -> void:
	if _glow == null or not is_instance_valid(_glow):
		return
	_phase += delta
	var breathe := 1.0 + sin(_phase * 1.7) * 0.04
	_glow.scale = Vector3(breathe, 1.0, 1.0)
