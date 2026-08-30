extends Node3D


const DioramaSkin := preload("res://scripts/art/props/diorama_interactable_skin.gd")

signal lever_used(direction: String)

var _interact_area: Area3D
var _label: Label3D
var _anim: AnimationPlayer
var _audio: AudioStreamPlayer3D
var _handle: Node3D
var _near_player := false
var _unlocked := false
var _menu_open := false
var _floor_index := 1
var _can_ascend := true
var _can_descend := false
var _can_retreat := false


func _ready() -> void:
	var visual := get_node_or_null("Visual") as Node3D
	if visual == null:
		visual = Node3D.new()
		visual.name = "Visual"
		add_child(visual)
	_handle = visual.get_node_or_null("Handle") as Node3D
	if _handle == null:
		_handle = Node3D.new()
		_handle.name = "Handle"
		visual.add_child(_handle)
	if get_node_or_null(DioramaSkin.VISUAL_NAME) == null and visual.get_child_count() <= 1:
		DioramaSkin.build_lever(visual, DioramaSkin.resolve_biome(self))
	_interact_area = get_node_or_null("InteractArea") as Area3D
	_label = get_node_or_null("Label3D") as Label3D
	_anim = get_node_or_null("AnimationPlayer") as AnimationPlayer
	_audio = get_node_or_null("AudioStreamPlayer3D") as AudioStreamPlayer3D
	if _anim == null:
		_anim = AnimationPlayer.new()
		_anim.name = "AnimationPlayer"
		add_child(_anim)
		_setup_animations()
	if _interact_area:
		_interact_area.body_entered.connect(_on_body_entered)
		_interact_area.body_exited.connect(_on_body_exited)
	if AchievementService and not lever_used.is_connected(_notify_lever_used):
		lever_used.connect(_notify_lever_used)
	_update_label()


func configure(
	can_ascend: bool, can_descend: bool, can_retreat: bool = false, floor_index: int = 1
) -> void:
	_can_ascend = can_ascend
	_can_descend = can_descend
	_can_retreat = can_retreat
	_floor_index = maxi(1, floor_index)
	_update_label()


func unlock() -> void:
	_unlocked = true
	_play_anim("unlock")
	_play_cue("lever_unlock")
	_update_label()


func is_unlocked() -> bool:
	return _unlocked


func set_menu_open(open: bool) -> void:
	_menu_open = open
	_update_label()


func floor_options() -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	if _can_ascend:
		for pact in DescentPactService.offers_for_descent(
			RunFlow.current_seed, _floor_index + 1
		):
			(
				options
				. append(
					{
						"id": DescentPactService.option_id_for_pact(str(pact.get("id", ""))),
						"label":
						(
							"Descend to floor %d — %s (%s)"
							% [
								_floor_index + 1,
								str(pact.get("label", "Pact")),
								DescentPactService.describe(pact),
							]
						),
						"enabled": true,
						"reason": "",
					}
				)
			)
	options.append(
		{
			"id": "ascend",
			"label": "Ascend to floor %d" % (_floor_index + 1),
			"enabled": _can_ascend,
			"reason": _ascend_reason(),
		}
	)
	options.append(
		{
			"id": "descend",
			"label": "Descend to floor %d" % (_floor_index - 1),
			"enabled": _can_descend,
			"reason": _descend_reason(),
		}
	)
	options.append(
		{
			"id": "retreat",
			"label": "Retreat to the hub",
			"enabled": _can_retreat and RunFlow.can_retreat_to_hub(),
			"reason": _retreat_reason(),
		}
	)
	return options


## What the stair should tell the player before they choose. In the Long Dark that is the Waning:
## once the difficulty curve stops flattening, banking the run is a real decision and the player
## needs the number in front of them to make it.
func pressure_note() -> String:
	if RunFlow.get_run_mode() != RunModeConfig.MODE_ENDLESS:
		return ""
	return EndlessDifficulty.describe_pressure(_floor_index + 1)


func use(direction: String) -> void:
	if not _unlocked:
		return
	_play_anim("pull")
	_play_cue("lever_pull")
	VfxService.play_hit_spark(global_position + Vector3(0.0, 1.05, 0.0), Vector3.UP)
	lever_used.emit(direction)
	var pact_id := DescentPactService.pact_id_from_option(direction)
	if pact_id != "":
		RunFlow.set_pending_descent_pact(pact_id)
		RunFlow.ascend_floor()
		return
	if direction == "ascend":
		RunFlow.set_pending_descent_pact("")
		RunFlow.ascend_floor()
	elif direction == "descend":
		RunFlow.descend_floor()
	elif direction == "retreat" and RunFlow.can_retreat_to_hub():
		RunFlow.retreat_to_hub()


