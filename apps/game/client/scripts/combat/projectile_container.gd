extends RefCounted
class_name ProjectileContainer

## `PH-04`: arrows used to be parented to `tree.current_scene` -- correct only because the run root
## happens to currently occupy that slot, not because anything says it must. A named container
## under the actual run root is explicit about where a spawned projectile lives and is torn down
## with everything else when that run scene unloads.

const CONTAINER_NAME := "Projectiles"


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


static func _find_run_root(from: Node) -> Node:
	var tree := from.get_tree()
	if tree == null:
		return null
	for group in ["castle_run", "waves_run"]:
		var found := tree.get_first_node_in_group(group)
		if found:
			return found
	return null
