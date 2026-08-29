extends Node

## Checks the background village plan: that no two building footprints overlap, that
## nothing intrudes on the hub plateau, and that the town is actually populated at
## every distance band rather than crowding one ring.
##
## Runs over several seeds, because a layout rule that only holds for one seed has not
## been shown to hold at all.

const SEEDS: Array[int] = [20259, 7, 918273, 44, 1010101]


func _ready() -> void:
	var failures := 0
	for seed_value in SEEDS:
		failures += _audit(seed_value)
	if failures == 0:
		print("VILLAGE RESULT 0 failures across %d seeds" % SEEDS.size())
	else:
		print("VILLAGE RESULT %d failures" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _audit(seed_value: int) -> int:
	var plan := VillagePlan.new()
	plan.generate(seed_value)
	var failures := 0

	var overlaps := plan.overlapping_pairs()
	if not overlaps.is_empty():
		failures += 1
		print("VILLAGE seed %d: %d overlapping plot pairs" % [seed_value, overlaps.size()])
		for pair in overlaps.slice(0, 5):
			var a: Dictionary = plan.plots[pair["a"]]
			var b: Dictionary = plan.plots[pair["b"]]
			print(
				"  %s at %v overlaps %s at %v"
				% [a["kind"], a["c"], b["kind"], b["c"]]
			)

	# Nothing may encroach on the hub plateau.
	var intruders := 0
	for plot in plan.plots:
		var centre: Vector2 = plot["c"]
		var size: Vector2 = plot["size"]
		if centre.length() - maxf(size.x, size.y) * 0.5 < VillagePlan.CLEARANCE:
			intruders += 1
	if intruders > 0:
		failures += 1
		print("VILLAGE seed %d: %d plots inside the hub clearance" % [seed_value, intruders])

	# Nothing cultivated may lie on a street or under a building.
	var stray := plan.field_conflicts()
	if not stray.is_empty():
		failures += 1
		print("VILLAGE seed %d: %d fields on roads or buildings" % [seed_value, stray.size()])
		for entry in stray.slice(0, 5):
			print("  %s at %v" % [entry["kind"], entry["c"]])

	# Every near band should be built up; an empty band means the town stops short.
	var per_band := {}
	for plot in plan.plots:
		var band: int = plot["band"]
		per_band[band] = int(per_band.get(band, 0)) + 1
	for band in 3:
		if int(per_band.get(band, 0)) < 12:
			failures += 1
			print(
				"VILLAGE seed %d: band %d has only %d buildings"
				% [seed_value, band, int(per_band.get(band, 0))]
			)

	var bands_desc := []
	for band in range(0, 5):
		bands_desc.append("b%d=%d" % [band, int(per_band.get(band, 0))])
	print(
		"VILLAGE seed %-8d %3d plots  %2d roads  %2d fields  %s  %s"
		% [
			seed_value,
			plan.plots.size(),
			plan.roads.size(),
			plan.fields.size(),
			" ".join(bands_desc),
			plan.counts_by_kind(),
		]
	)
	return failures
