class_name HubFauna
extends RefCounted

## Ambient life for the hub plaza — birds over the tower, strays between the stalls.
##
## Built from the same `PixelDioramaStyle.add_box` primitives as every other piece of hub dressing,
## so the animals sit in the same pixel-diorama language rather than looking like imported models.
##
## Purely visual: no collision body, no hurtbox, not in `lockable`. They cannot be hit, locked onto
## or walked into, and the player passes straight through them.

const BirdScript := preload("res://scripts/hub/hub_bird.gd")
const StrayScript := preload("res://scripts/hub/hub_stray.gd")

## Flight rings over the plaza: centre, radius, height, period in seconds, and how many birds share
## the ring. Staggered so the flock never lines up into a rotating spoke.
const BIRD_RINGS := [
	{"centre": Vector3(0.0, 0.0, -6.0), "radius": 16.0, "height": 15.0, "period": 26.0, "count": 4},
	{"centre": Vector3(-6.0, 0.0, 2.0), "radius": 11.0, "height": 11.5, "period": 19.0, "count": 3},
	{"centre": Vector3(9.0, 0.0, 4.0), "radius": 13.5, "height": 18.0, "period": 33.0, "count": 3},
]

## Where the strays live. Each keeps to a home patch rather than roaming the whole plaza, which is
## what makes them read as belonging to the stall they are next to.
const STRAYS := [
	# Cinder and Tallow used to sit at -15.6 and 16.2, which the enlarged stalls now stand on. Both
	# moved out to the flagstone just in front of their stall rather than further into the plaza:
	# Cinder's line is about the warm stone nearest the forge, and it should stay true.
	{"kind": "cat", "home": Vector3(-13.4, 0.0, 1.2), "range": 2.6, "tint": 0,
		"name": "Cinder", "dialogue": "stray_cat_cinder"},
	{"kind": "cat", "home": Vector3(13.6, 0.0, 9.4), "range": 2.2, "tint": 1,
		"name": "Tallow", "dialogue": "stray_cat_tallow"},
	{"kind": "cat", "home": Vector3(-4.0, 0.0, 12.0), "range": 3.0, "tint": 2,
		"name": "Ash", "dialogue": "stray_cat_ash"},
	{"kind": "dog", "home": Vector3(13.0, 0.0, -1.0), "range": 3.6, "tint": 0,
		"name": "Rook", "dialogue": "stray_dog_rook"},
	{"kind": "dog", "home": Vector3(-9.0, 0.0, -9.5), "range": 4.0, "tint": 1,
		"name": "Bramble", "dialogue": "stray_dog_bramble"},
]

## Interact zone size. Wider than the NPC capsule (0.6m): an animal that wanders while you are
## walking up to it is much harder to stand on top of than a shopkeeper who never moves.
const STRAY_INTERACT_RADIUS := 1.4

const BIRD_TINTS := [
	Color(0.22, 0.2, 0.26),
	Color(0.3, 0.27, 0.32),
	Color(0.18, 0.17, 0.22),
]
const CAT_TINTS := [
	Color(0.28, 0.25, 0.24),
	Color(0.78, 0.7, 0.55),
	Color(0.42, 0.38, 0.4),
]
const DOG_TINTS := [
	Color(0.55, 0.42, 0.28),
	Color(0.35, 0.3, 0.26),
]


static func apply(hub: Node3D) -> void:
	if hub.get_node_or_null("HubFauna") != null:
		return
	var root := Node3D.new()
	root.name = "HubFauna"
	hub.add_child(root)
	_spawn_birds(root)
	_spawn_strays(root)


