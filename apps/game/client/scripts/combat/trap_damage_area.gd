extends Area3D

## Applies DamageInfo to hurtboxes entering the area (traps, hazards).

@export var damage := 15.0
@export var poise_damage := 10.0
@export var damage_type := "physical"
@export var team := "trap"
@export var hit_interval := 0.5

var _cooldowns: Dictionary = {}


func _ready() -> void:
	area_entered.connect(_on_area_entered)
	monitoring = false


func _on_area_entered(area: Area3D) -> void:
	if not monitoring:
		return
	if not area.has_method("receive_hit"):
		return
	if area.get("team") == team:
		return
	var id := area.get_instance_id()
	var now := Time.get_ticks_msec() / 1000.0
	if _cooldowns.has(id) and now - _cooldowns[id] < hit_interval:
		return
	_cooldowns[id] = now
	var direction := (area.global_position - global_position).normalized()
	var info := DamageInfo.create(damage, poise_damage, self, damage_type, direction)
	area.call("receive_hit", info)
