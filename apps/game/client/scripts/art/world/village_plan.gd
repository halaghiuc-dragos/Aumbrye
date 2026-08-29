class_name VillagePlan
extends RefCounted

## Procedural town plan for the background village.
##
## This produces *data only* -- roads, building plots and walking routes as plain
## dictionaries in world XZ metres. `distant_skyline.gd` turns that data into batched
## geometry. Keeping the plan separate from the geometry is what makes the no-overlap
## guarantee checkable: every plot is accepted or rejected before a single box exists.
##
## The layout rule is the one real medieval towns follow: buildings front onto a street.
## Plots are not scattered by angle-and-jitter (which is what let them collide before);
## they are walked along each road, offset to one side by a setback, and tested against
## everything already placed -- including the roads themselves, so nothing ever sits on
## a carriageway. A rejected plot is simply skipped, so the guarantee holds by
## construction rather than by tuning the numbers until it looks alright.

## Keep clear of the hub plateau. Nothing is planned inside this radius.
const CLEARANCE := 34.0

## Rings of the street plan, innermost first. These are the "ring roads" of the town;
## the radius is modulated per-angle below so they read as organic rather than as
## drawn with a compass.
const RING_RADII: Array[float] = [46.0, 78.0, 112.0, 150.0, 196.0, 250.0]

## Radial streets running out from the town centre.
const SPOKE_COUNT := 7

## How far past the outermost ring the perimeter lane runs. Spokes terminate on that
## lane at one end and on the innermost ring at the other, which is what makes "no road
## ends abruptly" true by construction rather than by eye.
const OUTER_CIRCUIT_GAP := 46.0

## Carriageway widths by street rank. 0 = spoke/high street, 1 = ring road, 2 = outer lane.
const ROAD_WIDTH: Array[float] = [5.4, 4.2, 3.2]

## Distance bands, as outer radii. Band index selects what gets built and how much
## detail it is worth: the far ones are read as silhouettes and are built cheaply.
const BAND_EDGES: Array[float] = [88.0, 130.0, 180.0, 265.0, 360.0]

## Clear gap left between a building's footprint and anything else, in metres. Each
## rect is inflated by half of this, so two neighbours end up exactly PLOT_MARGIN
## apart -- the margin that makes "not overlapping" visibly true, not just technically.
const PLOT_MARGIN := 1.3

## Verge left either side of a carriageway when a road claims its ground. The crowd
## walks a little wider than the metalling -- people on a country lane walk beside it,
## not down the middle -- so the road reserves that strip too, and nothing gets planted
## where a villager would then walk through it.
const ROAD_VERGE := 0.9

## Occupancy grid cell size. Only affects how many candidates each test compares
## against, never whether the test is correct.
const CELL := 8.0

var roads: Array[Dictionary] = []
var plots: Array[Dictionary] = []
## Cultivated ground: crop strips, orchards and paddocks, each one a reserved rect that
## went through the same overlap test as a building, so no crop can ever end up on a
## carriageway or inside somebody's house.
var fields: Array[Dictionary] = []
var routes: Array[PackedVector2Array] = []
var plaza: Dictionary = {}

var _rng := RandomNumberGenerator.new()
var _grid: Dictionary = {}
var _rects: Array[Dictionary] = []


func generate(seed_value: int) -> void:
	_rng.seed = seed_value
	roads.clear()
	plots.clear()
	fields.clear()
	routes.clear()
	_grid.clear()
	_rects.clear()

	_build_streets()
	_reserve_plaza()
	_place_landmarks()
	_place_frontages()
	_place_outskirts()
	# Last, so buildings and streets always win the ground they want and the crops take
	# what is left over -- which is how a real village grows anyway.
	_place_fields()


# --- streets ---------------------------------------------------------------------


## A ring road, described rather than drawn. The radius is modulated by whole-number
## harmonics of the angle so the loop still meets itself exactly after a full turn, and
## keeping the harmonics as data means a spoke can ask the ring where its carriageway
## actually is at a given bearing -- which is what lets the two meet at a junction
## instead of near one.
func _ring_params(radius: float, wobble: float) -> Dictionary:
	return {
		"radius": radius,
		"wobble": wobble,
		"k1": _rng.randi_range(2, 4),
		"k2": _rng.randi_range(5, 8),
		"p1": _rng.randf() * TAU,
		"p2": _rng.randf() * TAU,
	}


