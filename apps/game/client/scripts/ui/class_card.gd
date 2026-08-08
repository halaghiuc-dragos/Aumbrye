extends Button
class_name ClassCard

## Focusable class selection card with portrait, role, and stat pips.

const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")
const ClassIconAtlasScript := preload("res://scripts/ui/class_icon_atlas.gd")

var class_id: String = ""
var _selected_mark: TextureRect
var _stat_pips: HBoxContainer


func _ready() -> void:
	toggle_mode = true
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = Vector2(0, 88)
	_build_ui()


func setup(class_def: Dictionary) -> void:
	class_id = str(class_def.get("id", ""))
	var portrait := get_node_or_null("Portrait") as TextureRect
	if portrait:
		portrait.texture = ClassIconAtlasScript.get_icon(
			class_id, str(class_def.get("iconPath", ""))
		)
	var name_label := get_node_or_null("NameLabel") as Label
	if name_label:
		name_label.text = str(class_def.get("name", class_id))
	var role_label := get_node_or_null("RoleLabel") as Label
	if role_label:
		var role_key := str(class_def.get("role", ""))
		var role_text := tr(role_key) if role_key != "" else ""
		if role_text == role_key:
			role_text = str(class_def.get("roleText", ""))
		role_label.text = role_text
	_configure_stat_pips(class_def.get("statBonuses", {}))


func set_selected_mark(visible_mark: bool) -> void:
	if _selected_mark:
		_selected_mark.visible = visible_mark


func _build_ui() -> void:
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 8)
	add_child(row)
	var portrait := TextureRect.new()
	portrait.name = "Portrait"
	portrait.custom_minimum_size = Vector2(64, 64)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(portrait)
	var text_col := VBoxContainer.new()
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.add_theme_constant_override("separation", 2)
	row.add_child(text_col)
	var name_label := Label.new()
	name_label.name = "NameLabel"
	GameUISkinScript.style_section_title(name_label)
	text_col.add_child(name_label)
	var role_label := Label.new()
	role_label.name = "RoleLabel"
	GameUISkinScript.style_hint_label(role_label)
	text_col.add_child(role_label)
	_stat_pips = HBoxContainer.new()
	_stat_pips.name = "StatPips"
	_stat_pips.add_theme_constant_override("separation", 4)
	text_col.add_child(_stat_pips)
	_selected_mark = TextureRect.new()
	_selected_mark.name = "SelectedMark"
	_selected_mark.custom_minimum_size = Vector2(12, 12)
	_selected_mark.visible = false
	row.add_child(_selected_mark)


func _configure_stat_pips(bonuses: Variant) -> void:
	if _stat_pips == null:
		return
	for child in _stat_pips.get_children():
		child.queue_free()
	if not bonuses is Dictionary:
		return
	for stat_name in (bonuses as Dictionary).keys():
		var pip_row := HBoxContainer.new()
		var label := Label.new()
		label.text = _abbreviate_stat(str(stat_name))
		GameUISkinScript.style_hint_label(label)
		pip_row.add_child(label)
		var pips := HBoxContainer.new()
		pips.add_theme_constant_override("separation", 1)
		var value := float((bonuses as Dictionary)[stat_name])
		var filled := clampi(int(round(absf(value) / 5.0)) + 1, 1, 5)
		for i in 5:
			var pip := ColorRect.new()
			pip.custom_minimum_size = Vector2(6, 6)
			pip.color = Color(0.45, 0.82, 0.45) if i < filled else Color(0.25, 0.25, 0.3)
			pips.add_child(pip)
		pip_row.add_child(pips)
		_stat_pips.add_child(pip_row)


func _abbreviate_stat(stat_name: String) -> String:
	match stat_name:
		"maxHealth":
			return "HP"
		"armor":
			return "AR"
		"moveSpeed":
			return "SP"
		"critChance":
			return "CR"
		"physicalDamage":
			return "DM"
		"poiseDamage":
			return "PS"
		"staminaRegen":
			return "RG"
		"staminaMax":
			return "ST"
		"poise":
			return "PO"
		"blockReduction":
			return "BL"
		_:
			return stat_name.substr(0, 2).to_upper()
