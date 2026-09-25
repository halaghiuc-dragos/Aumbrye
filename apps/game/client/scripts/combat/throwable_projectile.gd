extends Projectile
class_name ThrowableProjectile

## `RG-04`: a quick-slot throwable is a `Projectile` (same launch arc, same hitbox) that explodes
## into a small AoE instead of just landing a single hit -- configured right after `instantiate()`,
## before `launch()`, so `_explode()` has everything it needs by the time either impact hook fires.

var _status_id := ""
var _status_stacks := 1
var _status_duration := 6.0
var _impact_radius := 4.0
var _explode_damage := 0.0
var _explode_damage_type := DamageInfo.TYPE_PHYSICAL
var _lure := false
var _exploded := false
var _projectile_archetype := "lobbed_item"

static var _throwable_visual_variants: Dictionary = {}


func configure(
	status_id: String,
	status_stacks: int,
	status_duration: float,
	impact_radius: float,
	explode_damage: float,
	explode_damage_type: String,
	lure: bool,
	authored_archetype: String = "lobbed_item"
) -> void:
	_status_id = status_id
	_status_stacks = maxi(1, status_stacks)
	_status_duration = status_duration
	_impact_radius = maxf(0.5, impact_radius)
	_explode_damage = explode_damage
	_explode_damage_type = explode_damage_type
	_lure = lure
	_projectile_archetype = authored_archetype
	self.projectile_archetype = "lobbed_item"
	_exploded = false


func _build_visual(_dmg_type: String) -> void:
	if _visual == null:
		return
	var mesh := _visual.get_node_or_null("ThrowableVisual") as MeshInstance3D
	if mesh == null:
		mesh = MeshInstance3D.new()
		mesh.name = "ThrowableVisual"
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_visual.add_child(mesh)
	var variant := _throwable_visual_variant(_projectile_archetype)
	mesh.mesh = variant["mesh"]
	mesh.material_override = variant["material"]
	mesh.show()


static func _throwable_visual_variant(archetype: String) -> Dictionary:
	if _throwable_visual_variants.has(archetype):
		return _throwable_visual_variants[archetype]
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var geometry: Mesh
	if archetype == "lure":
		var ring := TorusMesh.new()
		ring.inner_radius = 0.15
		ring.outer_radius = 0.3
		geometry = ring
		material.albedo_color = Color(0.82, 0.74, 0.45)
		material.emission_enabled = true
		material.emission = Color(0.38, 0.28, 0.08)
	else:
		var sphere := SphereMesh.new()
		sphere.radius = 0.26
		sphere.height = 0.52
		geometry = sphere
		material.albedo_color = Color(0.32, 0.16, 0.08)
		material.emission_enabled = true
		material.emission = Color(0.5, 0.12, 0.03)
	var variant := {"mesh": geometry, "material": material}
	_throwable_visual_variants[archetype] = variant
	return variant


func _on_world_impact(contact: Dictionary = {}) -> void:
	var impact_position: Variant = contact.get("position")
	if impact_position is Vector3:
		global_position = impact_position
	_explode()
	_finish_lifecycle()


func _on_hit_landed(target: Node) -> void:
	_explode()
	super._on_hit_landed(target)


func _on_lifetime_expired() -> void:
	# The authored four-second lifetime is also the fuse if a lobbed item never hits terrain.
	_explode()
	_finish_lifecycle()


func _finish_lifecycle() -> void:
	_status_id = ""
	_status_stacks = 1
	_status_duration = 6.0
	_impact_radius = 4.0
	_explode_damage = 0.0
	_explode_damage_type = DamageInfo.TYPE_PHYSICAL
	_lure = false
	_exploded = false
	_projectile_archetype = "lobbed_item"
	projectile_archetype = "arrow"
	super._finish_lifecycle()


func _explode() -> void:
	if _exploded:
		return
	_exploded = true
	var origin := global_position
	var tree := get_tree()
	if tree == null:
		return
	if _lure:
		_draw_aggro(tree, origin)
	var radius_sq := _impact_radius * _impact_radius
	var hit_anything := false
	for node in tree.get_nodes_in_group("enemy"):
		var enemy := node as Node3D
		if enemy == null or not is_instance_valid(enemy):
			continue
		if enemy.has_method("is_dead") and enemy.call("is_dead"):
			continue
		if enemy.global_position.distance_squared_to(origin) > radius_sq:
			continue
		if not _has_line_of_effect(origin, enemy.global_position):
			continue
		hit_anything = true
		var status_can_apply := _explode_damage <= 0.0
		if _explode_damage > 0.0:
			var hurtbox := enemy.get_node_or_null("Hurtbox")
			if hurtbox and hurtbox.has_method("receive_hit"):
				var offset := enemy.global_position - origin
				var dir := (
					offset.normalized() if offset.length_squared() > 0.0001 else Vector3.FORWARD
				)
				var info := DamageInfo.create(
					_explode_damage, 0.0, _owner_node, _explode_damage_type, dir
				)
				var resolution = hurtbox.call("receive_hit", info)
				status_can_apply = (
					resolution is DamageResolution and (resolution as DamageResolution).outgoing > 0.0
				)
		if status_can_apply and _status_id != "":
			var controller := enemy.get_node_or_null("StatusController") as StatusController
			if controller:
				controller.apply_status(_status_id, _status_stacks, _status_duration)
	if VfxService:
		if hit_anything or _lure:
			VfxService.play_rune_flare(origin)
		else:
			VfxService.play_hit_spark(origin)


func _has_line_of_effect(origin: Vector3, target: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	if space == null:
		return true
	var query := PhysicsRayQueryParameters3D.create(origin, target)
	query.collision_mask = CombatLayers.WORLD_OCCLUDERS
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return space.intersect_ray(query).is_empty()


## `RG-04`: the lure item's identity trait -- redirects nearby patrolling enemies to investigate
## the impact point, the same public hook `CastleEnemyBase._broadcast_alert()` already uses for
## one enemy noticing another's alert.
func _draw_aggro(tree: SceneTree, origin: Vector3) -> void:
	for node in tree.get_nodes_in_group("enemy"):
		if node == null or not is_instance_valid(node) or not (node is Node3D):
			continue
		if node.has_method("is_dead") and node.call("is_dead"):
			continue
		if (node as Node3D).global_position.distance_squared_to(origin) > _impact_radius * _impact_radius:
			continue
		if node.has_method("notice_ally_alert"):
			node.call("notice_ally_alert", origin)
