class_name VillageCrowd
extends Node3D

## The people of the background village: villagers and peasants on foot, soldiers on
## patrol, and horsemen on the roads.
##
## Everyone here is drawn out of a MultiMesh rather than a node tree. The old
## background crowd gave every walker its own Node3D with a MeshInstance3D per limb,
## which is fine for eighteen of them and ruinous for eighty -- the scene tree walk and
## the per-node culling cost more than the pixels do. Instead each figure is a fixed
## list of boxes, every box is one instance in a shared MultiMesh, and a tick rewrites
## the transforms. That is a handful of draw calls for the whole population, no matter
## how many people are in it, and no per-figure nodes for the engine to visit.
##
## They also walk the planned streets rather than orbiting on circles, so the traffic
## is on the roads the town was actually laid out around.

## Limb codes. Anything but STATIC swings about its top edge as the figure walks.
const STATIC := 0
const LEG_A := 1
const LEG_B := 2
const ARM_A := 3
const ARM_B := 4

## The crowd updates at a fixed rate rather than per frame, which caps the cost of the
## whole system. Twelve was too coarse: it is below the rate at which the eye stops
## seeing separate positions, so a walk read as a series of poses and a trotting horse
## flickered. Thirty is smooth and still well under a render frame's worth of work.
const TICK_HZ := 30.0

## How long a figure takes to come to a stop or get going again, in seconds. Gait and
## travel are driven by one eased factor, so a figure slows down, its legs wind down in
## step with it, and it stops -- instead of the whole body snapping between walking and
## standing on a single frame.
const PACE_EASE := 0.45

## How quickly a figure turns to face its new bearing, in radians per second of easing.
## Corners on the polylines and the turn at the end of a dead-end street both used to be
## instantaneous, which at a hundred metres reads as a figure blinking round.
const TURN_RATE := 5.0

## Lanes. Every figure is given a fixed lateral offset from the street's centreline and
## keeps it for good, and each direction of travel takes its own side. That is the whole
## anti-collision scheme: nobody is ever pushed, slowed or steered by anybody else, so
## each figure walks at its own constant pace and its motion depends on nothing but its
## own clock. A solver that shunted people apart would have been the opposite -- one
## person stopping to talk would ripple down the whole street.
##
## Every lane is laid out to fit *on the carriageway*. The lanes used to be measured
## outward from the kerb, which bought room for the wagons at the price of walking half
## the village along the grass verge beside the road rather than on it. They are
## measured inward from the kerb instead, and how many will fit is worked out per street
## from what has to share it -- so a wagon takes the crown, riders sit just outside it,
## and foot traffic gets whatever lanes are left between them and the kerb.
const CART_HALF := 0.90
const HORSE_HALF := 0.31
const FOOT_HALF := 0.25
## Clear air left between two things sharing a carriageway.
const LANE_GAP := 0.05

## Narrowest carriageway a wagon is put on; the caller uses this to pick cart routes.
## Below it a street carries riders and people only, and the riders take the crown.
const CART_ROAD_WIDTH := 4.0

## Lateral pitch between two foot lanes, and the most any street will be given.
const LANE_STEP := 0.55
const MAX_FOOT_LANES := 3

## Lane bands, passed to `add_agent`. Which band a figure is in decides how far off the
## centreline it walks; within the foot band there are several lanes and figures are
## dealt into them in turn.
const BAND_FOOT := 0
const BAND_HORSE := 1
const BAND_CART := 2

var _agents: Array[Dictionary] = []
## Agents grouped by the lane they occupy, keyed "route:band:lane". Only used once, at
## commit, to space out the few figures that end up sharing a lane.
var _by_lane: Dictionary = {}
## Running count of figures dealt into each route-and-band, keyed "route:band".
var _lane_seq: Dictionary = {}
var _slots: Dictionary = {}
var _meshes: Dictionary = {}
var _routes: Array[Dictionary] = []
var _accum := 0.0
## The delta the current tick is being stepped with. Read by `_draw` for the turn
## easing, which is the one thing there that is rate-dependent.
var _tick_delta := 0.0
var _ground := 0.0


func configure(ground_y: float) -> void:
	_ground = ground_y


