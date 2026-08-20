extends Area3D

## Recoverable XP left at a death spot — grants stored XP on interact.

const DioramaSkin := preload("res://scripts/art/props/diorama_interactable_skin.gd")

const BEACON_HEIGHT := 14.0
const BEACON_BOTTOM_RADIUS := 0.32
const BEACON_TOP_RADIUS := 0.06
const BEACON_COLOR := Color(0.62, 0.86, 1.0, 0.34)
## Pushes the beam behind opaque geometry in the transparency sort so it does not flicker
## against room walls it is deliberately drawing through.
const BEACON_SORTING_OFFSET := -8.0

var _xp_amount := 0
var _gold_amount := 0
var _visual: Node3D
var _player: Node3D
var _label: Label3D
var _beacon: MeshInstance3D


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 1.2
	shape.shape = sphere
	add_child(shape)
	_visual = DioramaSkin.build_loot_pickup(self, DioramaSkin.resolve_biome(self))
	_build_beacon()
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


## A pillar of light above the death spot, visible across a room and through the gaps between
## floors.
##
## The recovery loop itself is complete — the shard spawns where you fell, holds the deferred XP
## and the staked gold, and hands both back on interact. But it was a knee-high pickup with a
## label that only appears once you are already standing on it, in a procedurally generated
## floor you have just respawned into from the other end. A recovery run you cannot navigate is
## not a recovery run; the pressure of "it is over there and something is standing on it" is the
## entire point of the mechanic.
func _build_beacon() -> void:
	var beam := MeshInstance3D.new()
	beam.name = "ShardBeacon"
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = BEACON_TOP_RADIUS
	cylinder.bottom_radius = BEACON_BOTTOM_RADIUS
	cylinder.height = BEACON_HEIGHT
	cylinder.radial_segments = 8
	beam.mesh = cylinder
	beam.position = Vector3(0.0, BEACON_HEIGHT * 0.5, 0.0)
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	# No depth test: the beam reads through walls and floors, which is what makes it a waypoint
	# rather than decoration.
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
		_label.text = "Echo shard (+%d XP, %d gold)" % [_xp_amount, _gold_amount]
	else:
		_label.text = "Echo shard (+%d XP)" % _xp_amount


func _unhandled_input(event: InputEvent) -> void:
	if _player == null:
		return
	if PlayerInput.interact_just_pressed(event):
		_collect()


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player = body
		_label.visible = true
		set_process_unhandled_input(true)


func _on_body_exited(body: Node3D) -> void:
	if body == _player:
		_player = null
		_label.visible = false
		set_process_unhandled_input(false)


func _collect() -> void:
	if _xp_amount <= 0 and _gold_amount <= 0:
		queue_free()
		return
	if _xp_amount > 0:
		ProgressionService.grant_xp(_xp_amount, "xp_shard")
	if _gold_amount > 0:
		CharacterService.add_gold(_gold_amount, false)
	RunFlow.clear_recoverable_xp_shard()
	queue_free()
