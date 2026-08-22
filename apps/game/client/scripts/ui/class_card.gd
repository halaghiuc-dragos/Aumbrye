extends Button
class_name ClassCard

## Focusable class selection card: portrait, name and role.
##
## The two-letter stat strip — `DM`, `PS`, `MP` and the rest — is gone. It asked the player to learn
## an abbreviation for every stat before they could read a card, and the same numbers are already on
## the All Classes comparison table below the picker, spelled out in full and side by side, which is
## where a comparison belongs.

const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")
const ClassIconAtlasScript := preload("res://scripts/ui/class_icon_atlas.gd")

## Two strengths and one weakness is what fits a card at this width without clipping.
## One pip per rating point away from standard, so the strip tops out where the rating scale does.

var class_id: String = ""
var _selected_mark: TextureRect
var _portrait: TextureRect
var _name_label: Label
var _role_label: Label
var _built := false


func _ready() -> void:
	toggle_mode = true
	focus_mode = Control.FOCUS_ALL
	# Seven of these have to fit the class column without the last one falling under the fold.
	# 78 was a few pixels over: the column got a scroll bar that scrolled almost nothing, which is
	# worse than no bar at all because it looks like there is more roster below. Six pixels off each
	# card is 42 off the stack, and the portrait comes down with it so the card keeps its padding.
	custom_minimum_size = Vector2(0, 72)
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
	_portrait.custom_minimum_size = Vector2(52, 52)
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
	_selected_mark = TextureRect.new()
	_selected_mark.name = "SelectedMark"
	_selected_mark.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_selected_mark.custom_minimum_size = Vector2(12, 12)
	_selected_mark.visible = false
	row.add_child(_selected_mark)
