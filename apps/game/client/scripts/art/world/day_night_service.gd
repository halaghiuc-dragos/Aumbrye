extends Node


const FALLBACK_CYCLE_SECONDS := 1200.0

const HORIZON_FADE_DEG := 6.0

const CELESTIAL_POLE := Vector3(
	0.0, sin(deg_to_rad(Celestial.LATITUDE_DEG)), -cos(deg_to_rad(Celestial.LATITUDE_DEG))
)

const MOON_LIGHT_NAME := "MoonLight"
const MOON_COLOR := Color(0.62, 0.70, 0.95)
const MOON_ENERGY := 0.45

var _environment: WeakRef
var _sun: WeakRef
var _fill: WeakRef
var _profile_id := ""

var _stops: Array = []
var _cycle_seconds := FALLBACK_CYCLE_SECONDS

var dim := 1.0
var _moon_elongation_cos := 0.0
var fog_boost := 1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func register_level(env: Environment, sun: DirectionalLight3D, fill: DirectionalLight3D, profile_id: String) -> void:
	_environment = weakref(env) if env else null
	_sun = weakref(sun) if sun else null
	_fill = weakref(fill) if fill else null
	_profile_id = profile_id
	_apply(phase())


func clear_level() -> void:
	dim = 1.0
	fog_boost = 1.0
	_environment = null
	_sun = null
	_fill = null
	_profile_id = ""


func phase() -> float:
	var cycle := cycle_seconds()
	if cycle <= 0.0:
		return 0.0
	return fposmod(LocalSave.get_playtime_seconds(), cycle) / cycle


func day() -> float:
	var cycle := cycle_seconds()
	if cycle <= 0.0:
		return 0.0
	return floorf(LocalSave.get_playtime_seconds() / cycle)


func night_amount() -> float:
	var elevation := Celestial.elevation_deg(Celestial.sun_direction(phase(), day()))
	return clampf(inverse_lerp(3.0, -8.0, elevation), 0.0, 1.0)


func cycle_seconds() -> float:
	_ensure_loaded()
	return _cycle_seconds


func clock_text() -> String:
	var minutes := int(phase() * 24.0 * 60.0)
	@warning_ignore("integer_division")
	return "%02d:%02d" % [minutes / 60, minutes % 60]


func is_night() -> bool:
	return night_amount() > 0.5


func _process(_delta: float) -> void:
	if _environment == null or _environment.get_ref() == null:
		return
	_apply(phase())


func _ensure_loaded() -> void:
	if not _stops.is_empty():
		return
	var block: Dictionary = VisualLighting.day_night_block()
	_cycle_seconds = float(block.get("cycle_seconds", FALLBACK_CYCLE_SECONDS))
	var stops: Array = block.get("stops", [])
	if stops.is_empty():
		push_error("DayNightService: no day_night stops in the lighting data")
		return
	var sorted := stops.duplicate()
	sorted.sort_custom(
		func(a: Variant, b: Variant) -> bool:
			return float((a as Dictionary).get("at", 0.0)) < float((b as Dictionary).get("at", 0.0))
	)
	_stops = sorted


func _bracket(p: float) -> Dictionary:
	var count := _stops.size()
	var before: Dictionary = _stops[count - 1]
	var after: Dictionary = _stops[0]
	var from := float(before.get("at", 0.0)) - 1.0
	var to := float(after.get("at", 0.0))
	for i in count:
		var stop: Dictionary = _stops[i]
		var at := float(stop.get("at", 0.0))
		if at > p:
			after = stop
			to = at
			before = _stops[(i - 1 + count) % count]
			from = float(before.get("at", 0.0))
			if i == 0:
				from -= 1.0
			break
		if i == count - 1:
			before = stop
			from = at
			after = _stops[0]
			to = float(after.get("at", 0.0)) + 1.0
	var span := maxf(0.0001, to - from)
	var t := clampf((p - from) / span, 0.0, 1.0)
	return {"from": before, "to": after, "t": t * t * (3.0 - 2.0 * t)}


