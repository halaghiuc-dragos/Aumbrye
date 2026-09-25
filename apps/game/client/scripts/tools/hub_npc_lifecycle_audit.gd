extends Node3D

const HubDioramaScript := preload("res://scripts/hub/hub_diorama.gd")
const HubNpcScene := preload("res://scenes/hub/hub_npc.tscn")

var _failures := 0


func _ready() -> void:
	var npc := HubNpcScene.instantiate() as NpcBase
	npc.npc_id = "blacksmith_aldric"
	add_child(npc)
	var npc_b := HubNpcScene.instantiate() as NpcBase
	npc_b.npc_id = "merchant_elara"
	add_child(npc_b)
	var npc_c := HubNpcScene.instantiate() as NpcBase
	npc_c.npc_id = "warden_mira"
	add_child(npc_c)
	HubDioramaScript._style_npc(npc)
	npc._resolve_visual()
	_check(npc.has_upper_body_look_pivot(), "catalog NPC has a head pivot rather than rotating its root")
	var far_phases := [float(npc.get("_far_update_timer")), float(npc_b.get("_far_update_timer")), float(npc_c.get("_far_update_timer"))]
	_check(far_phases[0] != far_phases[1] and far_phases[1] != far_phases[2], "distant NPC refresh phases are staggered by identity")
	npc.set_available(false)
	_check(not npc.visible and not npc.is_physics_processing() and not npc.is_available_cached(), "unavailable NPC is fully gated")
	npc.set_available(true)
	_check(npc.visible and npc.is_physics_processing() and npc.is_available_cached(), "available NPC resumes its inexpensive update loop")
	NpcBase.set_dialogue_ambient_suppressed(true)
	_check(NpcBase.is_dialogue_ambient_suppressed(), "dialogue suppresses nearby NPC murmurs")
	NpcBase.set_dialogue_ambient_suppressed(false)
	_check(not NpcBase.is_dialogue_ambient_suppressed(), "ambient murmurs resume only after dialogue closes")
	print("HUB NPC LIFECYCLE RESULT %d failures" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(label)
