extends Control


const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")

## UX-10: toast lane -- top-right, stacked. Every live instance repositions itself whenever one
## joins or leaves so the stack never overlaps or leaves a gap.
const TOAST_HEIGHT := 76.0
const TOAST_SPACING := 8.0
const TOAST_TOP := 40.0

static var _active_toasts: Array[Control] = []

@onready var _label: Label = $Panel/Margin/Label


func _ready() -> void:
	visible = false
	modulate.a = 0.0
	GameUISkinScript.apply_modal_menu(self, "Panel", "Backdrop")
	_active_toasts.append(self)
	_restack()
	tree_exiting.connect(_on_tree_exiting)


func show_achievement(display_name: String) -> void:
	_show(tr("ACHIEVEMENT_TOAST").format({"name": display_name}), Color.WHITE)


func show_loot(display_name: String, color: Color) -> void:
	_show(tr("LOOT_TOAST").format({"name": display_name}), color)


## SY-02: a quest's progress counter moving mid-run used to have no signal to show anything off
## of -- a toast rather than the banner lane, since a run can advance several quests in quick
## succession and the banner is one-at-a-time by design.
func show_quest_progress(title: String, count: int, required: int) -> void:
	_show(tr("QUEST_PROGRESS_TOAST").format({"title": title, "count": count, "required": required}), Color(0.75, 0.85, 1.0))


func _show(text: String, color: Color) -> void:
	_label.text = text
	_label.modulate = color
	visible = true
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.3)
	tween.tween_interval(2.5)
	tween.tween_property(self, "modulate:a", 0.0, 0.5)
	tween.tween_callback(queue_free)


func _on_tree_exiting() -> void:
	_active_toasts.erase(self)
	_restack()


func _restack() -> void:
	for i in _active_toasts.size():
		var toast := _active_toasts[i]
		if not is_instance_valid(toast):
			continue
		var target_top := TOAST_TOP + float(i) * (TOAST_HEIGHT + TOAST_SPACING)
		toast.offset_top = target_top
		toast.offset_bottom = target_top + TOAST_HEIGHT