static func _spawn_birds(root: Node3D) -> void:
	var index := 0
	for ring: Dictionary in BIRD_RINGS:
		var count := int(ring["count"])
		for i in count:
			var bird := Node3D.new()
			bird.name = "Bird%d" % index
			root.add_child(bird)
			var tint: Color = BIRD_TINTS[index % BIRD_TINTS.size()]
			var wings := _build_bird(bird, tint)
			bird.set_script(BirdScript)
			bird.call(
				"setup",
				ring["centre"],
				float(ring["radius"]) + (index % 3) * 0.8,
				float(ring["height"]) + (index % 4) * 0.7,
				float(ring["period"]),
				# Spread round the ring, plus a nudge so two rings never beat together.
				TAU * float(i) / float(count) + index * 0.37,
				wings
			)
			index += 1


## Returns the two wing pivots, which the flight script rotates to flap.
static func _build_bird(parent: Node3D, tint: Color) -> Array:
	var body_mat := PixelDioramaStyle.make_material(tint)
	var beak_mat := PixelDioramaStyle.make_material(Color(0.85, 0.62, 0.24))
	PixelDioramaStyle.add_box(
		parent, Vector3(0.2, 0.16, 0.38), Vector3.ZERO, body_mat, "Body"
	)
	PixelDioramaStyle.add_box(
		parent, Vector3(0.16, 0.15, 0.16), Vector3(0.0, 0.06, 0.24), body_mat, "Head"
	)
	PixelDioramaStyle.add_box(
		parent, Vector3(0.06, 0.05, 0.12), Vector3(0.0, 0.04, 0.36), beak_mat, "Beak"
	)
	PixelDioramaStyle.add_box(
		parent, Vector3(0.14, 0.05, 0.2), Vector3(0.0, 0.02, -0.28), body_mat, "Tail"
	)
	var wings: Array = []
	for side in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.name = "Wing%s" % ("R" if side > 0.0 else "L")
		pivot.position = Vector3(side * 0.09, 0.05, 0.0)
		parent.add_child(pivot)
		PixelDioramaStyle.add_box(
			pivot, Vector3(0.34, 0.05, 0.22), Vector3(side * 0.18, 0.0, 0.0), body_mat, "Feather"
		)
		wings.append(pivot)
	return wings


static func _spawn_strays(root: Node3D) -> void:
	for i in STRAYS.size():
		var spec: Dictionary = STRAYS[i]
		var kind := str(spec["kind"])
		var animal := Node3D.new()
		animal.name = "%s%d" % [kind.capitalize(), i]
		root.add_child(animal)
		var parts: Dictionary = (
			_build_cat(animal, CAT_TINTS[int(spec["tint"]) % CAT_TINTS.size()])
			if kind == "cat"
			else _build_dog(animal, DOG_TINTS[int(spec["tint"]) % DOG_TINTS.size()])
		)
		animal.set_script(StrayScript)
		animal.call(
			"setup",
			spec["home"],
			float(spec["range"]),
			1.15 if kind == "cat" else 1.55,
			parts.get("tail", null),
			parts.get("body", null)
		)
		_add_stray_interact(animal, spec, kind)


## The same `HubInteractable` zone every shopkeeper uses, so petting a cat goes through exactly the
## routing that talking to a blacksmith does — the hub already knows how to turn an `npc:` interact
## id into a conversation, and an animal is not a special case worth a second path.
##
## The zone is a child of the animal, so it wanders with it.
static func _add_stray_interact(animal: Node3D, spec: Dictionary, kind: String) -> void:
	var area := Area3D.new()
	area.name = "InteractArea"
	area.collision_layer = 0
	area.collision_mask = 2
	area.set_script(load("res://scripts/hub/hub_interactable.gd"))
	area.set("interact_id", "stray:%s" % str(spec["dialogue"]))
	area.set("prompt_text", "%s (E)" % str(spec["name"]))
	area.set("enter_sound", &"" )
	animal.add_child(area)
	area.connect("player_entered", Callable(animal, "set_player_near").bind(true))
	area.connect("player_exited", Callable(animal, "set_player_near").bind(false))
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = STRAY_INTERACT_RADIUS
	shape.shape = sphere
	shape.position = Vector3(0.0, 0.4, 0.0)
	area.add_child(shape)

	var label := Label3D.new()
	label.name = "NameLabel"
	label.text = str(spec["name"])
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 18
	label.position = Vector3(0.0, 1.0 if kind == "dog" else 0.8, 0.0)
	label.modulate = Color(0.86, 0.82, 0.78)
	animal.add_child(label)


