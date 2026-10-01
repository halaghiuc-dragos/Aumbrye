extends "res://scripts/dungeon/room_content/room_content_base.gd"

## A deliberately small decision room: one safe recovery choice or one painful, high-upside
## choice.  It uses the existing relic-offer UI rather than inventing a second upgrade screen.

const InteractPromptScript := preload("res://scripts/ui/interact_prompt.gd")
const PixelStyleScript := preload("res://scripts/art/style/pixel_diorama_style.gd")
const LightEmbersScript := preload("res://scripts/art/vfx/light_embers.gd")

const INTERACT_RADIUS := 1.75
const SOLACE_TINT := Color(0.35, 0.9, 0.68)
const PACT_TINT := Color(0.92, 0.25, 0.38)

var _claimed := false
var _player: Node3D
var _prompts: Dictionary = {}
var _pedestals: Dictionary = {}


func configure(_entry: Dictionary, _definition: Dictionary) -> void:
	var origin := _anchor(0).position
	_build_choice("solace", origin + Vector3(-1.55, 0.0, 0.0), SOLACE_TINT)
	_build_choice("pact", origin + Vector3(1.55, 0.0, 0.0), PACT_TINT)


func _build_choice(choice_id: String, local_position: Vector3, tint: Color) -> void:
	var root := _content_root()
	var pedestal := Node3D.new()
	pedestal.name = "PactShrine_%s" % choice_id.capitalize()
	pedestal.position = local_position
	root.add_child(pedestal)
	_pedestals[choice_id] = pedestal
	var base := MeshInstance3D.new()
	base.mesh = PropLibrary.bare_mesh("fx/pact_base")
	base.material_override = PixelStyleScript.make_prop_material(
		PixelStyleScript.theme_from_biome(str(get_meta("biome_id", BiomeRegistry.BIOME_CASTLE))), true
	)
	pedestal.add_child(base)
	var rune := MeshInstance3D.new()
	rune.mesh = PropLibrary.bare_mesh("fx/pact_rune")
	rune.position.y = 1.25
	rune.material_override = PixelStyleScript.make_glow_material(tint, tint * 0.35, 1.45)
	pedestal.add_child(rune)
	# Two different shrines should read as deliberate choices before the player enters prompt range.
	# The offset shards make a compact, pixel-clean crest rather than adding a second text panel.
	for offset in [Vector3(-0.36, 1.82, 0.0), Vector3(0.0, 2.06, 0.04), Vector3(0.36, 1.82, 0.0)]:
		var shard := MeshInstance3D.new()
		shard.name = "PactCrestShard"
		shard.mesh = PropLibrary.bare_mesh("fx/pact_shard")
		shard.position = offset
		shard.rotation.y = deg_to_rad(45.0)
		shard.material_override = PixelStyleScript.make_glow_material(tint.lightened(0.12), tint.darkened(0.3), 1.7)
		pedestal.add_child(shard)
	LightEmbersScript.attach(pedestal, Vector3(0.0, 1.32, 0.0), tint, 0.46, 0.48)
	var light := OmniLight3D.new()
	light.light_color = tint
	light.light_energy = 0.7
	light.omni_range = 3.0
	light.shadow_enabled = false
	light.position.y = 1.5
	pedestal.add_child(light)
	var prompt := InteractPromptScript.build(pedestal, Vector3(0.0, 2.55, 0.0))
	_prompts[choice_id] = prompt
	DungeonInteractionService.register_candidate(
		pedestal,
		pedestal,
		INTERACT_RADIUS,
		6,
		Callable(self, "_choose").bind(choice_id),
		Callable(self, "_can_choose"),
		Callable(self, "_set_prompt").bind(choice_id),
		true
	)


func _can_choose() -> bool:
	return not _claimed


func _set_prompt(active: bool, choice_id: String) -> void:
	var prompt := _prompts.get(choice_id) as InteractPrompt
	if prompt == null:
		return
	if not active or _claimed:
		prompt.hide_prompt()
		return
	if choice_id == "solace":
		prompt.show_text("Take Solace (heal + flask)")
	else:
		prompt.show_text("Blood Pact (-18% HP: power + relic)")


func _choose(choice_id: String) -> void:
	if _claimed:
		return
	_player = get_tree().get_first_node_in_group("player") as Node3D
	if _player == null:
		return
	_claimed = true
	if choice_id == "solace":
		_grant_solace()
	else:
		_grant_pact()
	for prompt in _prompts.values():
		if prompt is InteractPrompt:
			(prompt as InteractPrompt).hide_prompt()
	for pedestal in _pedestals.values():
		if pedestal is Node3D and is_instance_valid(pedestal):
			(pedestal as Node3D).scale = Vector3(0.82, 0.82, 0.82)
	DungeonInteractionService.refresh()


func _grant_solace() -> void:
	var health := _player.get_node_or_null("Health") as Health
	if health:
		health.heal(health.max_health * 0.3)
	var healer := _player.get_node_or_null("PlayerHeal") as PlayerHeal
	if healer:
		healer.grant_charge(1)
	if RunBuffs:
		RunBuffs.add_temporary_effect("shrine_solace", "staminaRegen", 0.35, 75.0)
	if VfxService:
		VfxService.play_rune_flare(_player.global_position + Vector3(0.0, 1.0, 0.0))
	if AudioDirector:
		AudioDirector.play_stinger("secret_found")


func _grant_pact() -> void:
	var health := _player.get_node_or_null("Health") as Health
	if health:
		# A pact must feel dangerous but can never turn a voluntary interaction into a cheap death.
		var cost := minf(health.max_health * 0.18, maxf(0.0, health.current - 1.0))
		health.take_damage(cost)
	if RunBuffs:
		RunBuffs.add_temporary_effect("shrine_blood_pact", "physicalDamage", 0.28, 120.0)
		RunBuffs.add_temporary_effect("shrine_blood_pact_poise", "poiseDamage", 0.22, 120.0)
	var offer_ui := get_tree().get_first_node_in_group("relic_offer_ui")
	if offer_ui and offer_ui.has_method("open_offer"):
		offer_ui.call("open_offer", "pact:%d:%s" % [RunFlow.current_floor, name])
	if VfxService:
		VfxService.play_rune_flare(_player.global_position + Vector3(0.0, 1.0, 0.0))
	if AudioDirector:
		AudioDirector.play_stinger("rare_drop")
