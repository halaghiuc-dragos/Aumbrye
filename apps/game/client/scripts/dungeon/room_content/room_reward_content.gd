extends "res://scripts/dungeon/room_content/room_content_base.gd"

const CHEST_SCENE := preload("res://scenes/loot/loot_chest.tscn")
const CURSE_EFFECT_ID := "cursed_cache"
const CURSE_DAMAGE_DEALT := -0.2
const CURSE_SECONDS := 240.0
const CURSE_TINT := Color(0.85, 0.2, 0.35)
const TIMED_SECONDS := 30.0

var _chest: Node3D


func configure(entry: Dictionary, _definition: Dictionary) -> void:
	_chest = CHEST_SCENE.instantiate() as Node3D
	_chest.name = "RewardChest"
	_chest.position = _anchor(0).position
	_content_root().add_child(_chest)
	if _chest.has_method("configure"):
		_chest.call("configure", {"items": entry.get("items", [])})
	var params: Variant = entry.get("params", {})
	var risk := str((params as Dictionary).get("risk", "")) if params is Dictionary else ""
	if risk == "cursed":
		_mark_cursed()
	elif risk == "timed":
		watch_room_entry(_start_countdown)


func get_chests() -> Array[Node3D]:
	return [_chest] if _chest != null else []


## A cursed cache glows red before it is touched, so taking the double reward is a choice, and
## opening it dulls the player's blows for the next few minutes.
func _mark_cursed() -> void:
	var light := OmniLight3D.new()
	light.light_color = CURSE_TINT
	light.light_energy = 0.9
	light.omni_range = 3.2
	light.shadow_enabled = false
	light.position.y = 1.2
	_chest.add_child(light)
	_chest.connect("opened", _on_cursed_chest_opened)


func _on_cursed_chest_opened() -> void:
	if RunBuffs:
		RunBuffs.add_temporary_effect(CURSE_EFFECT_ID, "physicalDamage", CURSE_DAMAGE_DEALT, CURSE_SECONDS)
	RunFlow.run_warning.emit(tr("ROOM_CURSE_TAKEN"))
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player and VfxService:
		VfxService.play_rune_flare(player.global_position + Vector3(0.0, 1.0, 0.0))


## A timed cache gives the player half a minute from stepping in to open it before it seals for good.
func _start_countdown(_player: Node3D) -> void:
	if _chest == null or bool(_chest.call("is_opened")):
		return
	RunFlow.run_warning.emit(tr("ROOM_TIMED_START") % int(TIMED_SECONDS))
	await get_tree().create_timer(TIMED_SECONDS).timeout
	if is_instance_valid(_chest) and not bool(_chest.call("is_opened")):
		_chest.call("seal")
		RunFlow.run_warning.emit(tr("ROOM_TIMED_LOST"))