## Routes come straight from the town plan, so the crowd is walking the same polylines
## the buildings were seated against. `widths` is the matching carriageway width per
## polyline; it decides how far off the centreline each direction of travel keeps, so
## two people passing in opposite directions go either side of each other instead of
## through each other.
func set_routes(
	polylines: Array[PackedVector2Array], widths: PackedFloat32Array = PackedFloat32Array()
) -> void:
	_routes.clear()
	for index in polylines.size():
		var points: PackedVector2Array = polylines[index]
		if points.size() < 2:
			continue
		var lengths := PackedFloat32Array()
		lengths.append(0.0)
		var total := 0.0
		for i in points.size() - 1:
			total += points[i].distance_to(points[i + 1])
			lengths.append(total)
		if total < 24.0:
			continue
		# A ring closes on itself, so walkers wrap; a spoke is a dead end, so they turn round.
		var loops := points[0].distance_to(points[points.size() - 1]) < 6.0
		var mean_radius := 0.0
		for p in points:
			mean_radius += p.length()
		mean_radius /= float(points.size())
		var width: float = widths[index] if index < widths.size() else 3.2
		var half := width * 0.5
		# The crown is spoken for only where wagons run; elsewhere the riders have it.
		var crown := CART_HALF if width >= CART_ROAD_WIDTH else 0.0
		var horse_lane := crown + HORSE_HALF + LANE_GAP
		# Outermost foot lane, set so a walker's shoulder lands on the kerb and not past it.
		var foot_outer := half - FOOT_HALF
		var foot_floor := horse_lane + HORSE_HALF + FOOT_HALF + LANE_GAP
		var foot_lanes := 1
		if foot_outer > foot_floor:
			foot_lanes = clampi(
				int(floor((foot_outer - foot_floor) / LANE_STEP)) + 1, 1, MAX_FOOT_LANES
			)
		_routes.append({
			"width": width,
			"points": points,
			"lengths": lengths,
			"total": total,
			"loops": loops,
			"radius": mean_radius,
			"half": half,
			"horse_lane": horse_lane,
			"foot_outer": maxf(foot_outer, 0.0),
			"foot_lanes": foot_lanes,
		})


func route_count() -> int:
	return _routes.size()


## Carriageway width of a route. The caller needs it to decide what will fit: a wagon
## on a three-metre lane straddles both verges however it is placed.
func route_width(index: int) -> float:
	if index < 0 or index >= _routes.size():
		return 0.0
	return float(_routes[index]["width"])


## Mean distance of a route from the town centre. Used to weight where the crowd goes:
## a figure on the outermost lane is 250m away and costs exactly as much as one on the
## high street, where it can actually be seen.
func route_mean_radius(index: int) -> float:
	if index < 0 or index >= _routes.size():
		return 0.0
	return _routes[index]["radius"]


## Register one figure. `parts` is the box list; the crowd keeps no node for it.
## `footprint` is how much room the figure takes along its line of travel, which is
## what a lane's occupants are checked against once they are all in. `band` picks which
## part of the carriageway it uses.
func add_agent(
	parts: Array[Dictionary],
	route_index: int,
	at_fraction: float,
	speed: float,
	stride: float,
	swing: float,
	footprint: float = 1.2,
	band: int = BAND_FOOT
) -> void:
	if _routes.is_empty():
		return
	var route_slot := route_index % _routes.size()
	var route: Dictionary = _routes[route_slot]
	var slots: Array[Dictionary] = []
	for part in parts:
		var mat_key: String = part["mat"]
		if not _slots.has(mat_key):
			_slots[mat_key] = []
		var bucket: Array = _slots[mat_key]
		slots.append({
			"mat": mat_key,
			"index": bucket.size(),
			"size": part["size"],
			"at": part["at"],
			"limb": int(part.get("limb", STATIC)),
		})
		bucket.append(part)
		_slots[mat_key] = bucket

	# Deal the figure into a lane, and on a ring into a direction as well. The two
	# directions are two more lanes for free -- they sit either side of the centreline
	# -- and they give the street counter-flow rather than one circulating procession.
	# A dead-end street's traffic turns round at the ends, so its direction is not fixed
	# and cannot be used to hold anybody apart; there, everyone starts the same way.
	var key := "%d:%d" % [route_slot, band]
	var dealt := int(_lane_seq.get(key, 0))
	_lane_seq[key] = dealt + 1
	var lanes: int = int(route["foot_lanes"]) if band == BAND_FOOT else 1
	var streams := 2 if bool(route["loops"]) else 1
	var slot := dealt % (lanes * streams)
	var lane := slot % lanes
	var heading := -1.0 if slot >= lanes else 1.0

	_agents.append({
		"slots": slots,
		"route": route_slot,
		"s": fposmod(at_fraction, 1.0) * float(route["total"]),
		"speed": speed,
		"dir": heading,
		"stride": stride,
		"swing": swing,
		"travelled": 0.0,
		"pause": 0.0,
		"pause_in": randf_range(6.0, 30.0),
		"pauses": true,
		"pace": 1.0,
		# Filled in on the first draw, when there is a bearing to face.
		"yaw": NAN,
		"leg": _leg_length(parts),
		"half": maxf(footprint, 0.3) * 0.5,
		"offset": _lane_offset(route, band, lane),
	})
	var lane_key := "%s:%d:%d" % [key, lane, int(heading)]
	if not _by_lane.has(lane_key):
		_by_lane[lane_key] = PackedInt32Array()
	var members: PackedInt32Array = _by_lane[lane_key]
	members.append(_agents.size() - 1)
	_by_lane[lane_key] = members


