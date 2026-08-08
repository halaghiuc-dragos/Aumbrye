extends Area3D

## World item pickup — adds to grid inventory on interact (INV-2.1).

const DioramaSkin := preload("res://scripts/art/props/diorama_interactable_skin.gd")
const RarityRegistryScript := preload("res://scripts/loot/rarity_registry.gd")

@export var item_id := "iron_scrap"
@export var quantity := 1

var _visual: Node3D
var _label: Label3D
var _player: Node3D
var _beam: Node3D
var _rarity := "common"


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 1.2
	shape.shape = sphere
	add_child(shape)
	_visual = DioramaSkin.build_loot_pickup(self, DioramaSkin.resolve_biome(self))
	_label = Label3D.new()
	_label.name = "Label3D"
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 32
	_label.modulate = Color(0.7, 0.9, 1.0, 1.0)
	_label.visible = false
	add_child(_label)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	set_process_unhandled_input(false)
	_start_bob()


func _start_bob() -> void:
	if _visual == null:
		return
	var base_y := float(_visual.get_meta("bob_base_y", 0.0))
	var tween := create_tween()
	tween.set_loops()
	tween.tween_property(_visual, "position:y", base_y + 0.08, 0.83).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_visual, "position:y", base_y - 0.08, 0.83).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


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


func _build_beam(color: Color) -> void:
	if _beam and is_instance_valid(_beam):
		_beam.queue_free()
	var height := RarityRegistryScript.drop_beam_height(_rarity)
	var beam := MeshInstance3D.new()
	beam.name = "RarityBeam"
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.06
	cylinder.bottom_radius = 0.16
	cylinder.height = height
	cylinder.radial_segments = 8
	beam.mesh = cylinder
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
	beam.position = Vector3(0.0, height * 0.5, 0.0)
	add_child(beam)
	_beam = beam


func _unhandled_input(event: InputEvent) -> void:
	if _player == null:
		return
	if event.is_action_pressed("interact"):
		_pickup()


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player = body
		_label.visible = true
		set_process_unhandled_input(true)


func _on_body_exited(body: Node3D) -> void:
	if body == _player:
		_player = null
		_label.visible = RarityRegistryScript.wants_drop_toast(_rarity)
		set_process_unhandled_input(false)


func _pickup() -> void:
	if InventoryService.add_loot(item_id, {"quantity": quantity}):
		if RunFlow:
			RunFlow.register_loot(item_id)
		queue_free()
