extends Area3D


const DioramaSkin := preload("res://scripts/art/props/diorama_interactable_skin.gd")
const RarityRegistryScript := preload("res://scripts/loot/rarity_registry.gd")

@export var item_id := "iron_scrap"
@export var quantity := 1

const INTERACT_RANGE := 2.0
const DESPAWN_SECONDS := 20.0 * 60.0
const DESPAWN_FADE_SECONDS := 20.0

var _visual: Node3D
var _label: Label3D
var _beam: Node3D
var _rarity := "common"
var _despawn_timer := 0.0


func _ready() -> void:
	add_to_group("world_item_pickup")
	collision_layer = 0
	collision_mask = 0
	monitoring = false
	_visual = DioramaSkin.build_loot_pickup(self, DioramaSkin.resolve_biome(self))
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
		Callable(self, "_pickup"),
		Callable(),
		Callable(self, "_set_selected_prompt")
	)
	set_process(false)
	_start_bob()


func _start_bob() -> void:
	if _visual == null:
		return
	var base_y := float(_visual.get_meta("bob_base_y", 0.0))
	var tween := create_tween()
	tween.set_loops()
	tween.tween_property(_visual, "position:y", base_y + 0.08, 0.83).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_visual, "position:y", base_y - 0.08, 0.83).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## What a floor snapshot keeps of an item lying on the ground.
func capture_state() -> Dictionary:
	return {
		"itemId": item_id,
		"quantity": quantity,
		"rarity": _rarity,
		"x": global_position.x,
		"y": global_position.y,
		"z": global_position.z,
	}


func set_despawn_after_drop() -> void:
	_despawn_timer = DESPAWN_SECONDS
	set_process(true)


func _process(delta: float) -> void:
	if _despawn_timer <= 0.0:
		return
	_despawn_timer -= delta
	if _despawn_timer <= 0.0:
		queue_free()
		return
	if _despawn_timer >= DESPAWN_FADE_SECONDS:
		return
	var fade := _despawn_timer / DESPAWN_FADE_SECONDS
	var shown := sin(_despawn_timer * (10.0 - 7.0 * fade)) > -0.4
	if _visual and is_instance_valid(_visual):
		_visual.visible = shown
	if _beam and is_instance_valid(_beam):
		_beam.visible = shown


func configure(id: String, qty: int = 1, rarity: String = "") -> void:
	item_id = id
	quantity = maxi(1, qty)
	var def := ItemCatalog.get_definition(item_id)
	_label.text = def.get("name", item_id)
	var resolved := rarity if rarity != "" else str(def.get("rarity", "common"))
	_rarity = RarityRegistryScript.normalize(resolved)
	_apply_rarity_presentation()


func _apply_rarity_presentation() -> void:
	var color := RarityRegistryScript.display_color(_rarity)
	var tier := maxi(0, RarityRegistryScript.tier_index(_rarity))
	if _label:
		_label.modulate = color
		_label.font_size = 32 + tier * 4
		_label.outline_size = 4 + tier * 2
		_label.outline_modulate = color.darkened(0.7)
		if RarityRegistryScript.wants_drop_toast(_rarity):
			_label.visible = true
	_build_beam(color)
	if AudioDirector:
		var sfx := RarityRegistryScript.drop_sfx_id(_rarity)
		if AudioDirector.has_sfx(sfx):
			AudioDirector.play_sfx(sfx, global_position)
		else:
			AudioDirector.play_sfx("ui_interact_near", global_position)
	if RarityRegistryScript.wants_camera_nudge(_rarity) and VfxService:
		VfxService.request_shake(0.12, 320)
		# Same top-tier gate as the camera nudge -- see `loot_chest.gd:_present_rarity_juice()`.
		AudioDirector.play_stinger("rare_drop")


func _build_beam(color: Color) -> void:
	if _beam and is_instance_valid(_beam):
		_beam.queue_free()
	var height := RarityRegistryScript.drop_beam_height(_rarity)
	var beam := MeshInstance3D.new()
	beam.name = "RarityBeam"
	beam.mesh = PropLibrary.bare_mesh("fx/beam")
	beam.scale = Vector3(0.16, height, 0.16)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color(color.r, color.g, color.b, 0.32)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = RarityRegistryScript.drop_beam_energy(_rarity)
	beam.material_override = material
	add_child(beam)
	_beam = beam


func _set_selected_prompt(active: bool) -> void:
	_label.visible = active or RarityRegistryScript.wants_drop_toast(_rarity)


func _pickup() -> void:
	if InventoryService.add_loot(item_id, {"quantity": quantity}):
		if RunFlow:
			RunFlow.register_loot(item_id)
		queue_free()