## How long the figure's legs are, measured off the parts list. This is what the body
## has to be dropped by as the stride opens if the feet are to stay on the road; a
## horse's legs and a villager's are found the same way.
static func _leg_length(parts: Array[Dictionary]) -> float:
	var longest := 0.0
	for part in parts:
		var limb := int(part.get("limb", STATIC))
		if limb == LEG_A or limb == LEG_B:
			longest = maxf(longest, (part["size"] as Vector3).y)
	return longest


## How far off the centreline a lane runs. Read straight off the route, which worked
## the layout out from its own width, so every lane lands on the metalling whether the
## street is a three-metre back lane or the high street.
static func _lane_offset(route: Dictionary, band: int, lane: int) -> float:
	if band == BAND_CART:
		# A wagon takes the crown of the road; there is only ever one per street.
		return 0.0
	if band == BAND_HORSE:
		return float(route["horse_lane"])
	return maxf(float(route["foot_outer"]) - float(lane) * LANE_STEP, 0.0)


## Space out the figures that ended up sharing a lane, and give them a common pace.
##
## Two people in one lane walking at different speeds must eventually meet, and the
## only ways out of that are to couple them -- which is what makes a crowd look
## shunted -- or to make the meeting impossible. This does the latter: a shared lane
## gets one speed and its occupants are spread evenly along the street, so the gaps
## between them never change and no figure ever has to react to another. They also give
## up the odd stop to talk, since a pause is exactly what would close a gap; the ones
## walking a lane on their own keep it.
func _resolve_lanes() -> void:
	for lane_key in _by_lane:
		var members: PackedInt32Array = _by_lane[lane_key]
		if members.size() < 2:
			continue
		var lead: Dictionary = _agents[members[0]]
		var route: Dictionary = _routes[lead["route"]]
		var total: float = float(route["total"])

		# Every gap is at least the two figures' own footprints; whatever length is left
		# over is shared out at random. Spacing them evenly would hold them apart just as
		# well, but a dozen people at identical intervals round a ring reads as a
		# procession, and the point of the lane scheme is that the crowd looks unarranged.
		var taken := 0.0
		for index in members:
			taken += float(_agents[index]["half"]) * 2.0
		if taken > total:
			push_warning("VillageCrowd: more traffic in lane %s than the street holds" % lane_key)
		var slack := maxf(total - taken, 0.0)
		var weights := PackedFloat32Array()
		var weight_sum := 0.0
		for i in members.size():
			var weight := randf() + 0.35
			weights.append(weight)
			weight_sum += weight

		var at := float(lead["s"])
		for i in members.size():
			var agent: Dictionary = _agents[members[i]]
			agent["speed"] = lead["speed"]
			agent["pauses"] = false
			agent["s"] = fposmod(at, total)
			at += float(agent["half"]) * 2.0
			if weight_sum > 0.0:
				at += slack * float(weights[i]) / weight_sum
	_by_lane.clear()


## Build one MultiMesh per material once every figure is registered.
func commit(materials: Dictionary, bounds: AABB) -> void:
	for mat_key in _slots:
		var bucket: Array = _slots[mat_key]
		if bucket.is_empty():
			continue
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = PixelBoxBatch.unit_cube()
		multimesh.instance_count = bucket.size()
		var node := MultiMeshInstance3D.new()
		node.name = "Crowd_%s" % mat_key
		node.multimesh = multimesh
		node.material_override = materials.get(mat_key) as Material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.custom_aabb = bounds
		add_child(node)
		_meshes[mat_key] = multimesh
	_slots.clear()
	_resolve_lanes()
	_step(0.0)


