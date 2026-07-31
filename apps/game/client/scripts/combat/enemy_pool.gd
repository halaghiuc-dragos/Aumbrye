extends RefCounted
class_name EnemyPool

## M6 enemy pooling — reuse defeated enemy scenes (PERF-6.1).

static var _pools: Dictionary = {}


static func acquire(enemy_id: String) -> Node:
	var scene: PackedScene = EnemyCatalog.get_scene(enemy_id)
	if scene == null:
		return null
	if not _pools.has(enemy_id):
		_pools[enemy_id] = []
	var pool: Array = _pools[enemy_id]
	if pool.is_empty():
		return scene.instantiate()
	var node: Node = pool.pop_back()
	if node.has_method("reset_for_pool"):
		node.reset_for_pool()
	return node


static func release(enemy_id: String, node: Node) -> void:
	if node == null:
		return
	if not _pools.has(enemy_id):
		_pools[enemy_id] = []
	node.get_parent().remove_child(node)
	_pools[enemy_id].append(node)


static func clear_all() -> void:
	for key in _pools:
		for node in _pools[key]:
			if is_instance_valid(node):
				node.queue_free()
	_pools.clear()