func _apply(p: float) -> void:
	_ensure_loaded()
	if _stops.is_empty():
		return
	var bracket := _bracket(p)
	var a: Dictionary = bracket["from"]
	var b: Dictionary = bracket["to"]
	var t: float = bracket["t"]

	var to_sun := Celestial.sun_direction(p, day())
	var to_moon := Celestial.moon_direction(p, day())
	var lit_fraction := Celestial.illuminated_fraction(day())

	var sun := _sun.get_ref() as DirectionalLight3D if _sun else null
	if sun and is_instance_valid(sun):
		sun.global_transform = Transform3D(Celestial.light_basis(to_sun), sun.global_position)
		sun.light_color = _col(a, "sun_color").lerp(_col(b, "sun_color"), t)
		var energy := lerpf(_num(a, "sun_energy", 1.0), _num(b, "sun_energy", 1.0), t) * dim
		energy *= clampf(Celestial.elevation_deg(to_sun) / HORIZON_FADE_DEG + 1.0, 0.0, 1.0)
		sun.light_energy = energy
		sun.visible = energy > 0.005

	_apply_moon(to_moon, to_sun, lit_fraction)

	var fill := _fill.get_ref() as DirectionalLight3D if _fill else null
	if fill and is_instance_valid(fill):
		fill.light_color = _col(a, "fill_color").lerp(_col(b, "fill_color"), t)
		fill.light_energy = (
			lerpf(_num(a, "fill_energy", 0.2), _num(b, "fill_energy", 0.2), t) * dim
		)

	var env := _environment.get_ref() as Environment if _environment else null
	if env == null or not is_instance_valid(env):
		return
	env.ambient_light_color = _col(a, "ambient_color").lerp(_col(b, "ambient_color"), t)
	env.ambient_light_energy = (
		lerpf(_num(a, "ambient_energy", 0.3), _num(b, "ambient_energy", 0.3), t) * dim
	)
	if env.fog_enabled:
		env.fog_light_color = _col(a, "fog_color").lerp(_col(b, "fog_color"), t)
		env.fog_density = (
			_base_fog_density()
			* lerpf(_num(a, "fog_scale", 1.0), _num(b, "fog_scale", 1.0), t)
			* fog_boost
		)
	var mat := env.sky.sky_material as ShaderMaterial if env.sky else null
	if mat == null:
		return
	mat.set_shader_parameter(
		"zenith_color", _col(a, "sky_zenith").lerp(_col(b, "sky_zenith"), t)
	)
	mat.set_shader_parameter(
		"horizon_color", _col(a, "sky_horizon").lerp(_col(b, "sky_horizon"), t)
	)
	mat.set_shader_parameter("apex_color", _col(a, "sky_apex").lerp(_col(b, "sky_apex"), t))
	mat.set_shader_parameter(
		"ground_color", _col(a, "sky_ground").lerp(_col(b, "sky_ground"), t)
	)
	mat.set_shader_parameter(
		"cloud_color", _col(a, "cloud_color").lerp(_col(b, "cloud_color"), t)
	)
	mat.set_shader_parameter(
		"cloud_shadow_color", _col(a, "cloud_shadow").lerp(_col(b, "cloud_shadow"), t)
	)
	mat.set_shader_parameter("sun_glow", lerpf(_num(a, "sun_glow", 0.5), _num(b, "sun_glow", 0.5), t))
	mat.set_shader_parameter("sun_direction", to_sun)
	mat.set_shader_parameter("moon_direction", to_moon)
	mat.set_shader_parameter("moon_phase", lit_fraction)
	var toward_sun := (to_sun - to_moon * to_moon.dot(to_sun))
	mat.set_shader_parameter(
		"moon_sun_axis", toward_sun.normalized() if toward_sun.length_squared() > 0.0001 else Vector3.UP
	)
	var darkness := night_amount()
	mat.set_shader_parameter("moon_bright", darkness)
	mat.set_shader_parameter("star_amount", darkness)
	mat.set_shader_parameter("celestial_pole", CELESTIAL_POLE)
	mat.set_shader_parameter("star_rotation", -p * TAU)
	mat.set_shader_parameter("sky_day", day())
	mat.set_shader_parameter("meteor_time", LocalSave.get_playtime_seconds())
	mat.set_shader_parameter(
		"sun_size", 0.0 if sun == null or not sun.visible else _base_sun_size()
	)


func _apply_moon(to_moon: Vector3, to_sun: Vector3, lit_fraction: float) -> void:
	var env_owner := _sun.get_ref() as Node3D if _sun else null
	if env_owner == null or not is_instance_valid(env_owner):
		return
	var parent := env_owner.get_parent() as Node3D
	if parent == null:
		return
	var moon := parent.get_node_or_null(MOON_LIGHT_NAME) as DirectionalLight3D
	if moon == null:
		moon = DirectionalLight3D.new()
		moon.name = MOON_LIGHT_NAME
		moon.shadow_enabled = false
		parent.add_child(moon)
	moon.global_transform = Transform3D(Celestial.light_basis(to_moon), moon.global_position)
	moon.light_color = MOON_COLOR
	var altitude := clampf(Celestial.elevation_deg(to_moon) / HORIZON_FADE_DEG + 1.0, 0.0, 1.0)
	var energy := MOON_ENERGY * lit_fraction * altitude * night_amount()
	moon.light_energy = energy
	moon.visible = energy > 0.002
	_moon_elongation_cos = to_sun.dot(to_moon)


func _base_fog_density() -> float:
	var fog: Dictionary = VisualLighting.get_profile(_profile_id).get("fog", {})
	return float(fog.get("density", 0.01))


func _base_sun_size() -> float:
	var sky: Dictionary = VisualLighting.get_profile(_profile_id).get("sky", {})
	return float(sky.get("sun_size", 0.045))


static func _num(stop: Dictionary, key: String, fallback: float) -> float:
	return float(stop.get(key, fallback))


static func _col(stop: Dictionary, key: String) -> Color:
	return Color(str(stop.get(key, "#808080")))
