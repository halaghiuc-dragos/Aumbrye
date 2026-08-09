extends RefCounted
class_name RunReplay

## Deterministic input capture keyed to a run seed. Samples are only appended when the
## gameplay input state actually changes, so a quiet stretch of a run costs nothing, and
## the stream is hard-capped so an opted-in recording can never grow the save without
## bound.

const META_KEY := "run_replay"
const OPT_IN_KEY := "replayRecordingEnabled"
const FORMAT_VERSION := 1
const ENTRY_BYTES := 8
const MAX_ENTRIES := 8192
const AXIS_QUANTUM := 100.0
const PLAYBACK_TAIL_TICKS := 120

## Bit index inside the packed action mask. Order is part of the on-disk format.
const ACTIONS: Array[StringName] = [
	&"sprint",
	&"jump",
	&"dodge",
	&"light_attack",
	&"heavy_attack",
	&"block",
	&"lock_on",
	&"interact",
	&"heal",
	&"two_hand",
	&"weapon_art",
	&"quick_slot_use",
	&"quick_slot_1",
	&"quick_slot_2",
	&"quick_slot_3",
	&"quick_slot_4",
]

static var _recording := false
static var _playing := false
static var _overflowed := false
static var _stream := PackedByteArray()
static var _entry_count := 0
static var _seed := 0
static var _floor := 0
static var _start_frame := 0
static var _last_frame := -1
static var _last_x := 0
static var _last_y := 0
static var _last_mask := 0
static var _play_entries: Array = []
static var _play_index := 0
static var _play_move := Vector2.ZERO
static var _play_mask := 0
static var _play_prev_mask := 0


static func recording_opt_in() -> bool:
	return bool(LocalSave.get_meta_data().get(OPT_IN_KEY, false))


static func set_recording_opt_in(value: bool) -> void:
	var meta := LocalSave.get_meta_data()
	meta[OPT_IN_KEY] = value
	LocalSave.set_meta_data(meta)


static func is_recording() -> bool:
	return _recording


static func is_playing() -> bool:
	return _playing


static func entry_count() -> int:
	return _entry_count


static func start_recording(seed_value: int, floor_index: int) -> bool:
	if _playing or not recording_opt_in():
		return false
	_reset_stream()
	_recording = true
	_seed = seed_value
	_floor = floor_index
	_start_frame = Engine.get_physics_frames()
	return true


static func stop_recording() -> void:
	_recording = false


static func discard() -> void:
	_reset_stream()
	_recording = false


## Sampled once per physics frame from the input gate. Cheap when idle: one frame-stamp
## compare and an early return whenever nothing is being recorded or replayed.
static func pump() -> void:
	if not _recording and not _playing:
		return
	var frame := Engine.get_physics_frames()
	if frame == _last_frame:
		return
	_last_frame = frame
	if _recording:
		_capture(frame)
	else:
		_advance_playback(frame)


static func _capture(frame: int) -> void:
	if _overflowed:
		return
	var move := Vector2.ZERO
	var mask := 0
	if not _gameplay_blocked():
		move = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
		for i in ACTIONS.size():
			if Input.is_action_pressed(ACTIONS[i]):
				mask |= 1 << i
	var qx := clampi(int(roundf(move.x * AXIS_QUANTUM)), -127, 127)
	var qy := clampi(int(roundf(move.y * AXIS_QUANTUM)), -127, 127)
	if qx == _last_x and qy == _last_y and mask == _last_mask and _entry_count > 0:
		return
	if _entry_count >= MAX_ENTRIES:
		_overflowed = true
		_recording = false
		return
	_last_x = qx
	_last_y = qy
	_last_mask = mask
	_append_entry(frame - _start_frame, qx, qy, mask)


static func _append_entry(tick: int, qx: int, qy: int, mask: int) -> void:
	var offset := _stream.size()
	_stream.resize(offset + ENTRY_BYTES)
	_stream.encode_u32(offset, maxi(tick, 0))
	_stream.encode_s8(offset + 4, qx)
	_stream.encode_s8(offset + 5, qy)
	_stream.encode_u16(offset + 6, mask)
	_entry_count += 1


static func _gameplay_blocked() -> bool:
	return PlayerControls != null and PlayerControls.gameplay_input_blocked()


static func _reset_stream() -> void:
	_stream = PackedByteArray()
	_entry_count = 0
	_overflowed = false
	_last_frame = -1
	_last_x = 0
	_last_y = 0
	_last_mask = 0


