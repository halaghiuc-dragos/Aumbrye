extends Node3D


const HubDioramaScript := preload("res://scripts/hub/hub_diorama.gd")
const CharacterCreateUIScript := preload("res://scripts/ui/character_create_ui.gd")
const PixelStyle := preload("res://scripts/art/style/pixel_diorama_style.gd")
const HubNpcScene := preload("res://scenes/hub/hub_npc.tscn")
const RainFieldScript := preload("res://scripts/art/world/rain_field.gd")

const INTERACT_HANDLERS := {
	"castle_portal": "_open_castle_menu",
	"endless_portal": "_open_endless_menu",
	"waves_portal": "_open_waves_menu",
	"skies_portal": "_show_coming_soon_skies",
	"cathedral_portal": "_show_coming_soon_cathedral",
	"arena_door": "_enter_arena",
	"blacksmith": "open_blacksmith",
	"merchant": "open_merchant",
	"storage": "open_storage",
	"quest_board": "open_quest_board",
	"appearance_mirror": "open_appearance_mirror",
}

@onready var _castle_portal_area: HubInteractable = $CastlePortal/InteractArea
@onready var _message_label: Label3D = $Player/MessageAnchor/MessageLabel
@onready var _tip_label: Label3D = $Player/MessageAnchor/TipLabel
@onready var _castle_menu: Control = $CastleEntryMenu
@onready var _endless_menu: Control = $UmbralEndlessMenu
@onready var _waves_menu: Control = $UmbralWavesMenu
@onready var _dialogue_ui: Control = $DialogueUI
@onready var _blacksmith_ui: Control = $BlacksmithUI
@onready var _merchant_ui: Control = $MerchantUI
@onready var _storage_ui: Control = $StorageUI
@onready var _quest_board_ui: Control = $QuestBoardUI

var _appearance_mirror_ui: Control

var _nearby: Array[String] = []
var _interactable_by_id: Dictionary = {}
var _current_prompt := ""
var _prompt_writes := 0
var _message_dismiss_armed := false


func _ready() -> void:
	PixelDioramaBootstrap.prime()
	_spawn_catalog_npcs()
	HubDioramaScript.apply(self)
	_appearance_mirror_ui = CharacterCreateUIScript.new()
	_appearance_mirror_ui.name = "AppearanceMirrorUI"
	add_child(_appearance_mirror_ui)
	_appearance_mirror_ui.appearance_saved.connect(_on_appearance_mirror_saved)
	call_deferred("_apply_pixel_diorama_to_scene")
	_register_interactables()
	_apply_npc_availability()
	_assert_interact_handlers()

	_connect_tip_refresh_sources()

	_dialogue_ui.closed.connect(_update_prompt)

	_castle_menu.dungeon_run_requested.connect(_on_dungeon_run)
	_castle_menu.continue_requested.connect(_on_castle_continue)
	_castle_menu.seed_run_requested.connect(_on_castle_seed_run)
	_endless_menu.endless_run_requested.connect(_on_endless_run)
	DungeonTierService.tier_unlocked.connect(_refresh_castle_portal_label)
	_endless_menu.continue_requested.connect(_on_endless_continue)
	_waves_menu.waves_run_requested.connect(_on_waves_run)
	_waves_menu.continue_requested.connect(_on_waves_continue)

	for npc in get_tree().get_nodes_in_group("hub_npc"):
		if npc.has_signal("dialogue_requested"):
			npc.dialogue_requested.connect(_on_npc_dialogue)
		if npc.has_signal("shop_requested"):
			npc.shop_requested.connect(_on_npc_shop)

	call_deferred("_face_spawn_view")
	_show_return_message()
	_refresh_castle_portal_label()
	# MD-07: lit before announced, not after -- the portal should already be glowing the moment
	# the card names it, not catch up a beat later via the deferred boot pass.
	_refresh_mode_portals()
	_announce_mode_unlocks()
	_announce_hub_growth()
	RunFlow.returned_to_hub.connect(_on_returned_to_hub)
	if not RunFlow.run_warning.is_connected(_on_run_warning):
		RunFlow.run_warning.connect(_on_run_warning)
	if InventoryService and not InventoryService.inventory_rejected.is_connected(_on_inventory_rejected):
		InventoryService.inventory_rejected.connect(_on_inventory_rejected)
	AudioDirector.play_hub_ambience()
	_attach_weather()
	call_deferred("_apply_player_viewmodel_theme")
	LocalSave.save_loaded.connect(_on_save_loaded)
	call_deferred("_boot_save_and_services")


