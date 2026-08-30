extends Control

## What the last warden left behind.
##
## Dying stakes XP and gold on the floor where it happened. Walking back to it used to be a pure
## refund — you pressed a key and got your numbers returned, which makes death a tax rather than a
## thing that happens in the story.
##
## The shard now asks a question instead. Recover it and take the numbers back, or listen to it,
## leave them, and carry the umbral of that warden for the rest of this run. Every character in
## Aumbrye is an umbral — what a warden left behind — and this is where the game says so
## mechanically rather than only in the subtitle.

const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")
const MenuShellScript := preload("res://scripts/ui/menu_shell.gd")

signal recovered
signal listened
signal dismissed

var _open := false
var _buttons: Array[Button] = []
var _content: VBoxContainer


func _ready() -> void:
	add_to_group("umbral_shard_ui")
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shell: Dictionary = MenuShellScript.build_modal(
		self,
		tr("UMBRAL_TITLE"),
		GameUISkinScript.MENU_HALF_W + 20.0,
		GameUISkinScript.MENU_HALF_H + 40.0
	)
	_content = shell["content_vbox"]


func is_open() -> bool:
	return _open


func open_offer(xp_amount: int, gold_amount: int) -> void:
	if _open:
		return
	_open = true
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	MenuStack.push(self, true)
	_rebuild(xp_amount, gold_amount)


func close_menu() -> void:
	if not _open:
		return
	_open = false
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	MenuStack.pop(self)
	_buttons.clear()


func _rebuild(xp_amount: int, gold_amount: int) -> void:
	for child in _content.get_children():
		if child.name != "TitleLabel":
			child.queue_free()
	_buttons.clear()
	MenuShellScript.add_subtitle(_content, tr("UMBRAL_SUBTITLE"))

	var recover_label := (
		tr("UMBRAL_RECOVER_XP_GOLD").format({"xp": xp_amount, "gold": gold_amount})
		if gold_amount > 0
		else tr("UMBRAL_RECOVER_XP").format({"xp": xp_amount})
	)
	var recover := MenuShellScript.make_menu_button(recover_label, _on_recover)
	_content.add_child(recover)
	_buttons.append(recover)

	var listen := MenuShellScript.make_menu_button(tr("UMBRAL_LISTEN"), _on_listen)
	_content.add_child(listen)
	_buttons.append(listen)

	MenuShellScript.add_hint(_content, tr("UMBRAL_HINT"))
	var leave := MenuShellScript.make_menu_button(tr("UMBRAL_LEAVE"), _on_dismiss)
	_content.add_child(leave)
	_buttons.append(leave)
	recover.grab_focus()


func _on_recover() -> void:
	close_menu()
	recovered.emit()


func _on_listen() -> void:
	close_menu()
	listened.emit()


func _on_dismiss() -> void:
	close_menu()
	dismissed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_dismiss()
