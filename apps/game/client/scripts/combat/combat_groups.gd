class_name CombatGroups
extends RefCounted


const HOSTILE := &"enemy"

const LOCKABLE := &"lockable"


static func hostiles(tree: SceneTree) -> Array[Node]:
	return tree.get_nodes_in_group(HOSTILE)


static func lockables(tree: SceneTree) -> Array[Node]:
	return tree.get_nodes_in_group(LOCKABLE)


## The CharacterBody3D an Area3D hangs off, walking up the tree. Hitboxes, hurtboxes and shields all
## need their wielder and all sit at different depths under it.
static func owning_body(node: Node) -> Node3D:
	var current := node
	while current:
		if current is CharacterBody3D:
			return current as Node3D
		current = current.get_parent()
	return null
