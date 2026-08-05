extends RefCounted
class_name AudioSettings

## Persisted bus volume levels (0–1 linear).

const SAVE_KEY := "audio"

static var master_volume: float = 1.0
static var music_volume: float = 1.0
static var sfx_volume: float = 1.0
static var ambience_volume: float = 1.0
static var ui_volume: float = 1.0


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