func _face_spawn_view() -> void:
	var player := get_node_or_null("Player") as Node3D
	if player == null:
		return
	var arm := player.get_node_or_null("CameraPivot/SpringArm3D")
	if arm != null and arm.has_method("snap_look_direction"):
		arm.call("snap_look_direction", Vector3(0.0, 0.0, -1.0))


func _attach_weather() -> void:
	WeatherService.set_outdoors(true)
	var player := get_node_or_null("Player") as Node3D
	if player == null or get_node_or_null("RainField") != null:
		return
	var rain := Node3D.new()
	rain.set_script(RainFieldScript)
	add_child(rain)
	rain.call(
		"set_floor_extent", HubDioramaScript.FLOOR_WIDTH * 0.5, HubDioramaScript.FLOOR_DEPTH * 0.5
	)
	rain.call("setup", player)


func _exit_tree() -> void:
	WeatherService.set_outdoors(false)
	if DungeonTierService and DungeonTierService.tier_unlocked.is_connected(_refresh_castle_portal_label):
		DungeonTierService.tier_unlocked.disconnect(_refresh_castle_portal_label)
	if RunFlow.returned_to_hub.is_connected(_on_returned_to_hub):
		RunFlow.returned_to_hub.disconnect(_on_returned_to_hub)
	if RunFlow.run_warning.is_connected(_on_run_warning):
		RunFlow.run_warning.disconnect(_on_run_warning)
	if InventoryService and InventoryService.inventory_rejected.is_connected(_on_inventory_rejected):
		InventoryService.inventory_rejected.disconnect(_on_inventory_rejected)
	if LocalSave.save_loaded.is_connected(_on_save_loaded):
		LocalSave.save_loaded.disconnect(_on_save_loaded)


func _boot_save_and_services() -> void:
	var result: Dictionary = await LocalSave.sync_from_cloud()
	var synced: bool = bool(result.get("ok", false))
	var reloaded := false
	if not synced and LocalSave.has_save():
		reloaded = LocalSave.reload_active_into_services()
	if CharacterService.class_id == "":
		push_error(
			(
				"Hub: no class on the active character (id '%s') — returning to the main menu. "
				+ "The save was loaded but carries no classId."
			)
			% LocalSave.get_active_character_id()
		)
		SceneTransition.goto(get_tree(), "res://scenes/ui/main_menu.tscn")
		return
	if not reloaded:
		_on_save_loaded()
	_auto_equip_starting_weapon()
	LocalSave.autosave()
	show_hub_message("Welcome back, %s." % LocalSave.get_character_name())


func _spawn_catalog_npcs() -> void:
	var existing: Dictionary = {}
	for child in get_children():
		if not child.is_in_group("hub_npc"):
			continue
		var npc_node := child as NpcBase
		if npc_node != null:
			existing[npc_node.get_npc_id()] = true
		elif "npc_id" in child:
			existing[str(child.get("npc_id"))] = true
	for npc_id in NpcCatalog.get_all_ids():
		if existing.has(npc_id):
			continue
		var npc := HubNpcScene.instantiate()
		npc.name = "Npc_%s" % npc_id
		npc.set("npc_id", npc_id)
		add_child(npc)


func _apply_npc_availability() -> void:
	for node in get_tree().get_nodes_in_group("hub_npc"):
		var npc := node as NpcBase
		if npc != null:
			npc.set_available(npc.is_available())


func _on_save_loaded() -> void:
	HubTutorialService.load_from_save()
	_apply_npc_availability()
	if DungeonTierService and not DungeonTierService.tier_unlocked.is_connected(_on_tier_unlocked):
		DungeonTierService.tier_unlocked.connect(_on_tier_unlocked)
	_refresh_tip_surface()