func _process(delta: float) -> void:
	if not is_visible_in_tree() or _meshes.is_empty():
		return
	_accum += delta
	var period := 1.0 / TICK_HZ
	if _accum < period:
		return
	_step(_accum)
	_accum = 0.0


## One tick: everybody advances, then the boxes are written. The two are separate
## passes only because it keeps the arithmetic and the transform writes apart; no
## figure reads any other figure's position at any point.
func _step(delta: float) -> void:
	_tick_delta = delta
	for agent in _agents:
		_advance(agent, delta)
	for agent in _agents:
		_draw(agent)


func _advance(agent: Dictionary, delta: float) -> void:
	var route: Dictionary = _routes[agent["route"]]
	var total: float = route["total"]

	# The odd stop to talk, haggle or look at something -- but only for the figures
	# that have a lane to themselves, since a pause is what would close the gap on
	# anybody sharing one.
	if bool(agent["pauses"]):
		var pause: float = agent["pause"]
		if pause > 0.0:
			agent["pause"] = maxf(0.0, pause - delta)
		else:
			agent["pause_in"] = float(agent["pause_in"]) - delta
			if float(agent["pause_in"]) <= 0.0:
				agent["pause"] = randf_range(1.5, 6.0)
				agent["pause_in"] = randf_range(12.0, 40.0)

	# One factor drives both how fast the figure travels and how far its legs swing, so
	# the stride always matches the ground covered and a foot can never scuff along.
	var wanted := 0.0 if float(agent["pause"]) > 0.0 else 1.0
	var pace := move_toward(float(agent["pace"]), wanted, delta / PACE_EASE)
	agent["pace"] = pace

	var step: float = float(agent["speed"]) * float(agent["dir"]) * pace * delta
	var s: float = float(agent["s"]) + step
	if bool(route["loops"]):
		s = fposmod(s, total)
	elif s < 0.0 or s > total:
		# Dead end: turn round and walk back.
		agent["dir"] = -float(agent["dir"])
		s = clampf(s, 0.0, total)
	agent["s"] = s
	agent["travelled"] = float(agent["travelled"]) + absf(step)


func _draw(agent: Dictionary) -> void:
	var route: Dictionary = _routes[agent["route"]]
	var pace: float = float(agent["pace"])

	var sample := _sample(route, float(agent["s"]))
	var pos: Vector2 = sample["p"]
	var dir: Vector2 = sample["d"] * float(agent["dir"])
	# Keep to one side of the road, by direction of travel, so the two streams of
	# traffic have their own half of the carriageway.
	var offside := Vector2(-dir.y, dir.x) * float(agent["offset"])
	var origin := Vector3(pos.x + offside.x, _ground, pos.y + offside.y)

	# The figures are modelled +Z forward, so the yaw that points +Z down the street is
	# atan2(x, z) -- not atan2(-z, x), which turned every one of them broadside on and
	# left the horses walking sideways with their riders facing across the road.
	#
	# The bearing is eased into rather than assigned. A polyline corner and the turn at
	# the end of a dead-end street are both step changes in direction, and a body that
	# snaps a hundred and eighty degrees between two ticks does not read as a person
	# turning round.
	var wanted_yaw := atan2(dir.x, dir.y)
	var yaw: float = float(agent["yaw"])
	if is_nan(yaw):
		yaw = wanted_yaw
	else:
		yaw = lerp_angle(yaw, wanted_yaw, clampf(_tick_delta * TURN_RATE, 0.0, 1.0))
	agent["yaw"] = yaw
	var facing := Basis(Vector3.UP, yaw)

	# The gait. `travelled` is distance covered, so the stride is tied to the ground and
	# a figure's feet cannot slide however its pace changes.
	var phase: float = float(agent["travelled"]) * float(agent["stride"])
	var swing: float = float(agent["swing"]) * pace
	var lean := sin(phase) * swing

	# Ride at the height the legs actually put the body at. Both legs are swung to the
	# same magnitude, so both feet lift by the same amount off a straight stance, and
	# subtracting it plants them on the road. That is also where the walk's bob comes
	# from -- the body dips as the stride opens and rises as it closes, twice a cycle,
	# smoothly, instead of the sawtooth an abs() of a sine used to give it.
	origin.y -= float(agent["leg"]) * (1.0 - cos(lean))

	var slots: Array = agent["slots"]
	for slot in slots:
		var limb: int = slot["limb"]
		var at: Vector3 = slot["at"]
		var size: Vector3 = slot["size"]
		var part_basis := facing
		var local := at
		if limb != STATIC:
			var angle := sin(phase + (PI if limb == LEG_B or limb == ARM_B else 0.0)) * swing
			if limb == ARM_A or limb == ARM_B:
				angle = -angle * 0.72
			# Swing about the top of the limb, not its middle, or the foot detaches.
			var pivot := Vector3(at.x, at.y + size.y * 0.5, at.z)
			var turn := Basis(Vector3.RIGHT, angle)
			local = pivot + turn * (at - pivot)
			part_basis = facing * turn
		var multimesh: MultiMesh = _meshes.get(slot["mat"])
		if multimesh == null:
			continue
		multimesh.set_instance_transform(
			slot["index"],
			Transform3D(part_basis.scaled_local(size), origin + facing * local)
		)