static func to_dictionary() -> Dictionary:
	return {
		"version": FORMAT_VERSION,
		"seed": _seed,
		"floor": _floor,
		"entries": _entry_count,
		"actions": _action_names(),
		"stream": Marshalls.raw_to_base64(_compress(_stream)),
	}


static func _action_names() -> Array:
	var names: Array = []
	for action in ACTIONS:
		names.append(String(action))
	return names


static func _compress(raw: PackedByteArray) -> PackedByteArray:
	if raw.is_empty():
		return raw
	return raw.compress(FileAccess.COMPRESSION_ZSTD)


static func _decompress(packed: PackedByteArray, expected_entries: int) -> PackedByteArray:
	if packed.is_empty():
		return packed
	return packed.decompress(expected_entries * ENTRY_BYTES, FileAccess.COMPRESSION_ZSTD)


## Persisted through the free-form meta blob so no save migration is involved.
static func save_to_meta() -> bool:
	if _entry_count <= 0:
		return false
	var meta := LocalSave.get_meta_data()
	meta[META_KEY] = to_dictionary()
	LocalSave.set_meta_data(meta)
	return true


static func load_from_meta() -> Dictionary:
	return LocalSave.get_meta_data().get(META_KEY, {})


static func clear_meta() -> void:
	var meta := LocalSave.get_meta_data()
	if not meta.has(META_KEY):
		return
	meta.erase(META_KEY)
	LocalSave.set_meta_data(meta)


static func decode(replay: Dictionary) -> Array:
	var entries: Array = []
	if int(replay.get("version", 0)) != FORMAT_VERSION:
		return entries
	var expected := int(replay.get("entries", 0))
	if expected <= 0 or expected > MAX_ENTRIES:
		return entries
	var raw := _decompress(
		Marshalls.base64_to_raw(str(replay.get("stream", ""))), expected
	)
	if raw.size() < expected * ENTRY_BYTES:
		return entries
	for i in expected:
		var offset := i * ENTRY_BYTES
		entries.append(
			{
				"tick": int(raw.decode_u32(offset)),
				"x": float(raw.decode_s8(offset + 4)) / AXIS_QUANTUM,
				"y": float(raw.decode_s8(offset + 5)) / AXIS_QUANTUM,
				"mask": int(raw.decode_u16(offset + 6)),
			}
		)
	return entries


static func replay_seed(replay: Dictionary) -> int:
	return int(replay.get("seed", 0))


static func start_playback(replay: Dictionary) -> bool:
	var entries := decode(replay)
	if entries.is_empty():
		return false
	_recording = false
	_play_entries = entries
	_play_index = 0
	_play_move = Vector2.ZERO
	_play_mask = 0
	_play_prev_mask = 0
	_seed = replay_seed(replay)
	_floor = int(replay.get("floor", 0))
	_start_frame = Engine.get_physics_frames()
	_last_frame = -1
	_playing = true
	return true


## Re-zeroes the playback clock at the same point in the run lifecycle where recording
## zeroed its own, so the two streams share an origin regardless of load time.
static func rebase_playback() -> void:
	if not _playing:
		return
	_start_frame = Engine.get_physics_frames()
	_last_frame = -1


static func stop_playback() -> void:
	_playing = false
	_play_entries = []
	_play_index = 0
	_play_move = Vector2.ZERO
	_play_mask = 0
	_play_prev_mask = 0


static func _advance_playback(frame: int) -> void:
	var tick := frame - _start_frame
	_play_prev_mask = _play_mask
	while _play_index < _play_entries.size():
		var entry: Dictionary = _play_entries[_play_index]
		if int(entry["tick"]) > tick:
			break
		_play_move = Vector2(float(entry["x"]), float(entry["y"]))
		_play_mask = int(entry["mask"])
		_play_index += 1
	if _play_index >= _play_entries.size() and tick > _playback_end_tick() + PLAYBACK_TAIL_TICKS:
		stop_playback()


static func _playback_end_tick() -> int:
	if _play_entries.is_empty():
		return 0
	return int((_play_entries[_play_entries.size() - 1] as Dictionary)["tick"])


static func playback_move_vector() -> Vector2:
	return _play_move


static func playback_pressed(action: StringName) -> bool:
	var bit := _action_bit(action)
	if bit < 0:
		return false
	return (_play_mask & (1 << bit)) != 0


static func playback_just_pressed(action: StringName) -> bool:
	var bit := _action_bit(action)
	if bit < 0:
		return false
	var flag := 1 << bit
	return (_play_mask & flag) != 0 and (_play_prev_mask & flag) == 0


static func _action_bit(action: StringName) -> int:
	return ACTIONS.find(action)
