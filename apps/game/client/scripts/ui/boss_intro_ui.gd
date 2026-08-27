extends Control


const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")

var _panel: PanelContainer
var _title_label: Label
var _subtitle_label: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()


func show_intro(boss_id: String) -> void:
	var def := EnemyCatalog.get_definition(boss_id)
	var title := str(def.get("title", def.get("name", boss_id)))
	var lore := str(def.get("loreText", ""))
	_title_label.text = title
	_subtitle_label.text = lore
	visible = true
	modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.35)
	tween.tween_interval(2.2)
	tween.tween_property(self, "modulate:a", 0.0, 0.45)
	tween.tween_callback(func() -> void: visible = false)


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