static func _sample(route: Dictionary, distance: float) -> Dictionary:
	var points: PackedVector2Array = route["points"]
	var lengths: PackedFloat32Array = route["lengths"]
	var last := points.size() - 1
	var clamped := clampf(distance, 0.0, lengths[last])
	var lo := 0
	var hi := last
	# Binary search: the crowd samples every tick and these polylines run to a hundred
	# vertices, so a linear scan here is the one place this system could get expensive.
	while lo < hi - 1:
		@warning_ignore("integer_division")
		var mid := (lo + hi) / 2
		if lengths[mid] <= clamped:
			lo = mid
		else:
			hi = mid
	var span: float = lengths[lo + 1] - lengths[lo]
	var t := 0.0 if span <= 0.0001 else (clamped - lengths[lo]) / span
	var a := points[lo]
	var b := points[lo + 1]
	var dir := b - a
	if dir.length() <= 0.0001:
		dir = Vector2.RIGHT
	return {"p": a.lerp(b, t), "d": dir.normalized()}


# --- figures ---------------------------------------------------------------------
#
# Each of these returns a box list in the figure's own space: +Y up, +Z forward.


static func villager_parts(cloth: String, skin: String) -> Array[Dictionary]:
	return [
		{"size": Vector3(0.46, 0.62, 0.30), "at": Vector3(0.0, 1.24, 0.0), "mat": cloth},
		{"size": Vector3(0.50, 0.34, 0.34), "at": Vector3(0.0, 1.02, 0.0), "mat": cloth},
		{"size": Vector3(0.26, 0.26, 0.26), "at": Vector3(0.0, 1.68, 0.0), "mat": skin},
		{"size": Vector3(0.14, 0.52, 0.16), "at": Vector3(-0.30, 1.24, 0.0), "mat": cloth, "limb": ARM_A},
		{"size": Vector3(0.14, 0.52, 0.16), "at": Vector3(0.30, 1.24, 0.0), "mat": cloth, "limb": ARM_B},
		{"size": Vector3(0.16, 0.92, 0.18), "at": Vector3(-0.13, 0.46, 0.0), "mat": cloth, "limb": LEG_A},
		{"size": Vector3(0.16, 0.92, 0.18), "at": Vector3(0.13, 0.46, 0.0), "mat": cloth, "limb": LEG_B},
	]


## A peasant: same frame, but stooped, in drab cloth, and carrying a bundle.
static func peasant_parts(cloth: String, skin: String, load_mat: String) -> Array[Dictionary]:
	var parts := villager_parts(cloth, skin)
	parts.append({
		"size": Vector3(0.52, 0.36, 0.40), "at": Vector3(0.0, 1.62, -0.34), "mat": load_mat
	})
	return parts