func _on_tier_unlocked(_tier: int) -> void:
	_apply_npc_availability()


func _auto_equip_starting_weapon() -> void:
	if InventoryService.inventory.get_equipped_weapon_id() != "":
		return
	var class_id := CharacterService.class_id
	var weapon_id := (
		ClassCatalog.get_starting_weapon_item_id(class_id) if class_id != "" else "castle_sword"
	)
	InventoryService.equip_weapon_item(weapon_id)

func _apply_pixel_diorama_to_scene() -> void:
	PixelDioramaBootstrap.attach(self)


func _unhandled_input(event: InputEvent) -> void:
	if HubTutorialService.should_show_tips() and _handle_tip_input(event):
		get_viewport().set_input_as_handled()
		return
	# UX-09: every other sub-panel handles its own `ui_cancel` internally, but
	# `character_create_ui.gd` (reused here for the appearance mirror) does not -- it only exposes
	# `request_cancel()` for whoever opened it to call, which `main_menu.gd` does for the creation
	# flow but nothing here did for the hub's edit-mode instance. Escape/B silently did nothing.
	if (
		event.is_action_pressed("ui_cancel")
		and _appearance_mirror_ui != null
		and _appearance_mirror_ui.has_method("is_open")
		and _appearance_mirror_ui.call("is_open")
	):
		_appearance_mirror_ui.call("request_cancel")
		get_viewport().set_input_as_handled()
		return
	if _any_ui_open():
		return
	if not PlayerInput.interact_just_pressed(event):
		return
	var interact_id := _nearest_interact_id()
	if interact_id.is_empty():
		return
	get_viewport().set_input_as_handled()
	_dispatch_interact(interact_id)


