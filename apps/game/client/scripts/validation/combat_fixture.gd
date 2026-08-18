extends RefCounted
class_name CombatFixture

## Deterministic two-body arena for combat pipeline validation.

const GRUNT_SCENE := preload("res://scenes/enemies/training_grunt.tscn")
const CRIT_SEED := 424242

var _ctx: TestContext
var _arena: Node3D
var _attacker: CharacterBody3D
var _defender: CharacterBody3D
var _attacker_hitbox: Hitbox
var _defender_hurtbox: Hurtbox
var _defender_health: Health
var _defender_poise: Poise
var _hp_before: float = 0.0
var _known_label_ids: Dictionary = {}


func _init(context: TestContext) -> void:
	_ctx = context


func setup(_attacker_id := "player", _defender_id := "training_grunt") -> void:
	_arena = Node3D.new()
	_arena.name = "CombatFixtureArena"
	_ctx.owner.add_child(_arena)

	_attacker = CharacterBody3D.new()
	_attacker.name = "Attacker"
	_arena.add_child(_attacker)

	var pivot := Node3D.new()
	pivot.position = Vector3(0.0, 1.0, 0.8)
	_attacker.add_child(pivot)

	_attacker_hitbox = Hitbox.new()
	_attacker_hitbox.team = "player"
	_attacker_hitbox.collision_layer = 4
	_attacker_hitbox.collision_mask = 8
	pivot.add_child(_attacker_hitbox)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 0.8, 1.2)
	shape.shape = box
	shape.position = Vector3(0.0, 0.0, 0.45)
	_attacker_hitbox.add_child(shape)

	_defender = GRUNT_SCENE.instantiate() as CharacterBody3D
	_defender.name = "Defender"
	_arena.add_child(_defender)

	_defender_health = _defender.get_node("Health") as Health
	_defender_health.configure(60.0)
	_defender_poise = _defender.get_node("Poise") as Poise
	_defender_poise.configure(40.0)
	_defender_hurtbox = _defender.get_node("Hurtbox") as Hurtbox

	await _ctx.await_physics(2)
	place(Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.0, 1.2))


func teardown() -> void:
	if _arena and is_instance_valid(_arena):
		_arena.queue_free()
		_arena = null
	await _ctx.await_frame()


func place(attacker_pos: Vector3, defender_pos: Vector3, defender_yaw := 0.0) -> void:
	_attacker.global_position = attacker_pos
	_defender.global_position = defender_pos
	_defender.rotation.y = defender_yaw
	_mark_hp()
	_clear_label_tracker()
	if AudioDirector:
		AudioDirector.last_combat_cue = ""


func strike(overrides: Dictionary = {}) -> Dictionary:
	var damage: float = float(overrides.get("damage", 12.0))
	var poise: float = float(overrides.get("poise_damage", 15.0))
	var dmg_type: String = str(overrides.get("damage_type", DamageInfo.TYPE_PHYSICAL))
	var status_id: String = str(overrides.get("status_id", ""))
	var status_stacks: int = int(overrides.get("status_stacks", 1))
	var crit_chance: float = float(overrides.get("crit_chance", 0.0))
	var team: String = str(overrides.get("team", _attacker_hitbox.team))

	_mark_hp()
	_clear_label_tracker()
	if AudioDirector:
		AudioDirector.last_combat_cue = ""
	_attacker_hitbox.team = team
	_attacker_hitbox.set_combat_owner(_attacker)
	_attacker_hitbox.set_attack_values(
		damage, poise, dmg_type, status_id, status_stacks, crit_chance
	)
	_attacker_hitbox.reset_swing()
	seed(CRIT_SEED)
	_attacker_hitbox.enable()
	await _ctx.await_physics(2)
	_attacker_hitbox.disable()
	return {"hp_lost": hp_lost()}


func direct_hit(info: DamageInfo) -> void:
	_mark_hp()
	_clear_label_tracker()
	if AudioDirector:
		AudioDirector.last_combat_cue = ""
	_defender_hurtbox.receive_hit(info)


func hp_lost() -> float:
	if _defender_health == null:
		return 0.0
	return _hp_before - _defender_health.current


func attacker_body() -> CharacterBody3D:
	return _attacker


func defender_body() -> CharacterBody3D:
	return _defender


func defender_health() -> Health:
	return _defender_health


func defender_hurtbox() -> Hurtbox:
	return _defender_hurtbox


func attacker_hitbox() -> Hitbox:
	return _attacker_hitbox


func add_guard_to_defender() -> Node:
	var guard := preload("res://scripts/combat/guard.gd").new()
	var stamina := Stamina.new()
	stamina.configure(100.0)
	_defender.add_child(stamina)
	_defender.add_child(guard)
	await _ctx.await_physics(1)
	return guard


func add_dodge_to_defender() -> Node:
	var dodge := preload("res://scripts/player/dodge.gd").new()
	_defender.add_child(dodge)
	await _ctx.await_physics(1)
	return dodge


func add_status_controller_to_defender() -> StatusController:
	var status_ctrl := StatusController.new()
	_defender.add_child(status_ctrl)
	await _ctx.await_physics(1)
	return status_ctrl


func add_hit_feedback_to_defender() -> Node:
	var feedback := preload("res://scripts/combat/hit_feedback.gd").new()
	_defender.add_child(feedback)
	await _ctx.await_physics(1)
	return feedback


func labels() -> Array[Node]:
	var result: Array[Node] = []
	var tree := _ctx.owner.get_tree()
	if tree == null:
		return result
	for node in tree.get_nodes_in_group("damage_number"):
		if not _known_label_ids.has(node.get_instance_id()):
			result.append(node)
	return result


func last_cue() -> String:
	if AudioDirector:
		return AudioDirector.last_combat_cue
	return ""


func label_amount(label_node: Node) -> int:
	var label := label_node.get_node_or_null("Label3D") as Label3D
	if label and label.text.is_valid_int():
		return int(label.text)
	return -1


func _clear_label_tracker() -> void:
	_known_label_ids.clear()
	var tree := _ctx.owner.get_tree()
	if tree == null:
		return
	for node in tree.get_nodes_in_group("damage_number"):
		_known_label_ids[node.get_instance_id()] = true


func _mark_hp() -> void:
	_hp_before = _defender_health.current if _defender_health else 0.0