## A soldier: mailed, helmed, with a spear held upright at the shoulder.
static func soldier_parts(cloth: String, skin: String, iron: String) -> Array[Dictionary]:
	return [
		{"size": Vector3(0.50, 0.64, 0.32), "at": Vector3(0.0, 1.26, 0.0), "mat": iron},
		{"size": Vector3(0.54, 0.30, 0.36), "at": Vector3(0.0, 1.44, 0.0), "mat": iron},
		{"size": Vector3(0.26, 0.26, 0.26), "at": Vector3(0.0, 1.70, 0.0), "mat": skin},
		{"size": Vector3(0.32, 0.18, 0.32), "at": Vector3(0.0, 1.84, 0.0), "mat": iron},
		{"size": Vector3(0.14, 0.52, 0.16), "at": Vector3(-0.31, 1.24, 0.0), "mat": iron, "limb": ARM_A},
		{"size": Vector3(0.14, 0.52, 0.16), "at": Vector3(0.31, 1.24, 0.0), "mat": iron, "limb": ARM_B},
		{"size": Vector3(0.17, 0.92, 0.19), "at": Vector3(-0.14, 0.46, 0.0), "mat": cloth, "limb": LEG_A},
		{"size": Vector3(0.17, 0.92, 0.19), "at": Vector3(0.14, 0.46, 0.0), "mat": cloth, "limb": LEG_B},
		# Spear, carried vertically so the patrol reads as armed at a distance.
		{"size": Vector3(0.07, 2.5, 0.07), "at": Vector3(0.36, 1.55, 0.1), "mat": "timber"},
		{"size": Vector3(0.11, 0.34, 0.11), "at": Vector3(0.36, 2.92, 0.1), "mat": iron},
	]


## A horseman: horse and rider as one figure, so they can never drift apart.
static func horseman_parts(cloth: String, skin: String, coat: String) -> Array[Dictionary]:
	return [
		# Horse.
		{"size": Vector3(0.62, 0.78, 1.90), "at": Vector3(0.0, 1.32, 0.0), "mat": coat},
		{"size": Vector3(0.42, 0.72, 0.46), "at": Vector3(0.0, 1.78, 1.02), "mat": coat},
		{"size": Vector3(0.30, 0.34, 0.34), "at": Vector3(0.0, 2.10, 1.24), "mat": coat},
		{"size": Vector3(0.14, 0.62, 0.14), "at": Vector3(0.0, 1.42, -1.02), "mat": coat},
		{"size": Vector3(0.19, 0.94, 0.19), "at": Vector3(-0.24, 0.47, 0.62), "mat": coat, "limb": LEG_A},
		{"size": Vector3(0.19, 0.94, 0.19), "at": Vector3(0.24, 0.47, 0.62), "mat": coat, "limb": LEG_B},
		{"size": Vector3(0.19, 0.94, 0.19), "at": Vector3(-0.24, 0.47, -0.62), "mat": coat, "limb": LEG_B},
		{"size": Vector3(0.19, 0.94, 0.19), "at": Vector3(0.24, 0.47, -0.62), "mat": coat, "limb": LEG_A},
		# Rider, seated.
		{"size": Vector3(0.44, 0.60, 0.30), "at": Vector3(0.0, 2.16, -0.06), "mat": cloth},
		{"size": Vector3(0.26, 0.26, 0.26), "at": Vector3(0.0, 2.58, -0.06), "mat": skin},
		# Arms carried forward and down, as they are on the reins rather than hanging.
		{"size": Vector3(0.13, 0.44, 0.15), "at": Vector3(-0.28, 2.10, 0.22), "mat": cloth},
		{"size": Vector3(0.13, 0.44, 0.15), "at": Vector3(0.28, 2.10, 0.22), "mat": cloth},
		# Thighs sit outside the barrel, not in it: at 0.34 they were a hand's width
		# inside the horse, which shows as a leg that ends before the hip does.
		{"size": Vector3(0.15, 0.50, 0.17), "at": Vector3(-0.40, 1.68, 0.12), "mat": cloth},
		{"size": Vector3(0.15, 0.50, 0.17), "at": Vector3(0.40, 1.68, 0.12), "mat": cloth},
	]


