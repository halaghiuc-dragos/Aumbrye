extends "res://scripts/dungeon/room_content/room_content_base.gd"

const DIORAMA_SKIN := preload("res://scripts/art/props/diorama_interactable_skin.gd")
const InteractPromptScript := preload("res://scripts/ui/interact_prompt.gd")

const INTERACT_RANGE := 2.4

var _quest_key_id := ""
var _dialogue_id := "dungeon_npc_stranded"
var _npc: Node3D
var _prompt: InteractPrompt


func configure(entry: Dictionary, _definition: Dictionary) -> void:
	_quest_key_id = str(entry.get("questKeyId", ""))
	_dialogue_id = str(entry.get("dialogueId", _dialogue_id))
	_npc = Node3D.new()
	_npc.name = "QuestNpc"
	DIORAMA_SKIN.build_npc(_npc, DIORAMA_SKIN.resolve_biome(self))
	_npc.position = _anchor(0).position
	_content_root().add_child(_npc)
	_prompt = InteractPromptScript.build(_npc, Vector3(0.0, 2.4, 0.0))
	DungeonInteractionService.register_candidate(
		self,
		_npc,
		INTERACT_RANGE,
		3,
		Callable(self, "_talk"),
		Callable(),
		Callable(self, "_set_selected_prompt")
	)


func _set_selected_prompt(active: bool) -> void:
	if _prompt == null:
		return
	if active:
		_prompt.show_action(tr("NPC_QUEST_TALK"))
	else:
		_prompt.hide_prompt()


func _talk() -> void:
	var dialogue_ui := get_tree().get_first_node_in_group("dialogue_ui")
	if dialogue_ui and dialogue_ui.has_method("start_dialogue"):
		if dialogue_ui.call("start_dialogue", _dialogue_id):
			return
	# Missing dialogue is recoverable, never an implicit quest success. Keep the NPC present so the
	# player can retry after UI/content recovery and surface a visible explanation.
	if _prompt:
		_prompt.show_text(tr("DIALOGUE_UNAVAILABLE_RETRY"))
	if RunFlow:
		RunFlow.emit_run_warning(tr("DIALOGUE_UNAVAILABLE_RETRY"))