func _unhandled_input(event: InputEvent) -> void:
	if not PlayerInput.interact_just_pressed(event) or not _near_player or not _unlocked or _menu_open:
		return
	var menu := get_tree().get_first_node_in_group("stair_menu")
	if menu and menu.has_method("open_for_lever"):
		menu.call("open_for_lever", self, floor_options())
		get_viewport().set_input_as_handled()


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		_near_player = true
		_update_label()


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		_near_player = false
		_update_label()


func _update_label() -> void:
	if _label == null:
		return
	if _menu_open:
		_label.visible = false
		return
	if not _near_player:
		_label.visible = false
		return
	if not _unlocked:
		_label.text = "Sealed — defeat the floor boss"
		_label.visible = true
		return
	_label.text = InputGlyphService.format_interact_name("Stairs — floor %d" % _floor_index)
	_label.visible = true


func _ascend_reason() -> String:
	if _can_ascend:
		return ""
	if RunFlow.is_final_floor() and RunFlow.get_run_mode() != "endless":
		return "Ascend — floor %d is the highest" % _floor_index
	return "Ascend — unavailable"


func _descend_reason() -> String:
	if _can_descend:
		return ""
	if _floor_index <= 1:
		return "Descend — floor 1 is the lowest"
	if RunFlow.get_run_mode() == "endless":
		return "Descend — not available in endless mode"
	return "Descend — unavailable"


func _retreat_reason() -> String:
	if _can_retreat and RunFlow.can_retreat_to_hub():
		return ""
	if not _can_retreat:
		return "Retreat — not available in this mode"
	return "Retreat — defeat the boss first"


func _setup_animations() -> void:
	var handle_path := NodePath("Visual/Handle")
	if get_node_or_null("Visual/Handle") == null:
		handle_path = NodePath(".")
	var locked := Animation.new()
	locked.length = 1.0
	locked.loop_mode = Animation.LOOP_LINEAR
	var locked_track := locked.add_track(Animation.TYPE_ROTATION_3D)
	locked.track_set_path(locked_track, handle_path)
	locked.rotation_track_insert_key(locked_track, 0.0, Quaternion.from_euler(Vector3(0.0, 0.0, -0.12)))
	locked.rotation_track_insert_key(locked_track, 0.5, Quaternion.from_euler(Vector3(0.0, 0.0, 0.12)))
	locked.rotation_track_insert_key(locked_track, 1.0, Quaternion.from_euler(Vector3(0.0, 0.0, -0.12)))
	var unlock_anim := Animation.new()
	unlock_anim.length = 0.35
	var unlock_track := unlock_anim.add_track(Animation.TYPE_ROTATION_3D)
	unlock_anim.track_set_path(unlock_track, handle_path)
	unlock_anim.rotation_track_insert_key(
		unlock_track, 0.0, Quaternion.from_euler(Vector3(0.0, 0.0, -0.35))
	)
	unlock_anim.rotation_track_insert_key(
		unlock_track, 0.18, Quaternion.from_euler(Vector3(0.0, 0.0, 0.25))
	)
	unlock_anim.rotation_track_insert_key(
		unlock_track, 0.35, Quaternion.from_euler(Vector3(0.0, 0.0, 0.0))
	)
	var pull := Animation.new()
	pull.length = 0.28
	var pull_track := pull.add_track(Animation.TYPE_ROTATION_3D)
	pull.track_set_path(pull_track, handle_path)
	pull.rotation_track_insert_key(
		pull_track, 0.0, Quaternion.from_euler(Vector3(0.0, 0.0, 0.0))
	)
	pull.rotation_track_insert_key(
		pull_track, 0.12, Quaternion.from_euler(Vector3(0.55, 0.0, 0.0))
	)
	pull.rotation_track_insert_key(
		pull_track, 0.28, Quaternion.from_euler(Vector3(0.0, 0.0, 0.0))
	)
	var library := AnimationLibrary.new()
	library.add_animation("locked_idle", locked)
	library.add_animation("unlock", unlock_anim)
	library.add_animation("pull", pull)
	_anim.add_animation_library("", library)
	if not _unlocked:
		_anim.play("locked_idle")


func _play_anim(action_name: String) -> void:
	if _anim and _anim.has_animation(action_name):
		_anim.play(action_name)


func _play_cue(kind: String) -> void:
	if _audio:
		_audio.play()
	AudioDirector.play_sfx(kind, global_position)


func _notify_lever_used(direction: String) -> void:
	if AchievementService:
		AchievementService.notify("stair_lever_used", {"direction": direction})
