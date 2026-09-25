extends "res://scripts/dungeon/room_content/room_content_base.gd"

const DioramaSkin := preload("res://scripts/art/props/diorama_interactable_skin.gd")
const InteractPromptScript := preload("res://scripts/ui/interact_prompt.gd")

var _dialogue_id := "dungeon_lore_default"
var _lore_id := ""
var _near_player := false
var _prompt: InteractPrompt


func configure(entry: Dictionary, _definition: Dictionary) -> void:
	_dialogue_id = str(entry.get("dialogueId", _dialogue_id))
	_lore_id = str(entry.get("loreId", get_meta("placement_id", "")))
	var prop := Node3D.new()
	prop.name = "LoreProp"
	prop.set_meta("lore_id", _lore_id)
	var interact := Area3D.new()
	interact.name = "InteractArea"
	interact.collision_layer = 0
	interact.collision_mask = 2
	interact.monitoring = true
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 2.5, 2.0)
	shape.shape = box
	interact.add_child(shape)
	prop.add_child(interact)
	interact.body_entered.connect(_on_body_entered)
	interact.body_exited.connect(_on_body_exited)
	prop.position = _anchor(0).position
	DioramaSkin.build_lectern(prop, DioramaSkin.resolve_biome(self))
	_content_root().add_child(prop)
	_prompt = InteractPromptScript.build(prop, Vector3(0.0, 2.4, 0.0))
	DungeonInteractionService.register_candidate(self, prop, 2.2, 1, Callable(self, "_activate_interaction"), Callable(), Callable(self, "_set_selected_prompt"), true)


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		_near_player = true
		DungeonInteractionService.refresh()


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		_near_player = false
		DungeonInteractionService.refresh()


func _activate_interaction() -> void:
	if not _near_player:
		return
	var dialogue_ui := get_tree().get_first_node_in_group("dialogue_ui")
	if dialogue_ui and dialogue_ui.has_method("start_dialogue"):
		var first_read := _record_discovery_once()
		if dialogue_ui.call(
			"start_dialogue",
			_dialogue_id,
			_dialogue_node_id(),
			true,
			["increment_flag", "record_discovery"]
		):
			if first_read and _prompt:
				_set_selected_prompt(true)


func _set_selected_prompt(active: bool) -> void:
	if _prompt == null:
		return
	if active and _near_player:
		_prompt.show_action("Reread" if _lore_id != "" and CharacterService.get_flag("lore_discoveries", {}).has(_lore_id) else "Read")
	else:
		_prompt.hide_prompt()


func _dialogue_node_id() -> String:
	var biome_id := str(get_meta("biome_id", "forgotten_castle"))
	var entry_number := posmod(_lore_id.hash(), 12) + 1
	return "start" if entry_number == 1 else "%s_%d" % [biome_id, entry_number]


func _record_discovery_once() -> bool:
	if _lore_id == "" or CharacterService == null:
		return false
	var discovered: Dictionary = CharacterService.get_flag("lore_discoveries", {}) as Dictionary
	if discovered.has(_lore_id):
		return false
	discovered[_lore_id] = true
	CharacterService.set_flag("lore_discoveries", discovered)
	CharacterService.set_flag("discoveries_found", int(CharacterService.get_flag("discoveries_found", 0)) + 1)
	var biome_id := str(get_meta("biome_id", "forgotten_castle"))
	var counter_id := "lore_%s_read" % biome_id
	CharacterService.set_flag(counter_id, int(CharacterService.get_flag(counter_id, 0)) + 1)
	QuestService.register_discovery(_lore_id)
	return true