static func _ring_radius_at(ring: Dictionary, angle: float) -> float:
	var k1: float = float(ring["k1"])
	var k2: float = float(ring["k2"])
	return float(ring["radius"]) * (
		1.0
		+ float(ring["wobble"])
		* (
			sin(k1 * angle + float(ring["p1"])) * 0.62
			+ sin(k2 * angle + float(ring["p2"])) * 0.38
		)
	)


static func _ring_polyline(ring: Dictionary) -> PackedVector2Array:
	var steps := int(clampf(float(ring["radius"]) * 0.5, 28.0, 96.0))
	var out := PackedVector2Array()
	for i in steps + 1:
		var a := TAU * float(i) / float(steps)
		var r := _ring_radius_at(ring, a)
		out.append(Vector2(cos(a) * r, sin(a) * r))
	return out


## Bearing of a spoke at `t` along its run. Pulled out of the polyline loop because the
## endpoints have to be evaluated before the loop starts, to look up where the rings
## they terminate on happen to be at those bearings.
static func _spoke_bearing(angle: float, drift: float, t: float) -> float:
	return angle + drift * t * t + sin(t * 3.1 + angle) * 0.03


## A street running outward from the town centre. The bearing drifts as it goes so the
## spokes are not perfectly straight spears. Both ends land on a ring road's
## carriageway, so a spoke always begins and ends at a junction: no radial street stops
## dead in open ground.
func _spoke_polyline(angle: float, inner: Dictionary, outer: Dictionary) -> PackedVector2Array:
	var out := PackedVector2Array()
	var steps := 16
	var drift := _rng.randf_range(-0.16, 0.16)
	var from_r := _ring_radius_at(inner, _spoke_bearing(angle, drift, 0.0))
	var to_r := _ring_radius_at(outer, _spoke_bearing(angle, drift, 1.0))
	for i in steps + 1:
		var t := float(i) / float(steps)
		var r := lerpf(from_r, to_r, t)
		var a := _spoke_bearing(angle, drift, t)
		out.append(Vector2(cos(a) * r, sin(a) * r))
	return out


func _add_road(points: PackedVector2Array, rank: int) -> void:
	if points.size() < 2:
		return
	var width: float = ROAD_WIDTH[clampi(rank, 0, ROAD_WIDTH.size() - 1)]
	roads.append({"points": points, "width": width, "rank": rank})
	routes.append(points)
	# Reserve the carriageway itself. Because plots are tested against these rects too,
	# no building can ever land on a road -- including where another road passes behind it.
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		var mid := (a + b) * 0.5
		var span := b - a
		var length := span.length()
		if length <= 0.01:
			continue
		_occupy({
			"c": mid,
			"e": Vector2(length * 0.5, width * 0.5 + ROAD_VERGE),
			"yaw": atan2(span.y, span.x),
			"tag": "road",
		})


func _build_streets() -> void:
	# Ring roads, innermost first. The innermost one is held on to: the spokes start on
	# it. They used to start at CLEARANCE + 4, four metres off the plateau cliff, which
	# reads as a stone road beginning at nothing.
	var inner_ring: Dictionary = {}
	for i in RING_RADII.size():
		var wobble := 0.05 if i < 2 else 0.085
		var ring := _ring_params(RING_RADII[i], wobble)
		if i == 0:
			inner_ring = ring
		_add_road(_ring_polyline(ring), 1 if i < 3 else 2)

	# The perimeter lane. The spokes used to run past the last ring and stop, which left
	# seven stone roads ending abruptly in open country; now they all meet this.
	var outer_ring := _ring_params(RING_RADII[RING_RADII.size() - 1] + OUTER_CIRCUIT_GAP, 0.075)
	_add_road(_ring_polyline(outer_ring), 2)

	var base := _rng.randf() * TAU
	for i in SPOKE_COUNT:
		var angle := base + TAU * float(i) / float(SPOKE_COUNT) + _rng.randf_range(-0.07, 0.07)
		_add_road(_spoke_polyline(angle, inner_ring, outer_ring), 0)


# --- reservations ----------------------------------------------------------------