## A horse and cart: draught horse in the shafts, a boxed wagon behind it on four
## wheels, and a carter up on the board. Built as one figure for the same reason the
## horseman is -- a cart that can drift off its own horse is worse than no cart at all.
static func cart_parts(
	cloth: String, skin: String, coat: String, timber: String, load_mat: String
) -> Array[Dictionary]:
	return [
		# Draught horse, out in front of the shafts.
		{"size": Vector3(0.68, 0.84, 1.96), "at": Vector3(0.0, 1.34, 1.80), "mat": coat},
		{"size": Vector3(0.44, 0.74, 0.48), "at": Vector3(0.0, 1.82, 2.84), "mat": coat},
		{"size": Vector3(0.32, 0.36, 0.36), "at": Vector3(0.0, 2.14, 3.06), "mat": coat},
		{"size": Vector3(0.14, 0.62, 0.14), "at": Vector3(0.0, 1.44, 0.80), "mat": coat},
		{"size": Vector3(0.20, 0.96, 0.20), "at": Vector3(-0.26, 0.48, 2.42), "mat": coat, "limb": LEG_A},
		{"size": Vector3(0.20, 0.96, 0.20), "at": Vector3(0.26, 0.48, 2.42), "mat": coat, "limb": LEG_B},
		{"size": Vector3(0.20, 0.96, 0.20), "at": Vector3(-0.26, 0.48, 1.18), "mat": coat, "limb": LEG_B},
		{"size": Vector3(0.20, 0.96, 0.20), "at": Vector3(0.26, 0.48, 1.18), "mat": coat, "limb": LEG_A},
		# Shafts running back from the collar to the wagon.
		{"size": Vector3(0.10, 0.10, 1.70), "at": Vector3(-0.42, 1.05, 0.86), "mat": timber},
		{"size": Vector3(0.10, 0.10, 1.70), "at": Vector3(0.42, 1.05, 0.86), "mat": timber},
		# Wagon body and its sideboards.
		{"size": Vector3(1.32, 0.52, 2.40), "at": Vector3(0.0, 1.04, -0.60), "mat": timber},
		{"size": Vector3(0.12, 0.44, 2.40), "at": Vector3(-0.66, 1.44, -0.60), "mat": timber},
		{"size": Vector3(0.12, 0.44, 2.40), "at": Vector3(0.66, 1.44, -0.60), "mat": timber},
		{"size": Vector3(1.32, 0.12, 0.44), "at": Vector3(0.0, 1.44, -1.78), "mat": timber},
		# The load, heaped above the boards so the cart reads as working, not empty.
		{"size": Vector3(1.10, 0.56, 1.70), "at": Vector3(0.0, 1.56, -0.70), "mat": load_mat},
		# Wheels, standing proud of the body on both sides.
		{"size": Vector3(0.16, 1.02, 1.02), "at": Vector3(-0.74, 0.51, 0.28), "mat": timber},
		{"size": Vector3(0.16, 1.02, 1.02), "at": Vector3(0.74, 0.51, 0.28), "mat": timber},
		{"size": Vector3(0.16, 1.14, 1.14), "at": Vector3(-0.74, 0.57, -1.44), "mat": timber},
		{"size": Vector3(0.16, 1.14, 1.14), "at": Vector3(0.74, 0.57, -1.44), "mat": timber},
		# Carter on the board.
		{"size": Vector3(0.46, 0.58, 0.30), "at": Vector3(0.0, 1.66, 0.42), "mat": cloth},
		{"size": Vector3(0.26, 0.26, 0.26), "at": Vector3(0.0, 2.06, 0.42), "mat": skin},
		{"size": Vector3(0.14, 0.44, 0.16), "at": Vector3(-0.28, 1.64, 0.60), "mat": cloth},
		{"size": Vector3(0.14, 0.44, 0.16), "at": Vector3(0.28, 1.64, 0.60), "mat": cloth},
	]


static func dog_parts(pelt: String) -> Array[Dictionary]:
	return [
		{"size": Vector3(0.30, 0.32, 0.78), "at": Vector3(0.0, 0.56, 0.0), "mat": pelt},
		{"size": Vector3(0.26, 0.26, 0.30), "at": Vector3(0.0, 0.72, 0.52), "mat": pelt},
		{"size": Vector3(0.10, 0.10, 0.34), "at": Vector3(0.0, 0.70, -0.52), "mat": pelt},
		{"size": Vector3(0.11, 0.40, 0.11), "at": Vector3(-0.11, 0.20, 0.26), "mat": pelt, "limb": LEG_A},
		{"size": Vector3(0.11, 0.40, 0.11), "at": Vector3(0.11, 0.20, 0.26), "mat": pelt, "limb": LEG_B},
		{"size": Vector3(0.11, 0.40, 0.11), "at": Vector3(-0.11, 0.20, -0.26), "mat": pelt, "limb": LEG_B},
		{"size": Vector3(0.11, 0.40, 0.11), "at": Vector3(0.11, 0.20, -0.26), "mat": pelt, "limb": LEG_A},
	]
