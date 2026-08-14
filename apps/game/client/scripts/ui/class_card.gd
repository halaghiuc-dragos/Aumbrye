extends Button
class_name ClassCard

## Focusable class selection card with portrait, role, and stat pips.

const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")
const ClassIconAtlasScript := preload("res://scripts/ui/class_icon_atlas.gd")

## Two strengths and one weakness is what fits a card at this width without clipping.
const PIP_GAINS := 2
const PIP_LOSSES := 1
## One pip per rating point away from standard, so the strip tops out where the rating scale does.
const PIP_COUNT := ClassCatalog.RATING_MAX - ClassCatalog.RATING_STANDARD

var class_id: String = ""
var _selected_mark: TextureRect
var _stat_pips: HBoxContainer
var _portrait: TextureRect
var _name_label: Label
var _role_label: Label
var _built := false


func _ready() -> void:
	toggle_mode = true
	focus_mode = Control.FOCUS_ALL
	# Seven of these have to fit the class column without the last one falling under the fold.
	custom_minimum_size = Vector2(0, 78)
	_build_ui()


## Holds direct references to the widgets rather than looking them up by name. The nodes live
## inside the card's layout row, so the previous single-segment paths never resolved and every card
## rendered without its portrait, name or role.
func setup(class_def: Dictionary) -> void:
	_build_ui()
	class_id = str(class_def.get("id", ""))
	if _portrait:
		_portrait.texture = ClassIconAtlasScript.get_icon(
			class_id, str(class_def.get("iconPath", ""))
		)
	if _name_label:
		_name_label.text = str(class_def.get("name", class_id))
	if _role_label:
		var role_key := str(class_def.get("role", ""))
		var role_text := tr(role_key) if role_key != "" else ""
		if role_text == role_key:
			role_text = str(class_def.get("roleText", ""))
		_role_label.text = role_text
	_configure_stat_pips(class_def.get("statRatings", {}))


func set_selected_mark(visible_mark: bool) -> void:
	if _selected_mark:
		_selected_mark.visible = visible_mark


func _build_ui() -> void:
	if _built:
		return
	_built = true
	# A Button is not a container, so a child anchored to the full rect sits flush against the
	# card's border and the class name reads as if it were printed on the frame. The margin gives
	# the row the same inset the button's own text would have had.
	var inset := MarginContainer.new()
	inset.set_anchors_preset(Control.PRESET_FULL_RECT)
	inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		inset.add_theme_constant_override(side, 6)
	add_child(inset)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	inset.add_child(row)
	_portrait = TextureRect.new()
	_portrait.name = "Portrait"
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_portrait.custom_minimum_size = Vector2(58, 58)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(_portrait)
	var text_col := VBoxContainer.new()
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.add_theme_constant_override("separation", 2)
	row.add_child(text_col)
	_name_label = Label.new()
	_name_label.name = "NameLabel"
	GameUISkinScript.style_section_title(_name_label)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	text_col.add_child(_name_label)
	_role_label = Label.new()
	_role_label.name = "RoleLabel"
	GameUISkinScript.style_hint_label(_role_label)
	_role_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	text_col.add_child(_role_label)
	_stat_pips = HBoxContainer.new()
	_stat_pips.name = "StatPips"
	_stat_pips.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_stat_pips.add_theme_constant_override("separation", 6)
	text_col.add_child(_stat_pips)
	_selected_mark = TextureRect.new()
	_selected_mark.name = "SelectedMark"
	_selected_mark.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_selected_mark.custom_minimum_size = Vector2(12, 12)
	_selected_mark.visible = false
	row.add_child(_selected_mark)


func _configure_stat_pips(ratings: Variant) -> void:
	if _stat_pips == null:
		return
	for child in _stat_pips.get_children():
		child.queue_free()
	if not ratings is Dictionary:
		return
	# Only the class's defining stats. Every class now carries a value for all twelve, and drawing
	# a pip strip for each one overflowed the card several times over — a card has room to say what
	# a class is best and worst at, not to reproduce the comparison table.
	for entry in ClassCatalog.notable_stats(ratings as Dictionary, PIP_GAINS, PIP_LOSSES):
		var positive := int(entry.get("rating", ClassCatalog.RATING_STANDARD)) > ClassCatalog.RATING_STANDARD
		var pip_row := HBoxContainer.new()
		pip_row.add_theme_constant_override("separation", 3)
		var label := Label.new()
		label.text = _abbreviate_stat(str(entry.get("stat", "")))
		GameUISkinScript.style_hint_label(label)
		# The hint style word-wraps, which turns a two-letter abbreviation squeezed into this row
		# into one character per line.
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.custom_minimum_size = Vector2(20, 0)
		label.add_theme_color_override(
			"font_color",
			GameUISkinScript.STAT_DELTA_POSITIVE if positive else GameUISkinScript.STAT_DELTA_NEGATIVE
		)
		pip_row.add_child(label)
		var pips := HBoxContainer.new()
		pips.add_theme_constant_override("separation", 1)
		# One pip per rating point away from standard, so a pip means the same amount of power on
		# every stat and the strip reads as the same number the comparison table shows.
		var filled := clampi(int(entry.get("points", 1)), 1, PIP_COUNT)
		for i in PIP_COUNT:
			var pip := ColorRect.new()
			pip.custom_minimum_size = Vector2(6, 6)
			if i < filled:
				pip.color = (
					GameUISkinScript.STAT_DELTA_POSITIVE
					if positive
					else GameUISkinScript.STAT_DELTA_NEGATIVE
				)
			else:
				pip.color = Color(0.25, 0.25, 0.3)
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
		"manaMax":
			return "MP"
		"manaRegen":
			return "MR"
		_:
			return stat_name.substr(0, 2).to_upper()
