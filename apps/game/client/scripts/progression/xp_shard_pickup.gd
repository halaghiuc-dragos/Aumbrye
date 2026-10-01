extends Area3D


const DioramaSkin := preload("res://scripts/art/props/diorama_interactable_skin.gd")

const INTERACT_RANGE := 2.0
const BEACON_HEIGHT := 14.0
const BEACON_BOTTOM_RADIUS := 0.32
const BEACON_COLOR := Color(0.62, 0.86, 1.0, 0.34)
const BEACON_SORTING_OFFSET := -8.0

var _xp_amount := 0
var _gold_amount := 0
var _visual: Node3D
var _label: Label3D
var _beacon: MeshInstance3D


func _ready() -> void:
	collision_layer = 0
	collision_mask = 0
	monitoring = false
	_visual = DioramaSkin.build_loot_pickup(self, DioramaSkin.resolve_biome(self))
	_build_beacon()
	_label = Label3D.new()
	_label.name = "Label3D"
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 32
	_label.outline_size = 14
	_label.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	_label.modulate = Color(0.7, 0.9, 1.0, 1.0)
	_label.visible = false
	add_child(_label)
	DungeonInteractionService.register_candidate(
		self,
		self,
		INTERACT_RANGE,
		2,
		Callable(self, "_collect"),
		Callable(),
		Callable(self, "_set_selected_prompt")
	)
	_start_bob()


func _build_beacon() -> void:
	var beam := MeshInstance3D.new()
	beam.name = "ShardBeacon"
	beam.mesh = PropLibrary.bare_mesh("fx/beam")
	beam.scale = Vector3(BEACON_BOTTOM_RADIUS, BEACON_HEIGHT, BEACON_BOTTOM_RADIUS)
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = true
	material.albedo_color = BEACON_COLOR
	beam.material_override = material
	beam.sorting_offset = BEACON_SORTING_OFFSET
	add_child(beam)
	_beacon = beam
	var pulse := create_tween()
	pulse.set_loops()
	pulse.tween_property(material, "albedo_color:a", BEACON_COLOR.a * 0.35, 0.9).set_trans(
		Tween.TRANS_SINE
	).set_ease(Tween.EASE_IN_OUT)
	pulse.tween_property(material, "albedo_color:a", BEACON_COLOR.a, 0.9).set_trans(
		Tween.TRANS_SINE
	).set_ease(Tween.EASE_IN_OUT)


func _start_bob() -> void:
	if _visual == null:
		return
	var base_y := float(_visual.get_meta("bob_base_y", 0.0))
	var tween := create_tween()
	tween.set_loops()
	tween.tween_property(_visual, "position:y", base_y + 0.1, 0.63).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_visual, "position:y", base_y - 0.1, 0.63).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func configure(world_pos: Vector3, xp_amount: int, gold_amount: int = 0) -> void:
	global_position = world_pos
	_xp_amount = maxi(0, xp_amount)
	_gold_amount = maxi(0, gold_amount)
	if _gold_amount > 0:
		_label.text = tr("XP_SHARD_XP_GOLD").format({"xp": _xp_amount, "gold": _gold_amount})
	else:
		_label.text = tr("XP_SHARD_XP").format({"xp": _xp_amount})


func _set_selected_prompt(active: bool) -> void:
	_label.visible = active


func _collect() -> void:
	if _xp_amount <= 0 and _gold_amount <= 0:
		queue_free()
		return
	var offer := _umbral_ui()
	if offer == null:
		# No UI available (an arena or a stripped scene) — fall back to the plain refund rather
		# than stranding the player's staked XP behind a menu that cannot open.
		_recover()
		return
	if offer.is_open():
		return
	offer.recovered.connect(_recover, CONNECT_ONE_SHOT)
	offer.listened.connect(_listen, CONNECT_ONE_SHOT)
	offer.dismissed.connect(_on_offer_dismissed, CONNECT_ONE_SHOT)
	offer.open_offer(_xp_amount, _gold_amount)


func _umbral_ui() -> Node:
	var existing := get_tree().get_first_node_in_group("umbral_shard_ui")
	if existing != null:
		return existing
	var run := get_tree().get_first_node_in_group("castle_run")
	if run == null:
		return null
	var ui := Control.new()
	ui.name = "UmbralShardUI"
	ui.set_script(load("res://scripts/ui/umbral_shard_ui.gd"))
	run.add_child(ui)
	return ui


func _on_offer_dismissed() -> void:
	_disconnect_offer()


func _disconnect_offer() -> void:
	var offer := get_tree().get_first_node_in_group("umbral_shard_ui")
	if offer == null:
		return
	for entry in [
		["recovered", _recover], ["listened", _listen], ["dismissed", _on_offer_dismissed]
	]:
		var signal_name: String = entry[0]
		var callable: Callable = entry[1]
		if offer.is_connected(signal_name, callable):
			offer.disconnect(signal_name, callable)


func _recover() -> void:
	_disconnect_offer()
	if _xp_amount > 0:
		ProgressionService.grant_xp(_xp_amount, "xp_shard")
	if _gold_amount > 0:
		CharacterService.add_gold(_gold_amount, false)
	RunFlow.clear_recoverable_xp_shard()
	queue_free()


## Leave the numbers where they fell and take the warden instead — a relic choice, for this run.
func _listen() -> void:
	_disconnect_offer()
	var run := get_tree().get_first_node_in_group("castle_run")
	if run == null or not run.has_method("offer_umbral_relic"):
		return
	if not bool(run.call("offer_umbral_relic")):
		return
	RunFlow.clear_recoverable_xp_shard()
	VfxService.play_rune_flare(global_position + Vector3(0.0, 1.0, 0.0))
	AudioDirector.play_stinger("floor_clear")
	queue_free()
