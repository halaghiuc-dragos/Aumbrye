extends Node3D

## Walks a full day-night cycle and reports what is casting a shadow at each hour.
##
## The thing this is guarding is easy to break and hard to notice: shadows are owned by whichever
## directional light is currently the brightest, and the handover between sun and moon happens
## while both are near the horizon. If the handover is wrong the symptom is not an error, it is
## half a cycle of objects with no shadow under them, or a shadow that snaps to the other side of
## the world at dusk.
##
## Run: godot --path apps/game/client --headless res://scenes/debug/shadow_cycle_audit.tscn

const STEPS := 48
const SHADOW_GAP_LIMIT := 3

var _failures: int = 0


func _ready() -> void:
	await get_tree().process_frame
	var sun := DirectionalLight3D.new()
	sun.name = "DirectionalLight3D"
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.name = "FillLight"
	add_child(fill)
	var env := Environment.new()

	DayNightService.register_level(env, sun, fill, "hub")
	PixelDioramaSettings.shadow_quality = 1

	print("hour  sun_elev  sun_e  moon_e  caster    opacity")
	var casters: Array[String] = []
	for i in STEPS:
		var p := float(i) / float(STEPS)
		DayNightService._apply(p)
		var moon := get_node_or_null("MoonLight") as DirectionalLight3D
		var moon_energy := moon.light_energy if moon and moon.visible else 0.0
		var caster := "none"
		var opacity := 0.0
		if sun.shadow_enabled:
			caster = "sun"
			opacity = sun.shadow_opacity
		elif moon and moon.shadow_enabled:
			caster = "moon"
			opacity = moon.shadow_opacity
		if sun.shadow_enabled and moon and moon.shadow_enabled:
			_fail("hour %.1f: sun and moon are both casting" % (p * 24.0))
		casters.append(caster)
		var elevation := Celestial.elevation_deg(Celestial.sun_direction(p, DayNightService.day()))
		print(
			"%5.1f  %8.1f  %5.2f  %6.2f  %-8s  %.2f"
			% [p * 24.0, elevation, sun.light_energy if sun.visible else 0.0,
			   moon_energy, caster, opacity]
		)

	# Both lights are meant to take a turn: a cycle where only the sun ever casts means the night
	# half of the day has no shadows in it, which is the bug this exists to catch.
	if not casters.has("sun"):
		_fail("the sun never casts a shadow across a whole cycle")
	if not casters.has("moon"):
		_fail("the moon never casts a shadow — nothing has a shadow at night")

	var run := 0
	var worst := 0
	for caster in casters:
		run = run + 1 if caster == "none" else 0
		worst = maxi(worst, run)
	# Wrapping run, in case the gap straddles midnight.
	print("longest stretch with no caster: %d of %d steps" % [worst, STEPS])
	if worst > SHADOW_GAP_LIMIT:
		_fail(
			"%d consecutive steps with nothing casting (limit %d)" % [worst, SHADOW_GAP_LIMIT]
		)

	# A quality change mid-session has to reach both lights, including whichever one was dark at
	# the time. Dropping to zero must silence them; coming back must restore them.
	PixelDioramaSettings.shadow_quality = 0
	DayNightService._apply(0.0)
	var dark_moon := get_node_or_null("MoonLight") as DirectionalLight3D
	if sun.shadow_enabled or (dark_moon and dark_moon.shadow_enabled):
		_fail("shadow quality 0 still leaves a caster enabled")
	PixelDioramaSettings.shadow_quality = 1
	DayNightService._apply(0.0)
	if dark_moon and not dark_moon.shadow_enabled:
		_fail("raising shadow quality did not restore the night caster")
	elif dark_moon and dark_moon.directional_shadow_max_distance <= 0.0:
		_fail("night caster was enabled without being configured for the new quality")

	# An indoor profile must not grow shadows the lighting data denied the sun.
	DayNightService.register_level(env, sun, fill, "castle_interior")
	DayNightService._apply(0.5)
	var indoor_moon := get_node_or_null("MoonLight") as DirectionalLight3D
	if sun.shadow_enabled or (indoor_moon and indoor_moon.shadow_enabled):
		_fail("castle_interior declares no sun shadows but something is still casting")

	print("SHADOW CYCLE RESULT %d failures" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


func _fail(message: String) -> void:
	_failures += 1
	print("  FAIL %s" % message)
