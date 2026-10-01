class_name LockOnRegistry
extends RefCounted

## Everything the player can lock onto. Enemies add themselves on entering the tree and remove
## themselves on leaving it, so the lock never has to scan the tree or listen to every node added.

static var _targets: Array[Node3D] = []


static func register(target: Node3D) -> void:
	if not _targets.has(target):
		_targets.append(target)


static func unregister(target: Node3D) -> void:
	_targets.erase(target)


static func targets() -> Array[Node3D]:
	var live: Array[Node3D] = []
	for target in _targets:
		if is_instance_valid(target) and target.is_inside_tree():
			live.append(target)
	return live
