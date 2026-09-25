extends "res://scripts/dungeon/room_content/room_content_base.gd"

const DIORAMA_SKIN := preload("res://scripts/art/props/diorama_interactable_skin.gd")
const InteractPromptScript := preload("res://scripts/ui/interact_prompt.gd")

const INTERACT_RADIUS := 1.6

var _configured := false
var _rest_area: Area3D
var _player: Node3D
var _prompt: InteractPrompt


func configure(_entry: Dictionary, _definition: Dictionary) -> void:
	if _configured:
		return
	_configured = true
	var root := _content_root()
	var bonfire := Node3D.new()
	bonfire.name = "BonfireVisual"
	bonfire.position = _anchor(0).position
	DIORAMA_SKIN.build_bonfire(bonfire, DIORAMA_SKIN.resolve_biome(self))
	root.add_child(bonfire)
	_prompt = InteractPromptScript.build(
		root, _anchor(0).position + Vector3(0.0, 2.4, 0.0)
	)
	_rest_area = Area3D.new()
	_rest_area.name = "RestArea"
	_rest_area.collision_layer = 0
	_rest_area.collision_mask = 2
	_rest_area.monitoring = true
	_rest_area.position = _anchor(0).position + Vector3(0.0, 0.5, 0.0)
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = INTERACT_RADIUS
	shape.shape = sphere
	_rest_area.add_child(shape)
	root.add_child(_rest_area)
	_rest_area.body_entered.connect(_on_body_entered)
	_rest_area.body_exited.connect(_on_body_exited)
	DungeonInteractionService.register_candidate(self, bonfire, INTERACT_RADIUS, 4, Callable(self, "_activate_interaction"), Callable(self, "_can_rest"), Callable(self, "_set_selected_prompt"), true)


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player = body
		DungeonInteractionService.refresh()


func _on_body_exited(body: Node3D) -> void:
	if body == _player:
		_player = null
		DungeonInteractionService.refresh()


func _set_selected_prompt(active: bool) -> void:
	if _prompt == null:
		return
	if not active or _player == null:
		_prompt.hide_prompt()
		return
	if RunModifierService.has_modifier(RunModifierService.MODIFIER_NO_REST):
		_prompt.show_text(tr("REST_PROMPT_DISABLED"))
	elif RunModifierService.has_modifier(RunModifierService.MODIFIER_STARVED_HEARTH):
		_prompt.show_text(tr("REST_PROMPT_STARVED"))
	else:
		_prompt.show_text(tr("REST_PROMPT_FULL"))


func _can_rest() -> bool:
	return _player != null


func _activate_interaction() -> void:
	if _player == null:
		return
	_trigger_rest(_player)


func _trigger_rest(player: Node3D) -> void:
	if RunFlow and RunFlow.has_method("rest_at_bonfire"):
		RunFlow.rest_at_bonfire(player)
