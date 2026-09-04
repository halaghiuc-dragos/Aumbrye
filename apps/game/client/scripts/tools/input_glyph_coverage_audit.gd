extends Node

## AX-03: every action `InputMap` actually knows about, resolved to a glyph cell for every device
## family, must land on a real atlas cell rather than the "unknown" ? fallback.
##
## `InputGlyphService._cell_key_for_action()` reads the action's live binding first (keyboard key
## or joypad button/axis index) and only falls back to a per-action hardcoded cell when the action
## has no event of that family's type at all -- so this exercises the exact resolution path a real
## prompt takes, not a static list someone has to remember to update by hand.
##
## Run: godot --path apps/game/client --headless res://scenes/debug/input_glyph_coverage_audit.tscn

const InputGlyphServiceScript := preload("res://scripts/ui/input_glyph_service.gd")
const ATLAS_PATH := "content/ui/input_glyph_atlas.json"

## Godot's own reserved UI actions this project does not author prompts for (text-field caret
## movement, window/debugger traversal) -- excluded so the result reflects the ~44 actions this
## project actually authored, not every action GDScript ships with by default.
const SKIP_ACTIONS := [
	"ui_text_newline", "ui_text_indent", "ui_text_dedent", "ui_text_backspace",
	"ui_text_delete", "ui_text_completion_query", "ui_text_completion_accept",
	"ui_text_completion_replace", "ui_text_submit", "ui_text_caret_up",
	"ui_text_caret_down", "ui_text_caret_left", "ui_text_caret_right",
	"ui_text_caret_word_left", "ui_text_caret_word_right", "ui_text_caret_line_start",
	"ui_text_caret_line_end", "ui_text_caret_page_up", "ui_text_caret_page_down",
	"ui_text_scroll_up", "ui_text_scroll_down", "ui_text_select_all", "ui_text_select_word_under_caret",
	"ui_text_toggle_insert_mode", "ui_graph_duplicate", "ui_graph_delete", "ui_filedialog_up_one_level",
	"ui_filedialog_refresh", "ui_filedialog_show_hidden", "ui_swap_input_direction",
	"ui_undo", "ui_redo", "ui_menu", "ui_home", "ui_end", "ui_select", "ui_focus_next", "ui_focus_prev",
	"ui_copy", "ui_cut", "ui_paste",
]

var _failures: int = 0
var _checked: int = 0


func _ready() -> void:
	await get_tree().process_frame
	var manifest: Dictionary = ContentLoader.load_json(ATLAS_PATH)
	var cells: Dictionary = manifest.get("cells", {})
	if cells.is_empty():
		print("INPUT GLYPH COVERAGE RESULT 1 failures")
		print("  FAIL could not load atlas cells from %s" % ATLAS_PATH)
		get_tree().quit(1)
		return
	var families := [
		InputGlyphServiceScript.DeviceFamily.KEYBOARD,
		InputGlyphServiceScript.DeviceFamily.XBOX,
		InputGlyphServiceScript.DeviceFamily.PLAYSTATION,
	]
	for action in InputMap.get_actions():
		var action_name := str(action)
		if action_name in SKIP_ACTIONS:
			continue
		for family in families:
			_checked += 1
			# `_cell_key_for_action` is the same resolution `get_action_glyph_texture()` calls --
			# reused directly here (GDScript does not enforce the underscore as real privacy)
			# rather than re-deriving it, so this audit can never drift from what the game does.
			var cell_key: String = InputGlyphServiceScript._cell_key_for_action(action_name, family)
			if cell_key == "unknown" or cell_key == "" or not cells.has(cell_key):
				_fail(action_name, family, cell_key)
	print("INPUT GLYPH COVERAGE RESULT %d failures (%d action/family pairs checked)" % [_failures, _checked])
	get_tree().quit(1 if _failures > 0 else 0)


func _fail(action_name: String, family: int, cell_key: String) -> void:
	_failures += 1
	print("  FAIL %s [family %d] resolved to missing cell '%s'" % [action_name, family, cell_key])
