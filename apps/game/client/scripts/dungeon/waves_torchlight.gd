extends Node3D


const PixelStyle := preload("res://scripts/art/style/pixel_diorama_style.gd")
const PixelBoxBatchScript := preload("res://scripts/art/style/pixel_box_batch.gd")

const PYRE_RADIUS := 41.0
const PYRE_COUNT := 10
const FAR_PYRE_RADIUS := 74.0
const FAR_PYRE_COUNT := 8

const FADE_IN_SECONDS := 1.8
const FADE_OUT_SECONDS := 2.6
const FLAME_UPDATE_INTERVAL := 1.0 / 30.0

const DARK_LIGHT_FRACTION := 0.26
const DARK_AMBIENT_FRACTION := 0.3
const DARK_FOG_MULTIPLIER := 3.4

var _pyre_lights: Array[OmniLight3D] = []
var _pyre_flames: Array[Node3D] = []
var _pyre_scales: Array[float] = []
var _far_ring_start := 0
var _far_ring_lit := true
var _fog_override := 1.0
var _blend := 0.0
var _target := 0.0
var _phase := 0.0
var _flame_update_accumulator := 0.0
var _flame_tick := 0


func setup(_root: Node3D) -> void:
	name = "WavesTorchlight"
	_build_pyres()
	_apply_blend()


func set_lit(lit: bool, immediate: bool = false) -> void:
	_target = 1.0 if lit else 0.0
	if immediate:
		_blend = _target
		_apply_blend()


## MD-01: a continuous driver for the fade, alongside the boolean `set_lit()` -- lets the cresset's
## fuel level (drained by distance, replenished by standing near it) drive the same blend rather
## than snapping the light on or off.
func set_fuel_level(level: float) -> void:
	_target = clampf(level, 0.0, 1.0)


func _build_pyres() -> void:
	var iron := PixelStyle.make_metal_material(Color(0.21, 0.20, 0.24), 0.36)
	var stone := PixelStyle.make_material(Color(0.34, 0.33, 0.36))
	var flame_core := PixelStyle.make_custom_emissive(Color(1.0, 0.66, 0.24), 2.2)
	var geometry_batch := PixelBoxBatchScript.new() as PixelBoxBatch
	_add_pyre_ring(PYRE_RADIUS, PYRE_COUNT, 1.0, iron, stone, flame_core, geometry_batch, "Pyre")
	_far_ring_start = _pyre_lights.size()
	_add_pyre_ring(
		FAR_PYRE_RADIUS, FAR_PYRE_COUNT, 1.6, iron, stone, flame_core, geometry_batch, "FarPyre"
	)
	geometry_batch.commit(
		self,
		"PyreGeometry",
		AABB(Vector3(-125.0, -1.0, -125.0), Vector3(250.0, 10.0, 250.0))
	)