func _handle_tip_input(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_cancel"):
		HubTutorialService.skip_all()
		_refresh_tip_surface()
		return true
	if event.is_action_pressed("ui_accept") or PlayerInput.interact_just_pressed(event):
		HubTutorialService.advance_tip()
		_refresh_tip_surface()
		return true
	return false


func open_loadout() -> void:
	PlayerControls.open_loadout()


func open_blacksmith() -> void:
	_blacksmith_ui.open()
	_update_prompt()


func open_merchant() -> void:
	_merchant_ui.open()
	_update_prompt()


func open_storage() -> void:
	_storage_ui.open()
	_update_prompt()


func open_quest_board() -> void:
	_quest_board_ui.open()
	_update_prompt()


func open_appearance_mirror() -> void:
	if _appearance_mirror_ui and _appearance_mirror_ui.has_method("open_edit_mode"):
		_appearance_mirror_ui.call("open_edit_mode")
	_update_prompt()


func _apply_player_viewmodel_theme() -> void:
	var player := get_node_or_null("Player") as CharacterBody3D
	if player == null:
		return
	var theme := PixelStyle.PaletteTheme.HUB
	if CharacterService:
		theme = CharacterService.appearance_theme as PixelStyle.PaletteTheme
	var director := player.get_node_or_null("AnimDirector")
	if director and director.has_method("set_viewmodel_theme"):
		director.call("set_viewmodel_theme", theme)


func _on_appearance_mirror_saved(_profile: Dictionary) -> void:
	show_hub_message("Appearance updated.")
	_apply_player_viewmodel_theme()
	_update_prompt()


const MESSAGE_DISMISS_ACTIONS: Array[StringName] = [
	&"move_forward",
	&"move_back",
	&"move_left",
	&"move_right",
	&"sprint",
	&"jump",
	&"dodge",
	&"interact",
]


func show_hub_message(message: String) -> void:
	_message_label.text = message
	_message_label.visible = message != ""
	_message_dismiss_armed = message != ""


func _dismiss_message_on_movement() -> void:
	if not _message_dismiss_armed:
		return
	for action in MESSAGE_DISMISS_ACTIONS:
		if InputMap.has_action(action) and Input.is_action_pressed(action):
			_clear_hub_message()
			return
	if Input.get_vector("move_left", "move_right", "move_forward", "move_back").length_squared() > 0.04:
		_clear_hub_message()


func _clear_hub_message() -> void:
	_message_dismiss_armed = false
	_message_label.text = ""
	_message_label.visible = false


func _process(_delta: float) -> void:
	_dismiss_message_on_movement()


func _ui_is_open(ui: Control) -> bool:
	return ui != null and ui.has_method("is_open") and ui.call("is_open")


func has_open_ui() -> bool:
	return _any_ui_open()


func _any_ui_open() -> bool:
	return (
		_ui_is_open(_castle_menu)
		or _ui_is_open(_endless_menu)
		or _ui_is_open(_waves_menu)
		or _ui_is_open(_dialogue_ui)
		or _ui_is_open(_blacksmith_ui)
		or _ui_is_open(_merchant_ui)
		or _ui_is_open(_storage_ui)
		or _ui_is_open(_quest_board_ui)
		or (
			_appearance_mirror_ui != null
			and _appearance_mirror_ui.has_method("is_open")
			and _appearance_mirror_ui.call("is_open")
		)
		or PlayerControls.is_player_meta_ui_open()
	)


func _register_interactables() -> void:
	_interactable_by_id.clear()
	for node in _find_interactables(self):
		var area := node as HubInteractable
		var area_id := area.get_interact_id()
		if area_id.is_empty():
			continue
		_interactable_by_id[area_id] = area
		area.player_entered.connect(_on_interact_enter.bind(area_id))
		area.player_exited.connect(_on_interact_exit.bind(area_id))


func _find_interactables(root: Node) -> Array:
	var found: Array = []
	for child in root.get_children():
		if child is HubInteractable:
			found.append(child)
		found.append_array(_find_interactables(child))
	return found


func _on_interact_enter(interact_id: String) -> void:
	_nearby.erase(interact_id)
	_nearby.append(interact_id)
	_update_prompt()


func _on_interact_exit(interact_id: String) -> void:
	_nearby.erase(interact_id)
	_update_prompt()


func _nearest_interact_id() -> String:
	if _nearby.is_empty():
		return ""
	var player := get_node_or_null("Player") as Node3D
	if player == null:
		return _nearby[_nearby.size() - 1]
	var origin := player.global_position
	var best_id := ""
	var best_dist := INF
	for interact_id in _nearby:
		var area: HubInteractable = _interactable_by_id.get(interact_id)
		if area == null or not area.is_player_near():
			continue
		var to_zone := area.get_focus_position() - origin
		to_zone.y = 0.0
		var dist := to_zone.length_squared()
		if dist < best_dist:
			best_dist = dist
			best_id = interact_id
	if best_id.is_empty():
		return _nearby[_nearby.size() - 1]
	return best_id


func _update_prompt() -> void:
	var next_text := ""
	if not _any_ui_open():
		var interact_id := _nearest_interact_id()
		if interact_id != "":
			var area: HubInteractable = _interactable_by_id.get(interact_id)
			if area != null:
				next_text = area.get_prompt()
	if next_text == _current_prompt:
		return
	_current_prompt = next_text
	_prompt_writes += 1


func _dispatch_interact(interact_id: String) -> void:
	if interact_id.begins_with("npc:"):
		_trigger_npc_interact(interact_id.substr(4))
		return
	if interact_id.begins_with("stray:"):
		_on_npc_dialogue("", interact_id.substr(6))
		return
	if not INTERACT_HANDLERS.has(interact_id):
		push_warning("Hub: no handler for interact_id '%s'" % interact_id)
		return
	var handler_name: String = INTERACT_HANDLERS[interact_id]
	if has_method(handler_name):
		call(handler_name)
	elif has_method(handler_name.trim_prefix("_")):
		call(handler_name.trim_prefix("_"))
	else:
		push_warning("Hub: handler '%s' missing for interact_id '%s'" % [handler_name, interact_id])


func _trigger_npc_interact(npc_id: String) -> void:
	for node in get_tree().get_nodes_in_group("hub_npc"):
		var npc := node as NpcBase
		if npc != null and npc.get_npc_id() == npc_id:
			npc.trigger_interact()
			return


func _open_castle_menu() -> void:
	_castle_menu.open_menu()


func _open_endless_menu() -> void:
	if not _require_mode_unlocked(ModeUnlockService.MODE_ENDLESS):
		return
	_endless_menu.open_menu()


func _open_waves_menu() -> void:
	if not _require_mode_unlocked(ModeUnlockService.MODE_WAVES):
		return
	_waves_menu.open_menu()


## Refuses a sealed portal and tells the player exactly what opens it.
func _require_mode_unlocked(mode_id: String) -> bool:
	if ModeUnlockService.is_unlocked(mode_id):
		return true
	show_hub_message(ModeUnlockService.lock_message(mode_id))
	AudioDirector.play_sfx("ui", Vector3.ZERO)
	return false


## A sealed portal stays visible and keeps its frame — it just goes dark and says what it wants.
## A visible locked door is a goal; a missing one is nothing.
func _refresh_mode_portals() -> void:
	for mode_id in ModeUnlockService.all_mode_ids():
		var node_name := ModeUnlockService.portal_node_name(mode_id)
		if node_name == "":
			continue
		var portal := get_node_or_null(node_name) as Node3D
		if portal == null:
			continue
		var area := portal.get_node_or_null("InteractArea") as HubInteractable
		if area == null:
			continue
		var unlocked := ModeUnlockService.is_unlocked(mode_id)
		if mode_id == ModeUnlockService.MODE_CASTLE:
			area.set_display_name(DungeonTierService.get_hub_portal_label())
		else:
			area.set_display_name(
				ModeUnlockService.display_name(mode_id)
				if unlocked
				else ModeUnlockService.locked_label(mode_id)
			)
		_set_portal_lit(portal, unlocked)


func _set_portal_lit(portal: Node3D, lit: bool) -> void:
	var glow := portal.get_node_or_null("DioramaVisuals/PortalGlow") as Node3D
	if glow != null:
		glow.visible = lit
	var hum := portal.get_node_or_null(HubDioramaScript.PORTAL_HUM_NAME) as AudioStreamPlayer3D
	if hum != null:
		if lit:
			if not hum.playing:
				hum.play()
		else:
			hum.stop()


## Celebrates a newly-opened portal exactly once, the first time the player is back in the hub.
## MD-07: unlocking a mode is one of maybe five genuinely new things that will ever happen to this
## player -- a hub message line undersold it. Now: the portal is already lit (see `_ready()`), a
## stinger plays, and the announce line gets a region-banner-sized card instead of the small
## world-space message label.
func _announce_mode_unlocks() -> void:
	var fresh := ModeUnlockService.consume_announcements()
	if fresh.is_empty():
		return
	for entry in fresh:
		var mode_name := str(entry.get("name", ""))
		var announce := str(entry.get("announce", ""))
		_show_mode_unlock_card(
			mode_name, announce if announce != "" else "%s has opened." % mode_name
		)
	AudioDirector.play_stinger("floor_clear")
	# MD-07/VS-09: the one hub moment that deserves the camera turning to look at something --
	# pans to the first newly-lit portal, reusing the reveal framing built for RM-09 secrets.
	var first_mode_id := str(fresh[0].get("id", ""))
	var portal_node_name := ModeUnlockService.portal_node_name(first_mode_id)
	if portal_node_name != "":
		var portal := get_node_or_null(portal_node_name) as Node3D
		var player := get_tree().get_first_node_in_group("player")
		if portal and player:
			var camera := (player as Node).get_node_or_null("CameraPivot/SpringArm3D")
			if camera and camera.has_method("play_reveal_framing"):
				camera.call("play_reveal_framing", portal.global_position)


## `SY-03`: names what physically changed in the plaza this run earned -- `HubDioramaScript`
## already built the matching prop into the scene during `_ready()`'s `HubDioramaScript.apply()`
## call, above; this is only the announcement half. Appended to whatever `_show_return_message()`
## already put in the hub message label rather than overwriting it -- a mode unlock is rare enough
## to earn the big card, but a hub-growth entry is common enough that fighting the welcome-back
## line for the same small label would mean one of the two never gets read.
func _announce_hub_growth() -> void:
	HubGrowthService.evaluate()
	var fresh := HubGrowthService.consume_announcements()
	if fresh.is_empty():
		return
	var names: Array[String] = []
	for entry in fresh:
		var growth_name := str(entry.get("name", ""))
		if growth_name != "":
			names.append(growth_name)
	if names.is_empty():
		return
	var line := tr("HUB_GROWTH_ANNOUNCE").format({"names": ", ".join(names)})
	if _message_label and _message_label.visible and _message_label.text != "":
		show_hub_message("%s  %s" % [_message_label.text, line])
	else:
		show_hub_message(line)
	AudioDirector.play_stinger("floor_clear")


const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")

var _mode_unlock_layer: CanvasLayer


func _show_mode_unlock_card(title: String, subtitle: String) -> void:
	if _mode_unlock_layer == null or not is_instance_valid(_mode_unlock_layer):
		_mode_unlock_layer = CanvasLayer.new()
		_mode_unlock_layer.name = "ModeUnlockLayer"
		_mode_unlock_layer.layer = 20
		add_child(_mode_unlock_layer)
	var card := VBoxContainer.new()
	card.name = "ModeUnlockCard"
	card.set_anchors_preset(Control.PRESET_CENTER_TOP)
	card.offset_top = 48.0
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_theme_constant_override("separation", 4)
	_mode_unlock_layer.add_child(card)
	var title_row := HBoxContainer.new()
	title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	title_row.add_theme_constant_override("separation", 12)
	card.add_child(title_row)
	var left_flourish := ColorRect.new()
	left_flourish.custom_minimum_size = Vector2(32, 3)
	left_flourish.color = GameUISkinScript.GOLD
	left_flourish.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_row.add_child(left_flourish)
	var title_label := Label.new()
	title_label.text = title
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	GameUISkinScript.style_menu_title(title_label)
	title_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	title_label.add_theme_constant_override("outline_size", 5)
	title_row.add_child(title_label)
	var right_flourish := ColorRect.new()
	right_flourish.custom_minimum_size = Vector2(32, 3)
	right_flourish.color = GameUISkinScript.GOLD
	right_flourish.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_row.add_child(right_flourish)
	var subtitle_label := Label.new()
	subtitle_label.text = subtitle
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle_label.custom_minimum_size = Vector2(480, 0)
	subtitle_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	GameUISkinScript.style_body_label(subtitle_label)
	subtitle_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	subtitle_label.add_theme_constant_override("outline_size", 4)
	card.add_child(subtitle_label)
	card.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(card, "modulate:a", 1.0, 0.6)
	tween.tween_interval(4.2)
	tween.tween_property(card, "modulate:a", 0.0, 0.8)
	tween.tween_callback(card.queue_free)


func _show_coming_soon_skies() -> void:
	show_hub_message("Aumbrye Skies is coming soon.")


func _show_coming_soon_cathedral() -> void:
	show_hub_message("Aumbrye Cathedral is coming soon.")


func _enter_arena() -> void:
	if Input.is_key_pressed(KEY_SHIFT):
		open_loadout()
	else:
		RunFlow.go_to_arena()


func _assert_interact_handlers() -> void:
	for interact_id in INTERACT_HANDLERS.keys():
		var handler_name: String = INTERACT_HANDLERS[interact_id]
		if not has_method(handler_name) and not has_method(handler_name.trim_prefix("_")):
			push_warning(
				"Hub: INTERACT_HANDLERS['%s'] -> missing method '%s'" % [interact_id, handler_name]
			)


func _refresh_castle_portal_label() -> void:
	if _castle_portal_area:
		_castle_portal_area.set_display_name(DungeonTierService.get_hub_portal_label())
	_refresh_mode_portals()


func _on_returned_to_hub(_message: String) -> void:
	_refresh_castle_portal_label()


func _show_return_message() -> void:
	if RunFlow.last_hub_message != "":
		show_hub_message(RunFlow.last_hub_message)
		RunFlow.last_hub_message = ""
	else:
		show_hub_message(_default_welcome_message())


## MD-06: the weekly challenge was announced nowhere outside the tower board it lives on -- this
## is the passive nudge for a player who never opens the board.
func _default_welcome_message() -> String:
	var base := "Welcome to Aumbrye Tower — explore the landmarks"
	var challenge := ChallengeService.get_active_challenge()
	if challenge.is_empty():
		return base
	var remaining := ChallengeService.format_remaining(int(challenge.get("endsInSeconds", 0)))
	return "%s. This week: %s (%s)." % [base, str(challenge.get("name", "")), remaining]


func _connect_tip_refresh_sources() -> void:
	if InventoryService:
		InventoryService.inventory_changed.connect(_on_tip_source_changed)
	if StorageService:
		StorageService.storage_changed.connect(_on_tip_source_changed)
	if CharacterService:
		CharacterService.flags_changed.connect(_on_tip_source_changed)
		CharacterService.quests_changed.connect(_on_tip_source_changed)
		CharacterService.gold_changed.connect(_on_tip_source_changed_int)
		CharacterService.level_changed.connect(_on_tip_source_changed_int)
	if DungeonTierService:
		DungeonTierService.tier_unlocked.connect(_on_tip_source_changed_int)


func _on_tip_source_changed() -> void:
	_refresh_tip_surface()


func _on_tip_source_changed_int(_value: int) -> void:
	_refresh_tip_surface()


func _refresh_tip_surface() -> void:
	if not HubTutorialService.should_show_tips():
		_tip_label.text = ""
		_tip_label.visible = false
		return
	var tip := HubTutorialService.get_current_tip()
	if tip.is_empty():
		_tip_label.text = ""
		_tip_label.visible = false
		return
	_tip_label.visible = true
	_tip_label.text = "%s (Esc to skip tips)" % tip


func _on_dungeon_run(dungeon_id: String, difficulty_tier: int = 1) -> void:
	RunFlow.start_new_run(dungeon_id, null, difficulty_tier)
	_refresh_hub_message()


func _on_castle_continue() -> void:
	RunFlow.continue_castle_run()
	_refresh_hub_message()


func _on_castle_seed_run(run_seed_value: int) -> void:
	var dungeon_id := DungeonCatalog.DEFAULT_DUNGEON_ID
	var difficulty_tier := 1
	if _castle_menu.has_method("get_selected_dungeon"):
		dungeon_id = str(_castle_menu.get_selected_dungeon())
	if _castle_menu.has_method("get_selected_difficulty_tier"):
		difficulty_tier = int(_castle_menu.get_selected_difficulty_tier())
	RunFlow.start_new_run(dungeon_id, run_seed_value, difficulty_tier)
	_refresh_hub_message()


func _on_endless_run(start_floor: int, skip_item_id: String) -> void:
	RunFlow.start_endless_run(start_floor, skip_item_id)
	_refresh_hub_message()


func _on_endless_continue() -> void:
	RunFlow.continue_endless_run()
	_refresh_hub_message()


func _on_waves_run() -> void:
	RunFlow.start_waves_run()
	_refresh_hub_message()


func _on_waves_continue() -> void:
	RunFlow.continue_waves_run()
	_refresh_hub_message()


func _refresh_hub_message() -> void:
	if RunFlow.last_hub_message != "":
		show_hub_message(RunFlow.last_hub_message)
		RunFlow.last_hub_message = ""


func _on_run_warning(message: String) -> void:
	show_hub_message(message)


func _on_inventory_rejected(reason: String) -> void:
	if reason == "full":
		show_hub_message("Inventory full.")


func _on_npc_dialogue(_npc_id: String, dialogue_id: String) -> void:
	_dialogue_ui.start_dialogue(dialogue_id)
	_update_prompt()


func _on_npc_shop(_npc_id: String, shop_type: String) -> void:
	match shop_type:
		"blacksmith":
			open_blacksmith()
		"merchant":
			open_merchant()
		"quest_board", "bounty_board":
			open_quest_board()
		"storage":
			open_storage()
