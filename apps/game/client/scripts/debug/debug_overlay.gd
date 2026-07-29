extends CanvasLayer

@export var player_path: NodePath
@export var enemy_path: NodePath

var show_debug := true
var show_hitboxes := false

var _player: CharacterBody3D
var _enemy: CharacterBody3D
var _label: Label
var _dodge: Node
var _parry: Node


func _ready() -> void:
	_label = $DebugLabel
	if player_path:
		_player = get_node(player_path) as CharacterBody3D
		_dodge = _player.get_node_or_null("Dodge")
		_parry = _player.get_node_or_null("Parry")
	if enemy_path:
		_enemy = get_node(enemy_path) as CharacterBody3D


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_toggle"):
		show_debug = not show_debug
		_label.visible = show_debug
	if event.is_action_pressed("debug_hitboxes"):
		show_hitboxes = not show_hitboxes
		_toggle_hitbox_debug(show_hitboxes)


func _process(_delta: float) -> void:
	if not show_debug:
		return
	var lines: PackedStringArray = []
	lines.append("F1: toggle overlay | F2: hitbox draw | R: reset duel")
	if _dodge:
		lines.append("i-frames: %s" % ("ON" if _dodge.get("iframes_active") else "off"))
	if _parry:
		lines.append("parry window: %s" % ("OPEN" if _parry.get("parry_window_active") else "closed"))
	if _player:
		var health := _player.get_node_or_null("Health") as Health
		var stamina := _player.get_node_or_null("Stamina") as Stamina
		if health:
			lines.append("HP: %.0f" % health.current)
		if stamina:
			lines.append("Stamina: %.0f" % stamina.current)
	_label.text = "\n".join(lines)


func _toggle_hitbox_debug(enabled: bool) -> void:
	for node in get_tree().get_nodes_in_group("combat_hitbox"):
		if node is Hitbox:
			node.visible = enabled
			for child in node.get_children():
				if child is MeshInstance3D:
					child.visible = enabled


func reset_duel() -> void:
	if _player:
		var health := _player.get_node_or_null("Health") as Health
		var stamina := _player.get_node_or_null("Stamina") as Stamina
		var poise := _player.get_node_or_null("Poise") as Poise
		if health:
			health.reset_health()
		if stamina:
			stamina.reset_stamina()
		if poise:
			poise.reset_poise()
		_player.global_position = Vector3(0, 1, 0)
		_player.velocity = Vector3.ZERO
	if _enemy:
		if _enemy.has_method("reset_enemy"):
			_enemy.call("reset_enemy")
		_enemy.global_position = Vector3(6, 1, 0)
		_enemy.velocity = Vector3.ZERO
