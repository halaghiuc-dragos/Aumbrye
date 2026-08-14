class_name MenuShell
extends RefCounted

## Shared modal menu scaffold — backdrop, centered panel, title, content vbox.

const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")

const DEFAULT_BUTTON_MIN := Vector2(220, 36)
const DEFAULT_SEPARATION := 14


static func build_modal(
	parent: Control,
	title: String,
	half_w: float = GameUISkinScript.MENU_HALF_W,
	half_h: float = GameUISkinScript.MENU_HALF_H,
	clear_children: bool = true
) -> Dictionary:
	GameUISkinScript.ensure_full_rect(parent)
	if clear_children:
		for child in parent.get_children():
			child.queue_free()
	var backdrop: ColorRect = GameUISkinScript.make_backdrop(parent)
	var panel: PanelContainer = GameUISkinScript.make_center_panel(parent, half_w, half_h)
	panel.name = "Panel"
	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.add_theme_constant_override("margin_left", GameUISkinScript.PANEL_MARGIN)
	margin.add_theme_constant_override("margin_top", GameUISkinScript.PANEL_MARGIN)
	margin.add_theme_constant_override("margin_right", GameUISkinScript.PANEL_MARGIN)
	margin.add_theme_constant_override("margin_bottom", GameUISkinScript.PANEL_MARGIN)
	panel.add_child(margin)
	var content_vbox := VBoxContainer.new()
	content_vbox.name = "ContentVBox"
	content_vbox.add_theme_constant_override("separation", DEFAULT_SEPARATION)
	margin.add_child(content_vbox)
	if title != "":
		var title_label := Label.new()
		title_label.name = "TitleLabel"
		title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		GameUISkinScript.style_menu_title(title_label, title)
		content_vbox.add_child(title_label)
	return {"panel": panel, "content_vbox": content_vbox, "backdrop": backdrop, "margin": margin}


static func add_subtitle(parent: VBoxContainer, text: String) -> Label:
	var subtitle := Label.new()
	subtitle.text = text
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	GameUISkinScript.style_body_label(subtitle)
	parent.add_child(subtitle)
	return subtitle


static func add_hint(parent: VBoxContainer, text: String) -> Label:
	var hint := Label.new()
	hint.name = "HintLabel"
	hint.text = text
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	GameUISkinScript.style_hint_label(hint)
	# Safe here specifically because the hint owns a full panel row rather than sharing an HBox.
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(hint)
	return hint


static func make_menu_button(
	text: String, on_pressed: Callable, min_size: Vector2 = DEFAULT_BUTTON_MIN
) -> Button:
	var btn := GameUISkinScript.make_button(text)
	btn.custom_minimum_size = min_size
	btn.pressed.connect(on_pressed)
	return btn


static func add_button_row(parent: VBoxContainer, buttons: Array[Button]) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	for btn in buttons:
		row.add_child(btn)
	parent.add_child(row)
	return row


static func show_confirmation(
	parent: Control,
	title: String,
	message: String,
	on_confirm: Callable,
	on_cancel: Callable = Callable(),
	confirm_text: String = "Confirm",
	cancel_text: String = "Cancel"
) -> Control:
	var overlay := Control.new()
	overlay.name = "ConfirmOverlay"
	GameUISkinScript.ensure_full_rect(overlay)
	parent.add_child(overlay)
	overlay.move_to_front()
	var shell: Dictionary = build_modal(overlay, title, 300.0, 130.0)
	var vbox: VBoxContainer = shell["content_vbox"]
	var msg := Label.new()
	msg.text = message
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	GameUISkinScript.style_body_label(msg)
	vbox.add_child(msg)
	var cancel := make_menu_button(
		cancel_text,
		func() -> void:
			overlay.queue_free()
			if on_cancel.is_valid():
				on_cancel.call()
	)
	var confirm := make_menu_button(
		confirm_text,
		func() -> void:
			overlay.queue_free()
			on_confirm.call()
	)
	add_button_row(vbox, [cancel, confirm])
	cancel.focus_neighbor_right = confirm.get_path()
	confirm.focus_neighbor_left = cancel.get_path()
	cancel.grab_focus()
	return overlay