static func _build_cat(parent: Node3D, tint: Color) -> Dictionary:
	var fur := PixelDioramaStyle.make_material(tint)
	var dark := PixelDioramaStyle.make_material(tint.darkened(0.3))
	var body := Node3D.new()
	body.name = "Body"
	body.position = Vector3(0.0, 0.24, 0.0)
	parent.add_child(body)
	PixelDioramaStyle.add_box(body, Vector3(0.2, 0.18, 0.44), Vector3.ZERO, fur, "Trunk")
	PixelDioramaStyle.add_box(body, Vector3(0.2, 0.2, 0.18), Vector3(0.0, 0.1, 0.28), fur, "Head")
	for side in [-1.0, 1.0]:
		PixelDioramaStyle.add_box(
			body, Vector3(0.06, 0.09, 0.05), Vector3(side * 0.06, 0.22, 0.28), dark, "Ear"
		)
	for corner in [Vector3(-0.07, 0.0, 0.15), Vector3(0.07, 0.0, 0.15),
			Vector3(-0.07, 0.0, -0.15), Vector3(0.07, 0.0, -0.15)]:
		PixelDioramaStyle.add_box(
			parent, Vector3(0.06, 0.24, 0.06), corner + Vector3(0.0, 0.12, 0.0), dark, "Leg"
		)
	var tail := Node3D.new()
	tail.name = "Tail"
	tail.position = Vector3(0.0, 0.3, -0.22)
	parent.add_child(tail)
	PixelDioramaStyle.add_box(tail, Vector3(0.05, 0.28, 0.05), Vector3(0.0, 0.14, 0.0), fur, "Fur")
	return {"tail": tail, "body": body}


static func _build_dog(parent: Node3D, tint: Color) -> Dictionary:
	var fur := PixelDioramaStyle.make_material(tint)
	var dark := PixelDioramaStyle.make_material(tint.darkened(0.28))
	var body := Node3D.new()
	body.name = "Body"
	body.position = Vector3(0.0, 0.38, 0.0)
	parent.add_child(body)
	PixelDioramaStyle.add_box(body, Vector3(0.28, 0.26, 0.6), Vector3.ZERO, fur, "Trunk")
	PixelDioramaStyle.add_box(body, Vector3(0.26, 0.26, 0.24), Vector3(0.0, 0.12, 0.38), fur, "Head")
	PixelDioramaStyle.add_box(
		body, Vector3(0.15, 0.13, 0.18), Vector3(0.0, 0.04, 0.52), dark, "Snout"
	)
	for side in [-1.0, 1.0]:
		PixelDioramaStyle.add_box(
			body, Vector3(0.07, 0.14, 0.06), Vector3(side * 0.1, 0.26, 0.36), dark, "Ear"
		)
	for corner in [Vector3(-0.1, 0.0, 0.2), Vector3(0.1, 0.0, 0.2),
			Vector3(-0.1, 0.0, -0.2), Vector3(0.1, 0.0, -0.2)]:
		PixelDioramaStyle.add_box(
			parent, Vector3(0.09, 0.38, 0.09), corner + Vector3(0.0, 0.19, 0.0), dark, "Leg"
		)
	var tail := Node3D.new()
	tail.name = "Tail"
	tail.position = Vector3(0.0, 0.48, -0.3)
	parent.add_child(tail)
	PixelDioramaStyle.add_box(tail, Vector3(0.07, 0.26, 0.07), Vector3(0.0, 0.13, 0.0), fur, "Fur")
	return {"tail": tail, "body": body}
