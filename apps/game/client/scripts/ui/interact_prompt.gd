class_name InteractPrompt
extends Label3D

## HD-08: one interact-prompt look everywhere. `room_locked_door_content.gd` and
## `room_locked_vault_content.gd` used to build this Label3D by hand (each with its own font size
## and outline); `room_lore_content.gd`, `room_merchant_content.gd` and `room_npc_quest_content.gd`
## had no prompt at all, so interacting with them meant guessing that interact did something.

const InputGlyphServiceScript := preload("res://scripts/ui/input_glyph_service.gd")

const DEFAULT_COLOR := Color(1.0, 0.85, 0.35, 1.0)
const DEFAULT_LOCAL_POSITION := Vector3(0.0, 3.6, -1.5)

## Builds and attaches a hidden prompt as a child of `parent`, at `local_position` (the locked
## door's height above its socket by default -- override per prop where that does not fit).
static func build(parent: Node3D, local_position: Vector3 = DEFAULT_LOCAL_POSITION) -> Label3D:
	var prompt := Label3D.new()
	prompt.set_script(load("res://scripts/ui/interact_prompt.gd"))
	prompt.name = "InteractPrompt"
	prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	prompt.font_size = 24
	prompt.outline_size = 11
	prompt.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	prompt.modulate = DEFAULT_COLOR
	prompt.position = local_position
	prompt.visible = false
	parent.add_child(prompt)
	return prompt


## `InputGlyphService.format_interact_name(name)` -- "Read (E)", "Trade (E)".
func show_action(display_name: String) -> void:
	text = InputGlyphServiceScript.format_interact_name(display_name)
	visible = true


## For state-dependent text a plain action name can't express (locked vs. unlockable).
func show_text(raw_text: String) -> void:
	text = raw_text
	visible = true


func hide_prompt() -> void:
	visible = false
