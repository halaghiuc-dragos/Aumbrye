extends Node


const DAY_FRACTION := 0.10

const STAGGER_SPREAD := 0.55
# How much of the dusk window one lamp takes to come up. Wide, because a lamp that snaps on is a
# switch and a lamp that fades over half a minute is someone walking round with a taper.
const LIGHT_UP_WINDOW := 0.3

const GROUP := &"world_light"

# The dusk ramp, in degrees of solar elevation. It used to open at 22 degrees — an hour of daylight
# still to go — so the lamps were already up while the sun was well clear of the rooftops. Opening
# it just above the horizon means the first lamps light at sunset and the last are up once the sky
# has gone.
const DUSK_START_DEG := 6.0
const DUSK_END_DEG := -8.0

const META_BASE_ENERGY := &"night_light_base_energy"
const META_THRESHOLD := &"night_light_threshold"

var _lights: Array[Light3D] = []
var _last_applied := -1.0
var _bound_root: Node
var _next_index := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func bind(root: Node) -> void:
	clear()
	_bound_root = root
	if root == null:
		return
	var tree := get_tree()
	if tree and not tree.node_added.is_connected(_on_node_added):
		tree.node_added.connect(_on_node_added)
	for node in root.find_children("*", "Light3D", true, false):
		_adopt(node as Light3D)
	_apply(dusk_amount())


func clear() -> void:
	_lights.clear()
	_bound_root = null
	_next_index = 0
	_last_applied = -1.0
	var tree := get_tree()
	if tree and tree.node_added.is_connected(_on_node_added):
		tree.node_added.disconnect(_on_node_added)


func _on_node_added(node: Node) -> void:
	var light := node as Light3D
	if light != null:
		_adopt(light)


func _adopt(light: Light3D) -> void:
	if light == null or not light.is_in_group(GROUP) or light in _lights:
		return
	if _bound_root == null or not _bound_root.is_ancestor_of(light):
		return
	if not light.has_meta(META_BASE_ENERGY):
		light.set_meta(META_BASE_ENERGY, light.light_energy)
	light.set_meta(META_THRESHOLD, fposmod(float(_next_index) * 0.6180339887, 1.0) * STAGGER_SPREAD)
	_next_index += 1
	_lights.append(light)
	_last_applied = -1.0


func dusk_amount() -> float:
	var elevation := Celestial.elevation_deg(
		Celestial.sun_direction(DayNightService.phase(), DayNightService.day())
	)
	return clampf(inverse_lerp(DUSK_START_DEG, DUSK_END_DEG, elevation), 0.0, 1.0)


func scale_for(light: Light3D) -> float:
	if light == null or not light.has_meta(META_THRESHOLD):
		return 1.0
	return _lit_fraction(dusk_amount(), float(light.get_meta(META_THRESHOLD)))


func _lit_fraction(dusk: float, threshold: float) -> float:
	var lit := clampf((dusk - threshold) / LIGHT_UP_WINDOW, 0.0, 1.0)
	lit = lit * lit * (3.0 - 2.0 * lit)
	return lerpf(DAY_FRACTION, 1.0, lit)


func _process(_delta: float) -> void:
	if _lights.is_empty():
		return
	_apply(dusk_amount())


func _apply(dusk: float) -> void:
	if absf(dusk - _last_applied) < 0.001:
		return
	_last_applied = dusk
	var stale := false
	for light in _lights:
		if not is_instance_valid(light):
			stale = true
			continue
		var base: float = light.get_meta(META_BASE_ENERGY, light.light_energy)
		light.light_energy = base * _lit_fraction(dusk, float(light.get_meta(META_THRESHOLD, 0.0)))
	if stale:
		# Rebuilt by hand rather than with filter(): a freed entry arrives at the
		# predicate as a plain Object, which will not bind to a Light3D parameter,
		# and filter()'s untyped Array will not assign back to a typed one either.
		var live: Array[Light3D] = []
		for light in _lights:
			if is_instance_valid(light):
				live.append(light)
		_lights = live