## Pick a spot in the open ground between two ring roads. Everything sizeable in a
## town centre has to fit *between* the streets, so the plot is laid out tangentially:
## `size.x` runs along the ring (plenty of room) and `size.y` runs radially, across the
## gap (where the space is tight). Orienting these radially is what left the church
## straddling two carriageways with nowhere to go.
func _try_in_gap(kind: String, size: Vector2, gap: int, attempts: int) -> bool:
	var inner: float = RING_RADII[gap]
	var outer: float = RING_RADII[gap + 1]
	for i in attempts:
		var angle := _rng.randf() * TAU
		var mid := (inner + outer) * 0.5 + _rng.randf_range(-2.0, 2.0)
		var at := Vector2(cos(angle) * mid, sin(angle) * mid)
		# Tangential: local X along the ring, local Y across the gap.
		var yaw := angle + PI * 0.5
		if _try_plot(kind, at, yaw, size, band_for(mid), -Vector2(cos(angle), sin(angle))):
			return true
	return false


## The market square, reserved before any housing so the town has a centre the
## frontage pass must build around rather than fill in.
func _reserve_plaza() -> void:
	for i in 60:
		var angle := _rng.randf() * TAU
		var mid: float = (RING_RADII[0] + RING_RADII[1]) * 0.5
		var at := Vector2(cos(angle) * mid, sin(angle) * mid)
		var yaw := angle + PI * 0.5
		var half := Vector2(16.0, 11.0)
		var rect := {"c": at, "e": half, "yaw": yaw}
		if _overlaps(rect):
			continue
		plaza = {"c": at, "e": half, "yaw": yaw}
		_occupy({"c": at, "e": half, "yaw": yaw, "tag": "plaza"})
		return
	plaza = {}


## Landmarks are what the eye actually reads at this distance, so they get a search
## rather than a single try: one fixed spot lands on a carriageway as often as not, and
## a rejected church leaves the town with no skyline at all.
func _place_landmarks() -> void:
	# The church wants the centre, near the market, so try the inner gaps first.
	if not _try_in_gap("church", Vector2(38.0, 21.0), 0, 40):
		if not _try_in_gap("church", Vector2(38.0, 21.0), 1, 40):
			push_warning("VillagePlan: no room for the church")

	# The castle sits apart from the market, further out, and gets more room.
	if not _try_in_gap("castle", Vector2(26.0, 26.0), 2, 60):
		if not _try_in_gap("castle", Vector2(26.0, 26.0), 3, 60):
			push_warning("VillagePlan: no room for the castle")

	# Windmills want open ground and wind, so they go out past the built-up rings.
	var mills := 0
	for i in 60:
		if mills >= 4:
			break
		var a := _rng.randf() * TAU
		var r: float = RING_RADII[RING_RADII.size() - 2] + _rng.randf_range(10.0, 90.0)
		if _try_plot("windmill", Vector2(cos(a) * r, sin(a) * r), a, Vector2(9.0, 9.0), band_for(r)):
			mills += 1


# --- frontages -------------------------------------------------------------------


func band_for(radius: float) -> int:
	for i in BAND_EDGES.size():
		if radius <= BAND_EDGES[i]:
			return i
	return BAND_EDGES.size()


## Walk every street and try to seat a building on each side of it, facing the road.
## This is what gives the town streets with two built-up sides instead of a scatter.
func _place_frontages() -> void:
	for road in roads:
		var points: PackedVector2Array = road["points"]
		var width: float = road["width"]
		var rank: int = road["rank"]
		# Spokes are the high streets, so they get the tightest frontage.
		var gap_base := 1.6 if rank == 0 else 2.4
		var lengths := _cumulative(points)
		var total: float = lengths[lengths.size() - 1]
		for side_index in 2:
			var side := -1.0 if side_index == 0 else 1.0
			# Start each side at its own offset so the two rows do not line up
			# door-for-door across the street.
			var along := _rng.randf_range(0.0, 11.0)
			while along < total:
				var head := _sample(points, lengths, along)
				var radius: float = (head["p"] as Vector2).length()
				if radius < CLEARANCE + 6.0:
					along += 8.0
					continue
				var band := band_for(radius)
				# Past the last band there is no town left to build, only open country.
				if band >= 4:
					along += 14.0
					continue
				# Out in the fields the lanes are farm tracks: frontage thins out rather
				# than stopping at a hard edge, so the town fades into country.
				if band == 3 and _rng.randf() < 0.55:
					along += _rng.randf_range(12.0, 26.0)
					continue
				var kind := _kind_for(band)
				var size := _size_for(kind)
				# The terrace runs *along* the street, so step by its frontage width.
				var mid := _sample(points, lengths, along + size.x * 0.5)
				var dir: Vector2 = mid["d"]
				var normal := Vector2(-dir.y, dir.x) * side
				var setback := width * 0.5 + gap_base + _rng.randf_range(0.0, 1.6)
				var centre: Vector2 = (mid["p"] as Vector2) + normal * (setback + size.y * 0.5)
				var yaw := atan2(dir.y, dir.x) + _rng.randf_range(-0.04, 0.04)
				# `face` points back at the carriageway, so the geometry knows which
				# wall gets the door and the windows.
				_try_plot(kind, centre, yaw, size, band, -normal)
				along += size.x + PLOT_MARGIN + _rng.randf_range(0.3, 3.4)


