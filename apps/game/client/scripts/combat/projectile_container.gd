extends RefCounted
class_name ProjectileContainer

## `PH-04`: arrows used to be parented to `tree.current_scene` -- correct only because the run root
## happens to currently occupy that slot, not because anything says it must. A named container
## under the actual run root is explicit about where a spawned projectile lives and is torn down
## with everything else when that run scene unloads.

const CONTAINER_NAME := "Projectiles"
const POOL_NAME := "ProjectilePool"

static var total_created := 0
static var total_reused := 0


static func get_or_create(from: Node) -> Node3D:
	var run_root := _find_run_root(from)
	if run_root == null:
		var tree := from.get_tree()
		run_root = tree.current_scene if tree else null
	if run_root == null:
		return null
	var existing := run_root.get_node_or_null(CONTAINER_NAME)
	if existing is Node3D:
		return existing
	var container := Node3D.new()
	container.name = CONTAINER_NAME
	run_root.add_child(container)
	return container


## Reuses an inactive projectile of the same authored scene where possible.  The pool remains
## under the run root so pooled nodes are released with the run and never retain a prior scene.
static func acquire(from: Node, scene: PackedScene) -> Node3D:
	var container := get_or_create(from)
	if container == null or scene == null:
		return null
	var pool := _get_or_create_pool(container)
	var scene_key := scene.resource_path
	for child in pool.get_children():
		if child is Node3D and str(child.get_meta("projectile_pool_scene", "")) == scene_key:
			pool.remove_child(child)
			container.add_child(child)
			child.show()
			total_reused += 1
			return child as Node3D
	var projectile := scene.instantiate() as Node3D
	if projectile == null:
		return null
	projectile.set_meta("projectile_pool_scene", scene_key)
	container.add_child(projectile)
	total_created += 1
	return projectile


static func reset_metrics() -> void:
	total_created = 0
	total_reused = 0


static func recycle(projectile: Node3D) -> void:
	if projectile == null or not is_instance_valid(projectile):
		return
	var container := projectile.get_parent() as Node3D
	if container == null or container.name != CONTAINER_NAME:
		projectile.queue_free()
		return
	var pool := _get_or_create_pool(container)
	container.remove_child(projectile)
	pool.add_child(projectile)
	projectile.hide()


static func _get_or_create_pool(container: Node3D) -> Node3D:
	var existing := container.get_node_or_null(POOL_NAME) as Node3D
	if existing:
		return existing
	var pool := Node3D.new()
	pool.name = POOL_NAME
	pool.process_mode = Node.PROCESS_MODE_DISABLED
	container.add_child(pool)
	return pool


static func _find_run_root(from: Node) -> Node:
	var tree := from.get_tree()
	if tree == null:
		return null
	for group in ["castle_run", "waves_run"]:
		var found := tree.get_first_node_in_group(group)
		if found:
			return found
	return null
