extends RefCounted
class_name StatusCatalog

static var _definitions: Dictionary = {}


static func get_definition(status_id: String) -> Dictionary:
	_ensure_loaded()
	return _definitions.get(status_id, {})


static func tooltip(status_id: String, stacks: int = 1) -> String:
	var def := get_definition(status_id)
	if def.is_empty():
		return status_id
	var lines: Array[String] = [str(def.get("name", status_id))]
	var description := ContentText.description(def)
	if description != "":
		lines.append(description)
	var max_stacks := maxi(1, int(def.get("maxStacks", 1)))
	lines.append("Stacks: %d/%d" % [clampi(stacks, 1, max_stacks), max_stacks])
	var duration := float(def.get("duration", 0.0))
	if duration > 0.0:
		lines.append("Duration: %.1fs" % duration)
	var tick_damage := float(def.get("tickDamage", 0.0))
	var tick_heal := float(def.get("tickHeal", 0.0))
	var interval := float(def.get("tickInterval", 0.0))
	if tick_damage > 0.0 and interval > 0.0:
		lines.append("%g damage every %.1fs" % [tick_damage, interval])
	if tick_heal > 0.0 and interval > 0.0:
		lines.append("%g healing every %.1fs" % [tick_heal, interval])
	if float(def.get("speedMultiplier", 1.0)) != 1.0:
		lines.append("Action speed x%.2f" % float(def.get("speedMultiplier", 1.0)))
	if float(def.get("slowMultiplier", 1.0)) != 1.0:
		lines.append("Move speed x%.2f" % float(def.get("slowMultiplier", 1.0)))
	if float(def.get("damageTakenMultiplier", 1.0)) != 1.0:
		lines.append("Damage taken x%.2f" % float(def.get("damageTakenMultiplier", 1.0)))
	var stats: Dictionary = def.get("stats", {}) as Dictionary
	if float(stats.get("damagePercent", 0.0)) != 0.0:
		lines.append("Damage %+.1f%%" % float(stats.get("damagePercent", 0.0)))
	if float(stats.get("moveSpeedPercent", 0.0)) != 0.0:
		lines.append("Move speed %+.1f%%" % float(stats.get("moveSpeedPercent", 0.0)))
	if float(stats.get("healthRegen", 0.0)) != 0.0:
		lines.append("Health regeneration %+g" % float(stats.get("healthRegen", 0.0)))
	if float(stats.get("armor", 0.0)) != 0.0:
		lines.append("Armor %+g" % float(stats.get("armor", 0.0)))
	if bool(def.get("stunPulse", false)):
		var pulse := float(def.get("stunDuration", 0.0))
		lines.append("Pulses a %.2fs stun" % pulse)
	if bool(def.get("stackDecay", false)):
		lines.append("Loses one stack each duration")
	return "\n".join(lines)


static func _ensure_loaded() -> void:
	if not _definitions.is_empty():
		return
	var abs_dir := ContentLoader.content_path("content/statuses")
	var dir := DirAccess.open(abs_dir)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var data: Dictionary = ContentLoader.load_json("content/statuses/%s" % file_name)
			var status_id: String = data.get("id", "")
			if status_id != "":
				_definitions[status_id] = data
		file_name = dir.get_next()
	dir.list_dir_end()
