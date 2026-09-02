extends "res://scripts/dungeon/room_content/room_content_base.gd"

const FloorKeyringScript := preload("res://scripts/dungeon/floor_keyring.gd")

const CHEST_SCENE := preload("res://scenes/loot/loot_chest.tscn")
const DIORAMA_SKIN := preload("res://scripts/art/props/diorama_interactable_skin.gd")

var _key_id := ""
var _lock_id := ""
var _lock_flag_id := ""
var _key_label := "Dungeon Key"
var _collected := false

var _near_player := false
var _interact_area: Area3D
var _label: Label3D
var _chest: Node3D


func configure(entry: Dictionary, _definition: Dictionary) -> void:
	_key_id = str(entry.get("keyId", ""))
	_lock_id = str(entry.get("lockId", _key_id))
	_lock_flag_id = WorldFlags.lock_opened(_lock_id) if _lock_id != "" else ""
	_key_label = str(entry.get("keyLabel", "Dungeon Key"))
	_chest = CHEST_SCENE.instantiate() as Node3D
	_chest.name = "KeyVaultChest"
	_chest.position = _anchor(0).position
	_content_root().add_child(_chest)
	if _chest.has_method("configure"):
		_chest.call("configure", {"items": entry.get("items", [])})
	_style_key_chest()
	_interact_area = Area3D.new()
	_interact_area.name = "KeyPickupArea"
	_interact_area.collision_layer = 0
	_interact_area.collision_mask = 2
	_interact_area.monitoring = true
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.0, 3.0, 3.0)
	shape.shape = box
	shape.position = Vector3(0.0, 1.2, 0.0)
	_interact_area.add_child(shape)
	_interact_area.position = _anchor(0).position
	_content_root().add_child(_interact_area)
	_interact_area.body_entered.connect(_on_body_entered)
	_interact_area.body_exited.connect(_on_body_exited)
	_label = Label3D.new()
	_label.name = "KeyLabel"
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 22
	_label.outline_size = 10
	_label.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	_label.position = _anchor(0).position + Vector3(0.0, 2.4, 0.0)
	_label.modulate = Color(1.0, 0.9, 0.45, 1.0)
	_label.visible = false
	_content_root().add_child(_label)
	if _lock_flag_id != "" and WorldState.is_flag_true(_lock_flag_id):
		_collected = true
		_chest.visible = false
	if _lock_flag_id != "":
		WorldState.namespace_changed.connect(_on_namespace_changed)


func _on_namespace_changed(flag_namespace: String, flag_id: String, _value: Variant) -> void:
	if flag_namespace == WorldFlags.NS_LOCK and flag_id == _lock_flag_id:
		_collected = WorldState.is_flag_true(_lock_flag_id)
		if _chest:
			_chest.visible = not _collected


func _style_key_chest() -> void:
	var mesh := _chest.get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mesh:
		mesh.material_override = DIORAMA_SKIN.make_telegraph_material(Color(0.85, 0.65, 0.15, 1.0))


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	_near_player = true
	if _collected:
		return
	_label.visible = true
	_label.text = "%s — %s" % [
		InputGlyphService.get_action_prompt(&"interact"), _key_label
	]


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		_near_player = false
		_label.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if _collected or not _near_player:
		return
	if not PlayerInput.interact_just_pressed(event):
		return
	# Into the floor keyring, not the inventory: a keycard is not loot, and a full bag must never be
	# the reason a floor cannot be finished.
	if not FloorKeyringScript.take(_key_id):
		return
	_collected = true
	if _chest:
		_chest.visible = false
	_label.visible = false
	get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	if _lock_flag_id != "" and WorldState.namespace_changed.is_connected(_on_namespace_changed):
		WorldState.namespace_changed.disconnect(_on_namespace_changed)
