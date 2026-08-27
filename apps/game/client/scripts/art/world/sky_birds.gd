extends Node3D


const BIRD_COLOR := Color(0.09, 0.08, 0.12)
const BAT_COLOR := Color(0.14, 0.11, 0.16)

const FLOCK_COUNT := 3
const BIRDS_PER_FLOCK := 7
const ALTITUDE := 30.0
const ORBIT_RADIUS := 34.0
const FLOCK_SPREAD := 5.5
const ORBIT_SPEED := 0.048
const FLAP_HZ := 2.6
const FLAP_ANGLE := 0.62
const WIND_SWAY := 0.35

const BANK_ANGLE := 0.34
const SOAR_AMPLITUDE := 4.5

const FLAP_DUTY := 0.55
const FLAP_PERIOD := 3.4

enum Formation { SKEIN, CLUSTER, VEE }

var _flocks: Array[Dictionary] = []
var _elapsed := 0.0

func _ready() -> void:
	if PixelDioramaSettings.particle_quality <= 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 7734
	for f in FLOCK_COUNT:
		var flock := Node3D.new()
		flock.name = "Flock%d" % f
		add_child(flock)
		var formation: Formation = [Formation.SKEIN, Formation.CLUSTER, Formation.VEE][f % 3]
		var birds: Array[Node3D] = []
		var count := BIRDS_PER_FLOCK + rng.randi_range(-2, 3)
		for b in count:
			birds.append(_make_bird(flock, rng, formation, b, count, "%d_%d" % [f, b]))
		_flocks.append({
			"node": flock,
			"birds": birds,
			"phase": TAU * float(f) / float(FLOCK_COUNT),
			"speed": ORBIT_SPEED * rng.randf_range(0.85, 1.15) * (1.0 if f % 2 == 0 else -1.0),
			"radius": ORBIT_RADIUS * rng.randf_range(0.8, 1.35),
			"height": ALTITUDE + rng.randf_range(-6.0, 8.0),
			"soar_rate": rng.randf_range(0.11, 0.23),
			"soar_phase": rng.randf() * TAU,
		})


static func _formation_offset(
	formation: Formation, index: int, count: int, rng: RandomNumberGenerator
) -> Vector3:
	var t := float(index) / maxf(1.0, float(count - 1))
	match formation:
		Formation.SKEIN:
			return Vector3(
				rng.randf_range(-1.2, 1.2),
				rng.randf_range(-0.8, 0.8) + t * 1.4,
				-t * FLOCK_SPREAD * 2.0 + rng.randf_range(-0.6, 0.6)
			)
		Formation.VEE:
			var arm := 1.0 if index % 2 == 0 else -1.0
			@warning_ignore("integer_division")
			var rank := float((index + 1) / 2)
			return Vector3(
				arm * rank * 1.5 + rng.randf_range(-0.35, 0.35),
				rng.randf_range(-0.5, 0.5),
				-rank * 1.7 + rng.randf_range(-0.35, 0.35)
			)
		_:
			return Vector3(
				rng.randf_range(-FLOCK_SPREAD, FLOCK_SPREAD),
				rng.randf_range(-1.8, 1.8),
				rng.randf_range(-FLOCK_SPREAD, FLOCK_SPREAD)
			)


func _make_bird(
	flock: Node3D, rng: RandomNumberGenerator, formation: Formation, index: int, count: int,
	tag: String
) -> Node3D:
	var bird := Node3D.new()
	bird.name = "Bird%s" % tag
	bird.position = _formation_offset(formation, index, count, rng)
	bird.set_meta("beat", rng.randf_range(0.0, TAU))
	bird.set_meta("beat_scale", rng.randf_range(0.85, 1.2))
	bird.set_meta("glide_phase", rng.randf_range(0.0, FLAP_PERIOD))
	flock.add_child(bird)
	var mat := _bird_material()
	PixelDioramaStyle.add_box(bird, Vector3(0.16, 0.12, 0.5), Vector3.ZERO, mat, "Body")
	PixelDioramaStyle.add_box(bird, Vector3(0.1, 0.09, 0.16), Vector3(0.0, 0.02, 0.3), mat, "Head")
	PixelDioramaStyle.add_box(bird, Vector3(0.1, 0.05, 0.22), Vector3(0.0, 0.0, -0.32), mat, "Tail")
	for side in [-1.0, 1.0]:
		var wing := Node3D.new()
		wing.name = "WingR" if side > 0.0 else "WingL"
		bird.add_child(wing)
		PixelDioramaStyle.add_box(
			wing, Vector3(0.38, 0.05, 0.28), Vector3(side * 0.24, 0.0, 0.0), mat, "Inner"
		)
		var outer := Node3D.new()
		outer.name = "Outer"
		outer.position = Vector3(side * 0.43, 0.0, 0.0)
		wing.add_child(outer)
		PixelDioramaStyle.add_box(
			outer, Vector3(0.34, 0.04, 0.2), Vector3(side * 0.17, 0.0, -0.03), mat, "Tip"
		)
	return bird


static func _bird_material() -> Material:
	return PixelDioramaStyle.make_silhouette_material(BIRD_COLOR)


func _process(delta: float) -> void:
	if _flocks.is_empty():
		return
	_elapsed += delta
	var awake := 1.0 - DayNightService.night_amount()
	visible = awake > 0.02
	if not visible:
		return
	modulate_children(awake)
	var wind := WindService.drift() * WIND_SWAY
	for flock in _flocks:
		var speed: float = flock["speed"]
		var angle: float = float(flock["phase"]) + _elapsed * speed
		var node: Node3D = flock["node"]
		var radius: float = flock["radius"]
		var soar := sin(_elapsed * float(flock["soar_rate"]) + float(flock["soar_phase"]))
		node.position = Vector3(
			cos(angle) * radius + wind.x,
			float(flock["height"]) + soar * SOAR_AMPLITUDE,
			sin(angle) * radius + wind.z
		)
		node.rotation = Vector3(
			-soar * float(flock["soar_rate"]) * SOAR_AMPLITUDE * 0.5,
			-angle if speed > 0.0 else -angle + PI,
			BANK_ANGLE * signf(speed)
		)
		for bird in flock["birds"] as Array[Node3D]:
			_pose_bird(bird)


func modulate_children(awake: float) -> void:
	var mat := _bird_material() as StandardMaterial3D
	if mat == null:
		return
	if mat.transparency != BaseMaterial3D.TRANSPARENCY_ALPHA:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var col := mat.albedo_color
	mat.albedo_color = Color(col.r, col.g, col.b, clampf(awake, 0.0, 1.0))


func _pose_bird(bird: Node3D) -> void:
	var cycle := fposmod(_elapsed + float(bird.get_meta("glide_phase")), FLAP_PERIOD) / FLAP_PERIOD
	var beating := clampf((FLAP_DUTY - cycle) / 0.12, 0.0, 1.0)
	var beat: float = (
		_elapsed * TAU * FLAP_HZ * float(bird.get_meta("beat_scale"))
		+ float(bird.get_meta("beat"))
	)
	var swing := sin(beat) * FLAP_ANGLE * beating
	var glide := (1.0 - beating) * 0.12
	for side in [-1.0, 1.0]:
		var wing := bird.get_node_or_null("WingR" if side > 0.0 else "WingL") as Node3D
		if wing == null:
			continue
		wing.rotation.z = (-swing - glide) * side
		var outer := wing.get_node_or_null("Outer") as Node3D
		if outer:
			outer.rotation.z = (-sin(beat - 0.7) * FLAP_ANGLE * 0.7 * beating) * side
