class_name HubFauna
extends RefCounted


const BirdScript := preload("res://scripts/hub/hub_bird.gd")
const StrayScript := preload("res://scripts/hub/hub_stray.gd")

const BIRD_RINGS := [
	{"centre": Vector3(0.0, 0.0, -6.0), "radius": 16.0, "height": 15.0, "period": 26.0, "count": 4},
	{"centre": Vector3(-6.0, 0.0, 2.0), "radius": 11.0, "height": 11.5, "period": 19.0, "count": 3},
	{"centre": Vector3(9.0, 0.0, 4.0), "radius": 13.5, "height": 18.0, "period": 33.0, "count": 3},
]

const STRAYS := [
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
				TAU * float(i) / float(count) + index * 0.37,
				wings
			)
			index += 1


static func _build_bird(parent: Node3D, tint: Color) -> Array:
	PropLibrary.attach_themed(
		parent, "fauna/bird", PixelDioramaStyle.PaletteTheme.HUB,
		{"materials": {"fur": PixelDioramaStyle.make_material(tint), "dark": PixelDioramaStyle.make_material(tint.darkened(0.25)), "beak": PixelDioramaStyle.make_material(Color(0.85, 0.62, 0.24))}}
	)
	return [parent.get_node("WingL"), parent.get_node("WingR")]


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
		animal.call("set_voice", &"stray_meow" if kind == "cat" else &"stray_bark")
		animal.call(
			"setup",
			spec["home"],
			float(spec["range"]),
			1.15 if kind == "cat" else 1.55,
			parts.get("tail", null),
			parts.get("body", null)
		)
		_add_stray_interact(animal, spec, kind)


static func _add_stray_interact(animal: Node3D, spec: Dictionary, kind: String) -> void:
	var area := Area3D.new()
	area.name = "InteractArea"
	area.collision_layer = 0
	area.collision_mask = 2
	area.set_script(load("res://scripts/hub/hub_interactable.gd"))
	area.set("interact_id", "stray:%s" % str(spec["dialogue"]))
	area.set("display_name", str(spec["name"]))
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
	label.outline_size = 8
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	animal.add_child(label)


static func _build_cat(parent: Node3D, tint: Color) -> Dictionary:
	_attach_animal(parent, "fauna/cat", tint, 0.3)
	return {"tail": parent.get_node("Tail"), "body": parent.get_node("Body")}


## The animal model in its coat: `fur` is the tint and `dark` a shade under it.
static func _attach_animal(parent: Node3D, id: String, tint: Color, darken: float) -> void:
	PropLibrary.attach_themed(
		parent, id, PixelDioramaStyle.PaletteTheme.HUB,
		{"materials": {"fur": PixelDioramaStyle.make_material(tint), "dark": PixelDioramaStyle.make_material(tint.darkened(darken))}}
	)


static func _build_dog(parent: Node3D, tint: Color) -> Dictionary:
	_attach_animal(parent, "fauna/dog", tint, 0.28)
	return {"tail": parent.get_node("Tail"), "body": parent.get_node("Body")}


