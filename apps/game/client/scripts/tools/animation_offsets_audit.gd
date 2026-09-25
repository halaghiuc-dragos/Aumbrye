extends Node3D

const CharacterSkinScript := preload("res://scripts/art/characters/diorama_character_skin.gd")
const AnimControllerScript := preload("res://scripts/art/characters/diorama_anim_controller.gd")

var _failures := 0

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)

func _ready() -> void:
	var facing := Node3D.new()
	add_child(facing)
	var visual: Node3D = CharacterSkinScript.build_player_body(facing)
	var controller: Node = AnimControllerScript.new()
	add_child(controller)
	controller.call("bind", visual)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(controller.call("is_bound"), "Generated player binds one primary animation controller")
	_check(visual.get_node_or_null("DioramaAdditivePlayer") == null, "No second AnimationPlayer writes additive tracks")
	var head: Node3D = CharacterSkinScript.find_part(visual, "Head")
	var torso: Node3D = CharacterSkinScript.find_part(visual, "Torso")
	var head_offset := head.get_node_or_null("HeadLookOffset") as Node3D if head else null
	var torso_recoil := torso.get_node_or_null("ImpactRecoilOffset") as Node3D if torso else null
	var breath_offset := torso_recoil.get_node_or_null("BreathOffset") as Node3D if torso_recoil else null
	var arm := CharacterSkinScript.find_part(visual, "ArmR")
	var arm_recoil := arm.get_node_or_null("ImpactRecoilOffset") as Node3D if arm else null
	_check(head_offset != null and breath_offset != null, "Visual offset pivots exist below tracked rig pivots")
	_check(arm_recoil != null and arm_recoil.get_child_count() > 0, "Arm recoil pivot wraps its visual geometry")
	_check(torso_recoil != null and breath_offset != null, "Torso recoil pivot composes around the breathing pivot")
	controller.call("set_head_look_offset", Vector3(0.15, -0.2, 0.0))
	_check(head_offset != null and head_offset.rotation.is_equal_approx(Vector3(0.15, -0.2, 0.0)), "Head look writes only its visual offset")
	controller.call("play_attack", 0.2, 0.2, 0.4)
	controller.call("play_impact_recoil", 0.8)
	_check(arm_recoil != null and arm_recoil.rotation.is_equal_approx(Vector3(0.256, 0.0, 0.4)), "Impact recoil writes an independent arm offset")
	_check(torso_recoil != null and torso_recoil.rotation.is_equal_approx(Vector3(-0.064, 0.0, 0.0)), "Impact recoil writes an independent torso offset")
	controller.call("play_stagger", 0.3)
	_check(arm_recoil != null and arm_recoil.rotation.is_zero_approx(), "Stagger immediately clears attacker recoil")
	_check(torso_recoil != null and torso_recoil.rotation.is_zero_approx(), "Stagger immediately clears torso recoil")
	controller.call("play_impact_recoil", 1.0)
	_check(arm_recoil != null and arm_recoil.rotation.is_zero_approx(), "Impact recoil cannot override a stagger pose")
	controller.call("play_death")
	_check(arm_recoil != null and arm_recoil.rotation.is_zero_approx(), "Death retains ownership of the final pose")
	await get_tree().create_timer(0.14).timeout
	_check(arm_recoil != null and arm_recoil.rotation.is_zero_approx(), "Arm recoil offset decays without overwriting its animated pose")
	_check(torso_recoil != null and torso_recoil.rotation.is_zero_approx(), "Torso recoil offset decays without overwriting its breathing pose")
	_check(controller.call("is_bound") and visual.get_node_or_null("DioramaAnimPlayer") != null, "Attack and recoil preserve primary rig animation ownership")
	print("ANIMATION OFFSETS RESULT %d failures" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)