func _add_pyre_ring(
	radius: float,
	count: int,
	pyre_scale: float,
	iron: Material,
	stone: Material,
	flame_core: Material,
	geometry_batch: PixelBoxBatch,
	prefix: String
) -> void:
	for i in count:
		var angle := TAU * (float(i) + (0.5 if prefix == "FarPyre" else 0.0)) / float(count)
		var root_position := Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		geometry_batch.add(
			Vector3(1.4, 0.3, 1.4) * pyre_scale,
			root_position + Vector3(0.0, 0.15, 0.0) * pyre_scale,
			stone
		)
		geometry_batch.add(
			Vector3(0.4, 2.0, 0.4) * pyre_scale,
			root_position + Vector3(0.0, 1.2, 0.0) * pyre_scale,
			iron
		)
		geometry_batch.add(
			Vector3(1.1, 0.4, 1.1) * pyre_scale,
			root_position + Vector3(0.0, 2.3, 0.0) * pyre_scale,
			iron
		)
		var flame := Node3D.new()
		flame.name = "%sFlame%d" % [prefix, i]
		flame.position = root_position + Vector3(0.0, 2.6, 0.0) * pyre_scale
		flame.scale = Vector3.ONE * pyre_scale
		flame.visible = false
		add_child(flame)
		PixelStyle.add_box(flame, Vector3(0.7, 0.55, 0.7), Vector3(0.0, 0.25, 0.0), flame_core, "Core")
		PixelStyle.add_box(flame, Vector3(0.4, 0.4, 0.4), Vector3(0.0, 0.7, 0.0), flame_core, "Tip")
		var light: OmniLight3D = null
		# Distant pyres keep their emissive silhouette and embers but do not spend a dynamic light.
		if prefix != "FarPyre":
			light = OmniLight3D.new()
			light.name = "PyreLight"
			light.light_color = Color(1.0, 0.62, 0.28)
			light.light_energy = 0.0
			light.omni_range = 34.0 * pyre_scale
			light.shadow_enabled = false
			light.position = Vector3(0.0, 0.6, 0.0)
			flame.add_child(light)
		LightEmbers.attach(flame, Vector3(0.0, 0.4, 0.0), Color(1.0, 0.62, 0.28), 2.5, 1.5)
		_pyre_lights.append(light)
		_pyre_flames.append(flame)
		_pyre_scales.append(pyre_scale)


func _process(delta: float) -> void:
	if is_equal_approx(_blend, _target):
		_animate_flames(delta)
		return
	var duration := FADE_IN_SECONDS if _target > _blend else FADE_OUT_SECONDS
	_blend = move_toward(_blend, _target, delta / maxf(duration, 0.05))
	_apply_blend()
	_animate_flames(delta)


## MD-01: kills the far ring only, leaving the near ring lit -- called by `WavesArenaMutator` for
## the "dimmed" arena state.
func set_far_ring_lit(lit: bool) -> void:
	_far_ring_lit = lit
	_apply_blend()


## MD-01: `_apply_blend()` already writes `DayNightService.fog_boost` every frame the cresset's
## fuel is changing (near-constant during combat) -- a second writer racing it would just get
## stomped, so the "fog" arena state feeds a multiplier in here instead of writing the global
## directly.
func set_fog_override(multiplier: float) -> void:
	_fog_override = maxf(0.01, multiplier)
	_apply_blend()


func _apply_blend() -> void:
	var eased := _blend * _blend * (3.0 - 2.0 * _blend)
	for i in _pyre_lights.size():
		var light := _pyre_lights[i]
		var ring_eased := eased if (i < _far_ring_start or _far_ring_lit) else 0.0
		if is_instance_valid(light):
			light.light_energy = 2.1 * ring_eased
		var flame := _pyre_flames[i]
		if is_instance_valid(flame):
			flame.visible = ring_eased > 0.02
			flame.scale = Vector3.ONE * maxf(ring_eased, 0.001) * _pyre_scales[i]
	DayNightService.dim = lerpf(DARK_LIGHT_FRACTION, 1.0, eased)
	DayNightService.fog_boost = lerpf(DARK_FOG_MULTIPLIER, 1.0, eased) * _fog_override


func _animate_flames(delta: float) -> void:
	if _blend <= 0.02:
		return
	_flame_update_accumulator += delta
	if _flame_update_accumulator < FLAME_UPDATE_INTERVAL:
		return
	var step := _flame_update_accumulator
	_flame_update_accumulator = fmod(_flame_update_accumulator, FLAME_UPDATE_INTERVAL)
	_phase += step
	_flame_tick += 1
	for i in _pyre_flames.size():
		if i >= _far_ring_start and _flame_tick % 2 != 0:
			continue
		var flame := _pyre_flames[i]
		if not is_instance_valid(flame) or not flame.visible:
			continue
		var f := 0.92 + sin(_phase * 7.0 + float(i) * 1.7) * 0.08
		flame.scale = Vector3(f, 1.0 + (f - 0.92) * 1.8, f) * _blend * _pyre_scales[i]
