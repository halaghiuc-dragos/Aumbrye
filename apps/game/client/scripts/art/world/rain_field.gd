extends Node3D


const PixelStyle := preload("res://scripts/art/style/pixel_diorama_style.gd")

const FIELD_HALF := 20.0
const FALL_HEIGHT := 16.0
const MAX_DROPS := 420
const MAX_SPLASHES := 150
const WIND_PUSH := 9.0
const CAMERA_CLEARANCE := 2.6

const FALL_LIFETIME := 4.2

var _floor_half := Vector2(1e6, 1e6)

var _fall: CPUParticles3D
var _splash: CPUParticles3D
var _follow: Node3D
var _amount := 0.0
var _density_step := -1


func set_floor_extent(half_x: float, half_z: float) -> void:
	_floor_half = Vector2(maxf(0.0, half_x), maxf(0.0, half_z))


func setup(follow: Node3D) -> void:
	name = "RainField"
	_follow = follow
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	if WeatherService and not WeatherService.rain_changed.is_connected(_on_rain_changed):
		WeatherService.rain_changed.connect(_on_rain_changed)
	_on_rain_changed(WeatherService.rain_amount() if WeatherService else 0.0)


func _exit_tree() -> void:
	if WeatherService and WeatherService.rain_changed.is_connected(_on_rain_changed):
		WeatherService.rain_changed.disconnect(_on_rain_changed)


func _build() -> void:
	var drop_mesh := BoxMesh.new()
	drop_mesh.size = Vector3(0.018, 0.3, 0.018)
	var drop_mat := PixelStyle.make_custom_emissive(Color(0.62, 0.74, 0.92), 0.5)

	_fall = CPUParticles3D.new()
	_fall.name = "Fall"
	_fall.mesh = drop_mesh
	_fall.material_override = drop_mat
	_fall.amount = MAX_DROPS
	_fall.lifetime = FALL_LIFETIME
	_fall.preprocess = FALL_LIFETIME
	_fall.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	_fall.emission_ring_axis = Vector3(0.0, 1.0, 0.0)
	_fall.emission_ring_height = 1.0
	_fall.emission_ring_radius = FIELD_HALF
	_fall.emission_ring_inner_radius = CAMERA_CLEARANCE
	_fall.position = Vector3(0.0, FALL_HEIGHT, 0.0)
	_fall.direction = Vector3(0.0, -1.0, 0.0)
	_fall.spread = 0.0
	_fall.gravity = Vector3(0.0, -22.0, 0.0)
	_fall.initial_velocity_min = 9.0
	_fall.initial_velocity_max = 13.0
	_fall.scale_amount_min = 0.6
	_fall.scale_amount_max = 1.05
	_fall.emitting = false
	_fall.visibility_aabb = AABB(
		Vector3(-FIELD_HALF, -90.0, -FIELD_HALF),
		Vector3(FIELD_HALF * 2.0, FALL_HEIGHT + 92.0, FIELD_HALF * 2.0)
	)
	add_child(_fall)

	var splash_mesh := BoxMesh.new()
	splash_mesh.size = Vector3(0.09, 0.03, 0.09)
	_splash = CPUParticles3D.new()
	_splash.name = "Splash"
	_splash.mesh = splash_mesh
	_splash.material_override = PixelStyle.make_custom_emissive(Color(0.74, 0.84, 0.98), 0.7)
	_splash.amount = MAX_SPLASHES
	_splash.lifetime = 0.34
	_splash.preprocess = 0.5
	_splash.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_splash.emission_box_extents = Vector3(FIELD_HALF * 0.7, 0.02, FIELD_HALF * 0.7)
	_splash.position = Vector3(0.0, 0.08, 0.0)
	_splash.direction = Vector3(0.0, 1.0, 0.0)
	_splash.spread = 32.0
	_splash.gravity = Vector3(0.0, -14.0, 0.0)
	_splash.initial_velocity_min = 1.2
	_splash.initial_velocity_max = 2.4
	_splash.scale_amount_min = 0.5
	_splash.scale_amount_max = 1.2
	_splash.emitting = false
	_splash.visibility_aabb = AABB(
		Vector3(-FIELD_HALF, -1.0, -FIELD_HALF),
		Vector3(FIELD_HALF * 2.0, 4.0, FIELD_HALF * 2.0)
	)
	add_child(_splash)


const DENSITY_STEPS := 6


func _on_rain_changed(amount: float) -> void:
	var next := clampf(amount, 0.0, 1.0)
	var step := roundi(next * DENSITY_STEPS)
	if step == _density_step:
		return
	_density_step = step
	_amount = next
	var wet := step > 0
	var ratio := float(step) / float(DENSITY_STEPS)
	if _fall:
		_fall.emitting = wet
		_fall.amount = maxi(1, int(round(MAX_DROPS * ratio)))
	if _splash:
		_splash.emitting = wet
		_splash.amount = maxi(1, int(round(MAX_SPLASHES * ratio)))


func _process(_delta: float) -> void:
	if _follow != null and is_instance_valid(_follow):
		global_position = Vector3(_follow.global_position.x, 0.0, _follow.global_position.z)
	if _amount <= 0.01 or WindService == null:
		return
	var push: Vector3 = WindService.wind_vector() * WIND_PUSH
	if _fall:
		_fall.gravity = Vector3(push.x, -22.0, push.z)
	if _splash:
		_splash.gravity = Vector3(push.x * 0.25, -14.0, push.z * 0.25)
	_fit_splashes_to_floor()


func _fit_splashes_to_floor() -> void:
	if _splash == null:
		return
	var patch := FIELD_HALF * 0.7
	var origin := global_position
	for axis in 2:
		var centre: float = origin.x if axis == 0 else origin.z
		var limit: float = _floor_half.x if axis == 0 else _floor_half.y
		var low := maxf(centre - patch, -limit)
		var high := minf(centre + patch, limit)
		var half := maxf(0.0, (high - low) * 0.5)
		var mid := (low + high) * 0.5 - centre
		if axis == 0:
			_splash.emission_box_extents.x = half
			_splash.position.x = mid
		else:
			_splash.emission_box_extents.z = half
			_splash.position.z = mid
	_splash.emitting = (
		_amount > 0.01
		and _splash.emission_box_extents.x > 0.05
		and _splash.emission_box_extents.z > 0.05
	)
