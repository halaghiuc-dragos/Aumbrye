extends CanvasLayer

@export var player_path: NodePath
@export var enemy_path: NodePath

var show_debug := true
var show_hitboxes := false

var _player: CharacterBody3D
var _enemy: CharacterBody3D
var _label: Label
var _dodge: Node
var _guard: Node
var _weapon: Node
var _hit_feedback: Node


func _ready() -> void:
	_label = $DebugLabel
	if player_path:
		_player = get_node(player_path) as CharacterBody3D
		_dodge = _player.get_node_or_null("Dodge")
		_guard = _player.get_node_or_null("Guard")
		_weapon = _player.get_node_or_null("WeaponController")
		_hit_feedback = _player.get_node_or_null("HitFeedback")
	if enemy_path:
		_enemy = get_node(enemy_path) as CharacterBody3D


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_toggle"):
		show_debug = not show_debug
		_label.visible = show_debug
	if event.is_action_pressed("debug_hitboxes"):
		show_hitboxes = not show_hitboxes
		_toggle_hitbox_debug(show_hitboxes)
	if event.is_action_pressed("toggle_damage_numbers") and _hit_feedback:
		_hit_feedback.show_damage_numbers = not _hit_feedback.show_damage_numbers


func _process(_delta: float) -> void:
	if not show_debug:
		return
	var lines: PackedStringArray = []
	var fps := Engine.get_frames_per_second()
	lines.append("F1: overlay | F2: hitboxes | F3: dmg nums | R: reset | Q: tap block | FPS: %d" % fps)
	if _dodge:
		lines.append("i-frames: %s" % ("ON" if _dodge.get("iframes_active") else "off"))
	if _guard:
		lines.append("guard: %s | parry: %s | block: %s" % [
			"active" if _guard.get("is_guard_active") else "off",
			"OPEN" if _guard.get("parry_window_active") else "closed",
			"ON" if _guard.get("is_blocking") else "off",
		])
	if _player:
		var health := _player.get_node_or_null("Health") as Health
		var stamina := _player.get_node_or_null("Stamina") as Stamina
		if health:
			lines.append("HP: %.0f" % health.current)
		if stamina:
			lines.append("Stamina: %.0f" % stamina.current)
	if _enemy:
		var enemy_health := _enemy.get_node_or_null("Health") as Health
		if enemy_health:
			lines.append("Enemy HP: %.0f / %.0f" % [enemy_health.current, enemy_health.max_health])
	if show_hitboxes:
		var hit_nodes := get_tree().get_nodes_in_group("combat_hitbox")
		var hurt_nodes := get_tree().get_nodes_in_group("combat_hurtbox")
		var visible_meshes := _count_visible_debug_meshes()
		lines.append("hitbox draw: ON (%d hit, %d hurt, %d meshes)" % [
			hit_nodes.size(),
			hurt_nodes.size(),
			visible_meshes,
		])
	if _hit_feedback:
		lines.append("damage numbers: %s" % ("ON" if _hit_feedback.show_damage_numbers else "off"))
	if _weapon and _weapon.has_method("get_debug_state"):
		lines.append("attack: %s" % _weapon.call("get_debug_state"))
	var reactions := _player.get_node_or_null("CombatReactions") if _player else null
	if reactions:
		if reactions.get("is_dead"):
			lines.append("player: DEAD (press R)")
		elif reactions.get("is_staggered"):
			lines.append("player: staggered")
	_label.text = "\n".join(lines)


func _toggle_hitbox_debug(enabled: bool) -> void:
	var hit_count := 0
	var hurt_count := 0
	for node in get_tree().get_nodes_in_group("combat_hitbox"):
		if node.has_method("set_debug_draw"):
			node.call("set_debug_draw", enabled)
			hit_count += 1
	for node in get_tree().get_nodes_in_group("combat_hurtbox"):
		if node.has_method("set_debug_draw"):
			node.call("set_debug_draw", enabled)
			hurt_count += 1
	if enabled and hit_count + hurt_count == 0:
		push_warning("DebugOverlay: no combat hit/hurt boxes found in scene tree")


func _count_visible_debug_meshes() -> int:
	var count := 0
	for group_name in ["combat_hitbox", "combat_hurtbox"]:
		for node in get_tree().get_nodes_in_group(group_name):
			var debug_mesh := node.get_node_or_null("DebugDraw")
			if debug_mesh and debug_mesh.visible:
				count += 1
	return count


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
	if _player:
		var reactions := _player.get_node_or_null("CombatReactions")
		if reactions and reactions.has_method("reset_combat_state"):
			reactions.call("reset_combat_state")
