extends Node3D
class_name BiomeAmbienceEmitter


## Sparse, positional punctuation for rooms.  It intentionally does not loop: the profile layers
## already own the continuous bed, while these accents make a landmark feel local and memorable.
@export var biome_id := "forgotten_castle"
@export var min_interval := 13.0
@export var max_interval := 24.0
@export var hearing_radius := 30.0

var _remaining := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = hash("%s:%s" % [biome_id, global_position.snapped(Vector3(0.25, 0.25, 0.25))])
	_remaining = _rng.randf_range(2.0, 6.0)


func _process(delta: float) -> void:
	_remaining -= delta
	if _remaining > 0.0:
		return
	_remaining = _rng.randf_range(min_interval, max_interval)
	var camera := get_viewport().get_camera_3d()
	if camera == null or camera.global_position.distance_squared_to(global_position) > hearing_radius * hearing_radius:
		return
	if AudioDirector:
		AudioDirector.play_biome_accent(biome_id, global_position)
