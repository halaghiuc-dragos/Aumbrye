class_name QuickSlotBar
extends HBoxContainer


const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")
const ItemIconAtlasScript := preload("res://scripts/ui/item_icon_atlas.gd")
const InputGlyphServiceScript := preload("res://scripts/ui/input_glyph_service.gd")

const SLOT_SIZE := Vector2(44.0, 44.0)
const SELECTED_TINT := Color(1.0, 0.92, 0.62, 1.0)
const IDLE_TINT := Color(0.62, 0.60, 0.56, 1.0)
const EMPTY_ALPHA := 0.28

var _slots: Array[PanelContainer] = []


func _ready() -> void:
	name = "QuickSlotBar"
	add_theme_constant_override("separation", GameUISkinScript.PIXEL_UNIT * 2)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	if InventoryService:
		if not InventoryService.inventory_changed.is_connected(refresh):
			InventoryService.inventory_changed.connect(refresh)
		if not InventoryService.quick_slots_changed.is_connected(refresh):
			InventoryService.quick_slots_changed.connect(refresh)
	if WavesRunService and not WavesRunService.inventory_changed.is_connected(refresh):
		WavesRunService.inventory_changed.connect(refresh)
	if PlayerControls:
		if not PlayerControls.quick_slot_used.is_connected(_on_quick_slot_used):
			PlayerControls.quick_slot_used.connect(_on_quick_slot_used)
		if not PlayerControls.quick_slot_selection_changed.is_connected(_on_selection_changed):
			PlayerControls.quick_slot_selection_changed.connect(_on_selection_changed)
	refresh()


func _exit_tree() -> void:
	if InventoryService == null:
		return
	if InventoryService.inventory_changed.is_connected(refresh):
		InventoryService.inventory_changed.disconnect(refresh)
	if InventoryService.quick_slots_changed.is_connected(refresh):
		InventoryService.quick_slots_changed.disconnect(refresh)
	if WavesRunService and WavesRunService.inventory_changed.is_connected(refresh):
		WavesRunService.inventory_changed.disconnect(refresh)


func _build() -> void:
	_slots.clear()
	for i in _slot_count():
		var pip := PanelContainer.new()
		pip.name = "QuickSlot%d" % i
		pip.custom_minimum_size = SLOT_SIZE
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pip.add_theme_stylebox_override("panel", GameUISkinScript.make_panel_style())

		var stack := Control.new()
		stack.name = "Stack"
		stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pip.add_child(stack)

		var icon := TextureRect.new()
		icon.name = "Icon"
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack.add_child(icon)

		var key := Label.new()
		key.name = "Key"
		key.set_anchors_preset(Control.PRESET_TOP_LEFT)
		key.text = str(i + 1)
		key.mouse_filter = Control.MOUSE_FILTER_IGNORE
		GameUISkinScript.style_hint_label(key)
		stack.add_child(key)

		var count := Label.new()
		count.name = "Count"
		count.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		count.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		count.grow_vertical = Control.GROW_DIRECTION_BEGIN
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		count.mouse_filter = Control.MOUSE_FILTER_IGNORE
		GameUISkinScript.style_hint_label(count)
		stack.add_child(count)

		add_child(pip)
		_slots.append(pip)


func _slot_count() -> int:
	if PlayerControls:
		return int(PlayerControls.QUICK_SLOT_COUNT)
	return 4


func refresh() -> void:
	if InventoryService == null:
		return
	var selected := PlayerControls.get_quick_slot_selected() if PlayerControls else 0
	for i in _slots.size():
		var pip := _slots[i]
		if not is_instance_valid(pip):
			continue
		var icon := pip.get_node_or_null("Stack/Icon") as TextureRect
		var count := pip.get_node_or_null("Stack/Count") as Label
		var source := InventoryService.active_inventory()
		var idx := InventoryService.get_quick_slot_index(i)
		var has_item := idx >= 0 and idx < source.slots.size()
		if has_item:
			var slot: Dictionary = source.slots[idx]
			var item_id := str(slot.get("itemId", ""))
			var def := ItemCatalog.get_definition(item_id)
			if icon:
				icon.texture = ItemIconAtlasScript.get_icon(item_id, str(def.get("iconPath", "")))
				icon.modulate.a = 1.0
			var qty := int(slot.get("quantity", 1))
			if count:
				count.text = str(qty) if qty > 1 else ""
		else:
			if icon:
				icon.texture = null
				icon.modulate.a = EMPTY_ALPHA
			if count:
				count.text = ""
		pip.modulate = SELECTED_TINT if i == selected else IDLE_TINT


func _on_selection_changed(_index: int) -> void:
	refresh()


func _on_quick_slot_used(index: int, _item_id: String) -> void:
	refresh()
	if index < 0 or index >= _slots.size():
		return
	var pip := _slots[index]
	if not is_instance_valid(pip) or not pip.is_inside_tree():
		return
	var tween := pip.create_tween()
	tween.tween_property(pip, "modulate", Color(1.6, 1.5, 1.1, 1.0), 0.06)
	tween.tween_property(pip, "modulate", SELECTED_TINT, 0.18)
