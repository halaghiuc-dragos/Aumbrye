extends Area3D


const DioramaSkin := preload("res://scripts/art/props/diorama_interactable_skin.gd")
const PixelStyle := preload("res://scripts/art/style/pixel_diorama_style.gd")
const INTERACT_RANGE := 3.0

enum State { DORMANT, ACTIVE }

var _state: State = State.DORMANT
var _label: Label3D
var _selected := false
var _confirm_pending := false
var _biome_id := BiomeRegistry.BIOME_CASTLE


func _ready() -> void:
	_label = get_node_or_null("Label3D") as Label3D
	if _label:
		_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	DungeonInteractionService.register_candidate(
		self,
		self,
		INTERACT_RANGE,
		4,
		Callable(self, "_interact"),
		Callable(self, "_is_active_state"),
		Callable(self, "_set_selected_prompt")
	)
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


func is_active() -> bool:
	return _state == State.ACTIVE


func _is_active_state() -> bool:
	return _state == State.ACTIVE


func _set_selected_prompt(active: bool) -> void:
	_selected = active
	_update_label()


func _interact() -> void:
	if _state != State.ACTIVE or _confirm_pending:
		return
	_confirm_pending = true
	var spec := ConfirmSpec.new()
	spec.title_key = &"EXIT_PORTAL_TITLE"
	spec.message_key = &"EXIT_PORTAL_MESSAGE"
	spec.confirm_key = &"EXIT_PORTAL_LEAVE"
	spec.cancel_key = &"EXIT_PORTAL_STAY"
	spec.pause_game = true
	spec.on_confirm = func() -> void:
		_confirm_pending = false
		AudioDirector.play_cue(&"portal_enter", global_position)
		var portal_def := PortalCatalog.resolve(_biome_id)
		var accent_hex := str(portal_def.get("interior", {}).get("color_accent", "#e6f5ff"))
		VfxService.play_portal_enter(global_position, PixelStyle.color_from_hex(accent_hex))
		RunFlow.complete_run_via_portal()
	spec.on_cancel = func() -> void:
		_confirm_pending = false
	MenuStack.confirm(spec)


func _update_label() -> void:
	if _label == null:
		return
	if _state != State.ACTIVE or not _selected:
		_label.visible = false
		return
	_label.text = InputGlyphService.format_interact_name(tr("EXIT_PORTAL_PROMPT"))
	_label.visible = true
