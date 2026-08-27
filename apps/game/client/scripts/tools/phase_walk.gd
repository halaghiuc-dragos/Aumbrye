extends Node


const HUB_SCENE := "res://scenes/hub/hub.tscn"
const ARENA_SCENE := "res://scenes/combat/combat_arena.tscn"
const WALK_CHARACTER := "PhaseWalk"

const SCENE_FRAMES := 90

const UI_SCENES := {
	"main_menu": "res://scenes/ui/main_menu.tscn",
	"character_create": "res://scenes/ui/character_create.tscn",
	"castle_entry": "res://scenes/ui/castle_entry_menu.tscn",
	"endless_menu": "res://scenes/ui/umbral_endless_menu.tscn",
	"waves_menu": "res://scenes/ui/umbral_waves_menu.tscn",
	"results": "res://scenes/ui/results_screen.tscn",
	"loading": "res://scenes/ui/loading_screen.tscn",
}

var _phase := ""


func _ready() -> void:
	_phase = _phase_arg()
	print("PHASE-BEGIN %s" % _phase)
	await get_tree().process_frame
	if RunFlow and not RunFlow.run_warning.is_connected(_on_run_warning):
		RunFlow.run_warning.connect(_on_run_warning)
	_ensure_playable_character()
	match _phase:
		"main_menu", "character_create", "castle_entry", "endless_menu", "waves_menu", \
		"results", "loading":
			await _walk_scene(str(UI_SCENES[_phase]), 40)
		"hub":
			await _walk_scene(HUB_SCENE, SCENE_FRAMES)
		"combat_arena":
			await _walk_scene(ARENA_SCENE, SCENE_FRAMES)
		"castle_run":
			_watch(); RunFlow.start_new_castle_run(); return
		"endless_run":
			_watch(); RunFlow.start_endless_run(1); return
		"waves_run":
			_watch(); RunFlow.start_waves_run(); return
		"challenge_run":
			_watch(); RunFlow.start_challenge_run(); return
		"floor_advance":
			_watch(func() -> void:
				RunFlow.ascend_floor()
				print("  advanced to floor %d" % RunFlow.get_current_floor()))
			RunFlow.start_new_castle_run()
			return
		"boss_fight":
			_watch(func() -> void:
				RunFlow.begin_boss_fight()
				print("  boss fight begun"))
			RunFlow.start_new_castle_run()
			return
		"run_complete":
			_watch(func() -> void:
				RunFlow.complete_run_via_portal()
				print("  run completed; results = %s" % str(not RunFlow.last_run_results.is_empty())))
			RunFlow.start_new_castle_run()
			return
		"return_to_hub":
			_watch(func() -> void:
				RunFlow.return_to_hub("phase walk")
				print("  returned to hub"))
			RunFlow.start_new_castle_run()
			return
		_:
			print("PHASE-ERROR unknown phase '%s'" % _phase)
			get_tree().quit(2)
			return
	print("PHASE-END %s" % _phase)
	get_tree().quit(0)


func _on_run_warning(message: String) -> void:
	print("PHASE-REFUSED %s: %s" % [_phase, message])
	get_tree().quit(0)


func _phase_arg() -> String:
	for arg in OS.get_cmdline_user_args():
		if str(arg).begins_with("--phase="):
			return str(arg).substr("--phase=".length())
	return "hub"


func _ensure_playable_character() -> void:
	if CharacterService.class_id != "":
		return
	LocalSave.queue_boot_new_game("knight", WALK_CHARACTER, {"theme": 0})
	if not LocalSave.execute_boot():
		print("PHASE-ERROR could not create a character to walk with: %s"
			% LocalSave.last_boot_failure)


func _walk_scene(path: String, frames: int) -> void:
	var packed := load(path) as PackedScene
	if packed == null:
		print("PHASE-ERROR could not load %s" % path)
		return
	var instance := packed.instantiate()
	add_child(instance)
	for method in ["open_menu", "open_creation", "open", "show_results", "open_panel"]:
		if instance.has_method(method):
			instance.call(method)
			break
	for i in frames:
		await get_tree().process_frame
	instance.queue_free()
	await get_tree().process_frame


func _watch(after: Callable = Callable()) -> void:
	var watcher := Node.new()
	watcher.name = "PhaseWatcher"
	watcher.process_mode = Node.PROCESS_MODE_ALWAYS
	watcher.set_script(load("res://scripts/tools/phase_watcher.gd"))
	watcher.set("phase_name", _phase)
	watcher.set("follow_up", after)
	get_tree().root.add_child.call_deferred(watcher)
