extends RefCounted
class_name AudioSettings

## Persisted bus volume levels (0–1 linear).

const SAVE_KEY := "audio"

static var master_volume: float = 1.0
static var music_volume: float = 1.0
static var sfx_volume: float = 1.0
static var ambience_volume: float = 1.0
static var ui_volume: float = 1.0

static var _save_timer: SceneTreeTimer
const SAVE_DEBOUNCE_SEC := 0.5
static var _pending_commit := false
static var _changed_listeners: Array[Callable] = []


static func connect_changed(callback: Callable) -> void:
	if not _changed_listeners.has(callback):
		_changed_listeners.append(callback)


static func disconnect_changed(callback: Callable) -> void:
	_changed_listeners.erase(callback)


static func _notify_changed(setting_id: String, value: Variant) -> void:
	for callback in _changed_listeners:
		if callback.is_valid():
			if callback.get_argument_count() >= 2:
				callback.call(setting_id, value)
			else:
				callback.call()


static func apply_live(setting_id: String = "", value: Variant = null) -> void:
	apply()
	if setting_id != "":
		_notify_changed(setting_id, value)


static func request_commit() -> void:
	_pending_commit = true
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		commit()
		return
	if _save_timer != null and is_instance_valid(_save_timer):
		_save_timer.time_left = SAVE_DEBOUNCE_SEC
		return
	_save_timer = tree.create_timer(SAVE_DEBOUNCE_SEC)
	_save_timer.timeout.connect(_on_commit_timeout, CONNECT_ONE_SHOT)


static func commit() -> void:
	_pending_commit = false
	save()


static func _on_commit_timeout() -> void:
	if _pending_commit:
		commit()


static func load_from_save() -> void:
	var data: Dictionary = LocalSave.get_meta_data().get(SAVE_KEY, {})
	master_volume = float(data.get("master_volume", 1.0))
	music_volume = float(data.get("music_volume", 1.0))
	sfx_volume = float(data.get("sfx_volume", 1.0))
	ambience_volume = float(data.get("ambience_volume", 1.0))
	ui_volume = float(data.get("ui_volume", 1.0))
	apply()


static func save() -> void:
	var meta := LocalSave.get_meta_data()
	meta[SAVE_KEY] = {
		"master_volume": master_volume,
		"music_volume": music_volume,
		"sfx_volume": sfx_volume,
		"ambience_volume": ambience_volume,
		"ui_volume": ui_volume,
	}
	LocalSave.set_meta_data(meta)
	LocalSave.autosave()
	apply()
	_notify_changed("all", null)


static func apply() -> void:
	_set_bus_volume(&"Master", master_volume)
	_set_bus_volume(&"Music", music_volume)
	_set_bus_volume(&"SFX", sfx_volume)
	_set_bus_volume(&"Ambience", ambience_volume)
	_set_bus_volume(&"UI", ui_volume)


static func _set_bus_volume(bus_name: StringName, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	var clamped := clampf(linear, 0.0, 1.0)
	AudioServer.set_bus_volume_db(idx, linear_to_db(clamped) if clamped > 0.0001 else -80.0)