## Arc length at each vertex, so a polyline can be walked by metres travelled rather
## than by vertex index -- frontage spacing has to be in metres to be uniform.
static func _cumulative(points: PackedVector2Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.append(0.0)
	var total := 0.0
	for i in points.size() - 1:
		total += points[i].distance_to(points[i + 1])
		out.append(total)
	return out


## Position and unit direction at `distance` along the polyline.
static func _sample(
	points: PackedVector2Array, lengths: PackedFloat32Array, distance: float
) -> Dictionary:
	var last := points.size() - 1
	var clamped := clampf(distance, 0.0, lengths[last])
	var i := 0
	while i < last - 1 and lengths[i + 1] < clamped:
		i += 1
	var span: float = lengths[i + 1] - lengths[i]
	var t := 0.0 if span <= 0.0001 else (clamped - lengths[i]) / span
	var a := points[i]
	var b := points[i + 1]
	var dir := (b - a)
	if dir.length() <= 0.0001:
		dir = Vector2.RIGHT
	return {"p": a.lerp(b, t), "d": dir.normalized()}


## Farmsteads and barns scattered across the fields beyond the last ring road. These
## are placed by rejection sampling rather than frontage -- out here there is no street
## to line up on -- but they go through the same overlap test.
func _place_outskirts() -> void:
	var outer: float = BAND_EDGES[BAND_EDGES.size() - 1]
	var attempts := 520
	for i in attempts:
		var a := _rng.randf() * TAU
		# Square-root weighting spreads them evenly over area instead of crowding the centre.
		var t := sqrt(_rng.randf())
		var r: float = lerpf(RING_RADII[RING_RADII.size() - 1] + 10.0, outer, t)
		var band := band_for(r)
		var kind := "farm" if band <= 3 else "silhouette"
		_try_plot(
			kind,
			Vector2(cos(a) * r, sin(a) * r),
			_rng.randf() * TAU,
			_size_for(kind),
			band
		)


func _kind_for(band: int) -> String:
	var roll := _rng.randf()
	match band:
		0:
			# The core is townhouses in terraces, with the odd hall or workshop.
			if roll < 0.18:
				return "hall"
			return "terrace"
		1:
			if roll < 0.24:
				return "terrace"
			return "cottage"
		_:
			if roll < 0.3:
				return "barn"
			return "cottage"


func _size_for(kind: String) -> Vector2:
	match kind:
		"terrace":
			return Vector2(_rng.randf_range(15.0, 25.0), _rng.randf_range(7.0, 9.0))
		"hall":
			return Vector2(_rng.randf_range(13.0, 18.0), _rng.randf_range(9.5, 12.0))
		"cottage":
			return Vector2(_rng.randf_range(7.0, 12.5), _rng.randf_range(6.0, 7.6))
		"barn":
			return Vector2(_rng.randf_range(11.0, 16.0), _rng.randf_range(7.5, 9.5))
		"farm":
			return Vector2(_rng.randf_range(9.0, 14.0), _rng.randf_range(7.0, 9.0))
		"silhouette":
			return Vector2(_rng.randf_range(8.0, 16.0), _rng.randf_range(7.0, 10.0))
	return Vector2(10.0, 7.0)


# --- cultivated ground -----------------------------------------------------------


## Strips of crop, orchard and paddock in whatever open ground the town left. Placed by
## rejection sampling against the same occupancy grid the buildings used, so a strip is
## either wholly in a free space or not placed at all -- there is no partial acceptance
## that could leave a furrow lying across a road.
func _place_fields() -> void:
	# Crops start outside the built-up core: nobody sows barley in the high street's
	# back yards, and a strip wedged between two terraces reads as a mistake even when
	# it technically fits.
	var inner: float = RING_RADII[1] + 6.0
	var outer: float = BAND_EDGES[BAND_EDGES.size() - 1] - 10.0
	var wanted := 46
	var placed := 0
	for i in 900:
		if placed >= wanted:
			break
		var angle := _rng.randf() * TAU
		var r := lerpf(inner, outer, sqrt(_rng.randf()))
		var at := Vector2(cos(angle) * r, sin(angle) * r)
		# Strips run tangentially, following the lie of the land around the town, and
		# the far ones are larger because there is more room out there.
		var scale := clampf(r / 160.0, 0.55, 1.6)
		var size := Vector2(
			_rng.randf_range(11.0, 21.0) * scale, _rng.randf_range(8.0, 15.0) * scale
		)
		var yaw := angle + PI * 0.5 + _rng.randf_range(-0.5, 0.5)
		var roll := _rng.randf()
		var kind := "crop"
		if roll > 0.82:
			kind = "paddock"
		elif roll > 0.66:
			kind = "orchard"
		if not try_reserve(at, yaw, size, kind):
			continue
		fields.append({"kind": kind, "c": at, "yaw": yaw, "size": size, "band": band_for(r)})
		placed += 1


## Is this footprint free of every street, plot and field placed so far? Test only --
## nothing is claimed, so it is the right call for scatter that is happy to be skipped.
func is_clear(centre: Vector2, yaw: float, size: Vector2) -> bool:
	if centre.length() - maxf(size.x, size.y) * 0.5 < CLEARANCE:
		return false
	return not _overlaps({"c": centre, "e": size * 0.5, "yaw": yaw})


## Claim a footprint for something that is not a building -- a crop strip, an orchard,
## a stand of trees. Returns false and claims nothing if the ground is already taken.
func try_reserve(centre: Vector2, yaw: float, size: Vector2, tag: String) -> bool:
	var half := size * 0.5 + Vector2(PLOT_MARGIN, PLOT_MARGIN) * 0.5
	if centre.length() - maxf(half.x, half.y) < CLEARANCE:
		return false
	var rect := {"c": centre, "e": half, "yaw": yaw}
	if _overlaps(rect):
		return false
	_occupy({"c": centre, "e": half, "yaw": yaw, "tag": tag})
	return true


# --- placement and bounds --------------------------------------------------------


func _try_plot(
	kind: String,
	centre: Vector2,
	yaw: float,
	size: Vector2,
	band: int,
	face: Vector2 = Vector2.ZERO
) -> bool:
	var half := size * 0.5
	var pad := Vector2(PLOT_MARGIN, PLOT_MARGIN) * 0.5
	var rect := {"c": centre, "e": half + pad, "yaw": yaw}
	if centre.length() - maxf(half.x, half.y) < CLEARANCE:
		return false
	if _overlaps(rect):
		return false
	_occupy({"c": centre, "e": half + pad, "yaw": yaw, "tag": kind})
	# With no street to face, the building simply faces outward from the town.
	var facing := face if face.length_squared() > 0.0001 else centre.normalized()
	plots.append({
		"kind": kind,
		"c": centre,
		"yaw": yaw,
		"size": size,
		"band": band,
		"face": facing,
	})
	return true


func _cells_for(rect: Dictionary) -> Array[Vector2i]:
	# An axis-aligned bound over the rotated rect is enough to pick candidate cells;
	# the exact test happens per-candidate in _overlaps.
	var e: Vector2 = rect["e"]
	var c: Vector2 = rect["c"]
	var reach := e.length()
	var out: Array[Vector2i] = []
	var x0 := int(floor((c.x - reach) / CELL))
	var x1 := int(floor((c.x + reach) / CELL))
	var y0 := int(floor((c.y - reach) / CELL))
	var y1 := int(floor((c.y + reach) / CELL))
	for x in range(x0, x1 + 1):
		for y in range(y0, y1 + 1):
			out.append(Vector2i(x, y))
	return out


func _occupy(rect: Dictionary) -> void:
	var index := _rects.size()
	_rects.append(rect)
	for cell in _cells_for(rect):
		if not _grid.has(cell):
			_grid[cell] = PackedInt32Array()
		var bucket: PackedInt32Array = _grid[cell]
		bucket.append(index)
		_grid[cell] = bucket


func _overlaps(rect: Dictionary) -> bool:
	var seen := {}
	for cell in _cells_for(rect):
		if not _grid.has(cell):
			continue
		var bucket: PackedInt32Array = _grid[cell]
		for index in bucket:
			if seen.has(index):
				continue
			seen[index] = true
			if _obb_overlap(rect, _rects[index]):
				return true
	return false


## Separating-axis test for two oriented rectangles. Two convex shapes miss each other
## if and only if some axis separates them, and for rectangles only the four face
## normals can be that axis -- so four projections settle it.
static func _obb_overlap(a: Dictionary, b: Dictionary) -> bool:
	var a_yaw: float = a["yaw"]
	var b_yaw: float = b["yaw"]
	var axes := [
		Vector2(cos(a_yaw), sin(a_yaw)),
		Vector2(-sin(a_yaw), cos(a_yaw)),
		Vector2(cos(b_yaw), sin(b_yaw)),
		Vector2(-sin(b_yaw), cos(b_yaw)),
	]
	var delta: Vector2 = (b["c"] as Vector2) - (a["c"] as Vector2)
	for axis in axes:
		var ax: Vector2 = axis
		if _extent(a, ax) + _extent(b, ax) <= absf(delta.dot(ax)):
			return false
	return true


## Half-width of a rectangle's shadow on `axis`.
static func _extent(rect: Dictionary, axis: Vector2) -> float:
	var yaw: float = rect["yaw"]
	var e: Vector2 = rect["e"]
	var ux := Vector2(cos(yaw), sin(yaw))
	var uy := Vector2(-sin(yaw), cos(yaw))
	return absf(ux.dot(axis)) * e.x + absf(uy.dot(axis)) * e.y


# --- reporting -------------------------------------------------------------------


## Used by the audit scene to prove the guarantee rather than assert it. This tests the
## *bare* footprints, with no margin added, so it measures real overlap rather than
## re-running the placement rule and agreeing with itself.
func overlapping_pairs() -> Array[Dictionary]:
	var buckets: Dictionary = {}
	var rects: Array[Dictionary] = []
	for plot in plots:
		rects.append({
			"c": plot["c"],
			"e": (plot["size"] as Vector2) * 0.5,
			"yaw": plot["yaw"],
		})
	for i in rects.size():
		for cell in _cells_for(rects[i]):
			if not buckets.has(cell):
				buckets[cell] = PackedInt32Array()
			var bucket: PackedInt32Array = buckets[cell]
			bucket.append(i)
			buckets[cell] = bucket

	var out: Array[Dictionary] = []
	var seen: Dictionary = {}
	for cell in buckets:
		var bucket: PackedInt32Array = buckets[cell]
		for x in bucket.size():
			for y in range(x + 1, bucket.size()):
				var i: int = bucket[x]
				var j: int = bucket[y]
				var key := mini(i, j) * 100000 + maxi(i, j)
				if seen.has(key):
					continue
				seen[key] = true
				if _obb_overlap(rects[i], rects[j]):
					out.append({"a": i, "b": j})
	return out


## Every carriageway as a bare rectangle, rebuilt from the published road polylines
## rather than read out of the occupancy grid, so a caller can check "is this on a
## road?" against the same streets that get drawn.
func road_rects() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for road in roads:
		var points: PackedVector2Array = road["points"]
		var width: float = road["width"]
		for i in points.size() - 1:
			var a: Vector2 = points[i]
			var b: Vector2 = points[i + 1]
			var span := b - a
			var length := span.length()
			if length <= 0.01:
				continue
			out.append({
				"c": (a + b) * 0.5,
				"e": Vector2(length * 0.5, width * 0.5),
				"yaw": atan2(span.y, span.x),
			})
	return out


## Cultivated ground that has ended up on a street or under a building. Tests bare
## footprints with no margin, so it measures the thing the eye actually objects to --
## a furrow crossing a carriageway -- rather than re-running the placement rule.
func field_conflicts() -> Array[Dictionary]:
	var obstacles: Array[Dictionary] = road_rects()
	for plot in plots:
		obstacles.append({
			"c": plot["c"], "e": (plot["size"] as Vector2) * 0.5, "yaw": plot["yaw"]
		})
	var out: Array[Dictionary] = []
	for i in fields.size():
		var field: Dictionary = fields[i]
		var rect := {
			"c": field["c"], "e": (field["size"] as Vector2) * 0.5, "yaw": field["yaw"]
		}
		for obstacle in obstacles:
			if _obb_overlap(rect, obstacle):
				out.append({"field": i, "kind": field["kind"], "c": field["c"]})
				break
	return out


func counts_by_kind() -> Dictionary:
	var out: Dictionary = {}
	for plot in plots:
		var kind: String = plot["kind"]
		out[kind] = int(out.get(kind, 0)) + 1
	return out
