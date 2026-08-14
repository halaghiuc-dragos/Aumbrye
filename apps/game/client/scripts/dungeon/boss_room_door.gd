extends Node3D

## Boss arena door — earned gate with open / seal / release lifecycle.

const DioramaSkin := preload("res://scripts/art/props/diorama_interactable_skin.gd")

enum State { LOCKED, CLOSED, OPEN, SEALED, RELEASED }

signal door_opened
signal door_sealed

var _barrier: StaticBody3D
var _barrier_shape: CollisionShape3D
var _barrier_mesh: MeshInstance3D
var _interact_area: Area3D
var _label: Label3D
var _near_player := false
var _state: State = State.CLOSED
var _requirement := "none"
var _floor := 1
var _locks: Array = []
var _biome_id := BiomeRegistry.BIOME_CASTLE


func _ready() -> void:
	_resolve_nodes()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_interact_area.body_entered.connect(_on_body_entered)
	_interact_area.body_exited.connect(_on_body_exited)
	_apply_barrier_visual()
	_update_label()


## Idempotent, and called from `configure()` as well as `_ready()`.
##
## DungeonBuilder configures the door on the instantiated scene before it adds it to the tree, so
## `_ready()` has not run yet and every one of these references was still null — `configure()`
## then threw on the barrier's `disabled` and the label's `visible` on every dungeon build. The
## children exist as soon as the scene is instantiated, so they can be resolved on demand.
func _resolve_nodes() -> void:
	if _barrier != null:
		return
	_barrier = get_node_or_null("Barrier") as StaticBody3D
	if _barrier == null:
		return
	_barrier_shape = _barrier.get_node_or_null("BarrierShape") as CollisionShape3D
	_barrier_mesh = _barrier.get_node_or_null("MeshInstance3D") as MeshInstance3D
	_interact_area = get_node_or_null("InteractArea") as Area3D
	_label = get_node_or_null("Label3D") as Label3D


func configure(
	biome_id: String,
	requirement: String = "none",
	floor: int = 1,
	locks: Array = []
) -> void:
	_biome_id = biome_id
	_requirement = requirement
	_floor = floor
	_locks = locks
	_resolve_nodes()
	set_meta("biome_id", biome_id)
	DioramaSkin.build_boss_door_frame(self, biome_id)
	if _barrier_mesh:
		_barrier_mesh.material_override = BiomeRegistry.get_wall_material(biome_id)
	if requirement == "sigil":
		_state = State.LOCKED
	elif requirement == "all_keys" and not _all_locks_open():
		_state = State.LOCKED
	else:
		_state = State.CLOSED
	_apply_barrier_visual()
	_update_label()


func get_state() -> State:
	return _state


func get_state_name() -> String:
	return State.keys()[_state]


func apply_state(state_name: String) -> void:
	var idx := State.keys().find(state_name)
	if idx < 0:
		return
	_state = idx as State
	_apply_barrier_visual()
	_update_label()


func is_opened() -> bool:
	return _state == State.OPEN or _state == State.RELEASED


func is_sealed() -> bool:
	return _state == State.SEALED


func open_door() -> void:
	if _state != State.CLOSED:
		return
	_state = State.OPEN
	_apply_barrier_visual()
	_update_label()
	AudioDirector.play_cue(&"door_open", global_position)
	door_opened.emit()


func seal_door() -> void:
	if _state != State.OPEN:
		return
	_state = State.SEALED
	_apply_barrier_visual()
	_update_label()
	AudioDirector.play_cue(&"door_seal", global_position)
	VfxService.play_rune_flare(global_position + Vector3(0.0, 2.0, 0.0))
	door_sealed.emit()


func release_door() -> void:
	_state = State.RELEASED
	_apply_barrier_visual()
	_label.visible = false
	AudioDirector.play_cue(&"door_release", global_position)


func reset_door() -> void:
	if _requirement == "sigil":
		_state = State.LOCKED
	elif _requirement == "all_keys" and not _all_locks_open():
		_state = State.LOCKED
	else:
		_state = State.CLOSED
	_apply_barrier_visual()
	_update_label()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact") or not _near_player:
		return
	if _state == State.SEALED:
		get_viewport().set_input_as_handled()
		return
	if _state == State.LOCKED:
		if _requirement == "sigil" and _has_sigil():
			InventoryService.consume_boss_sigil()
			_state = State.CLOSED
			open_door()
		elif _requirement == "all_keys" and _all_locks_open():
			_state = State.CLOSED
			open_door()
		get_viewport().set_input_as_handled()
		return
	if _state == State.CLOSED:
		open_door()
		get_viewport().set_input_as_handled()


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		_near_player = true
		_update_label()


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		_near_player = false
		_update_label()


func _apply_barrier_visual() -> void:
	if _barrier_shape == null:
		return
	var solid := _state in [State.LOCKED, State.CLOSED, State.SEALED]
	_barrier_shape.disabled = not solid
	if _barrier_mesh:
		_barrier_mesh.visible = solid


func _update_label() -> void:
	if _label == null:
		return
	if not _near_player:
		_label.visible = false
		return
	match _state:
		State.LOCKED:
			_label.text = _locked_prompt()
			_label.visible = true
		State.CLOSED:
			_label.text = "%s Enter the arena" % InputGlyphService.format_interact_label()
			_label.visible = true
		State.SEALED:
			_label.text = "The way back is sealed"
			_label.visible = true
		_:
			_label.visible = false


func _locked_prompt() -> String:
	match _requirement:
		"sigil":
			return "Sealed — find the Boss Sigil"
		"all_keys":
			return "Sealed — open every lock on this floor"
		_:
			return "Sealed"


func _has_sigil() -> bool:
	return InventoryService.count_item("boss_sigil") > 0


func _all_locks_open() -> bool:
	for lock in _locks:
		if lock is Dictionary:
			var lock_id := str(lock.get("lockId", ""))
			if lock_id == "":
				continue
			if not WorldState.is_flag_true(WorldFlags.lock_opened(lock_id)):
				return false
	return true
