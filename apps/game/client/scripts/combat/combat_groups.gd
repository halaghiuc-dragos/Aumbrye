class_name CombatGroups
extends RefCounted

## C-57: single source of truth for the scene groups combat code scans.
##
## `weapon_controller._find_soft_lock_target()` scanned `lockable` while
## `_resolve_backstab_target()` and `CombatEvents._spread_status()` scanned `enemy`, for what is
## the same question — "which hostiles are near me". Every spawn path adds both groups together
## (`castle_enemy_base`, `training_grunt`, `dungeon_builder._ensure_enemy_groups`), so the two are
## synonyms today and nothing is broken; the risk is an entity that joins one and not the other
## becoming soft-lockable but not backstabbable, silently. Naming them here is the same move
## `combat_layers.gd` makes for collision masks, for the same reason.

## Anything the player may target or strike. Enemies join this on spawn.
const HOSTILE := &"enemy"

## Anything the lock-on camera may acquire. Kept distinct from HOSTILE because a future
## destructible or NPC could reasonably be one without being the other.
const LOCKABLE := &"lockable"


static func hostiles(tree: SceneTree) -> Array[Node]:
	return tree.get_nodes_in_group(HOSTILE)


static func lockables(tree: SceneTree) -> Array[Node]:
	return tree.get_nodes_in_group(LOCKABLE)
