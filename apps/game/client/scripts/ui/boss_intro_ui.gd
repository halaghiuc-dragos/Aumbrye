extends Control


const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")

var _panel: PanelContainer
var _title_label: Label
var _subtitle_label: Label
var _tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()


## `BS-02`: `total_duration` sizes the fade-in/hold/fade-out so the label matches whatever the
## caller's camera framing/skip window is, instead of a hardcoded 2.9s that could outlast it.
func show_intro(boss_id: String, total_duration: float = 2.9) -> void:
	var def := EnemyCatalog.get_definition(boss_id)
	var title := str(def.get("title", def.get("name", boss_id)))
	var lore := str(def.get("loreText", ""))
	_title_label.text = title
	_subtitle_label.text = lore
	visible = true
	modulate.a = 0.0
	var fade_in := 0.35
	var fade_out := 0.45
	var hold := maxf(0.1, total_duration - fade_in - fade_out)
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 1.0, fade_in)
	_tween.tween_interval(hold)
	_tween.tween_property(self, "modulate:a", 0.0, fade_out)
	_tween.tween_callback(func() -> void: visible = false)


## Called when the player skips the intro sequence early -- cuts the fade instead of racing it.
func skip_intro() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	visible = false


func _build_ui() -> void:
	_panel = GameUISkinScript.make_center_panel(self, 360.0, 120.0)
	_panel.name = "Panel"
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 12)
	_panel.add_child(margin)
	var vbox := VBoxContainer.new()
	margin.add_child(vbox)
	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	GameUISkinScript.style_menu_title(_title_label)
	vbox.add_child(_title_label)
	_subtitle_label = Label.new()
	_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_subtitle_label)
