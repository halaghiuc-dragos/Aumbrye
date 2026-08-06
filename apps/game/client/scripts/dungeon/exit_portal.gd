extends Area3D

## Post-boss escape portal — confirmed interact ends the run (FLOW-2.1).

const DioramaSkin := preload("res://scripts/art/props/diorama_interactable_skin.gd")
const RunOutcomeConfirmScript := preload("res://scripts/ui/run_outcome_confirm.gd")

enum State { DORMANT, ACTIVE }

var _state: State = State.DORMANT
var _label: Label3D
var _near_player := false
var _confirm_pending := false
var _biome_id := BiomeRegistry.BIOME_CASTLE


func _ready() -> void:
	_label = get_node_or_null("Label3D") as Label3D
	if _label:
		_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	if not monitoring:
		visible = false


func configure(biome_id: String) -> void:
	_biome_id = biome_id
	set_meta("biome_id", biome_id)
	DioramaSkin.build_exit_portal(self, biome_id)


func activate() -> void:
	if _state == State.ACTIVE:
		return
	_state = State.ACTIVE
	monitoring = true
	visible = true
	_update_label()
	AudioDirector.play_cue(&"portal_open", global_position)
	VfxService.play_portal_activate(global_position)


func deactivate() -> void:
	_state = State.DORMANT
	_near_player = false
	_confirm_pending = false
	monitoring = false
	visible = false
	if _label:
		_label.visible = false


func is_active() -> bool:
	return _state == State.ACTIVE


func _unhandled_input(event: InputEvent) -> void:
	if _state != State.ACTIVE or not _near_player or not event.is_action_pressed("interact"):
		return
	get_viewport().set_input_as_handled()
	if _confirm_pending:
		return
	_confirm_pending = true
	RunOutcomeConfirmScript.ask(
		"Leave with your loot?",
		func() -> void:
			_confirm_pending = false
			AudioDirector.play_cue(&"portal_enter", global_position)
			RunFlow.complete_run_via_portal()
	)


func _on_body_entered(body: Node3D) -> void:
	if _state != State.ACTIVE:
		return
	if body is CharacterBody3D and body.is_in_group("player"):
		_near_player = true
		_update_label()


func _on_body_exited(body: Node3D) -> void:
	if body is CharacterBody3D and body.is_in_group("player"):
		_near_player = false
		_confirm_pending = false
		_update_label()


func _update_label() -> void:
	if _label == null:
		return
	if _state != State.ACTIVE or not _near_player:
		_label.visible = false
		return
	_label.text = "%s  Leave the dungeon" % InputGlyphService.format_interact_label()
	_label.visible = true
