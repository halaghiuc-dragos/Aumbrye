class_name GentleStart
extends RefCounted

## The first few runs are gentler: ordinary enemies wind up a little slower and only one of them
## attacks at a time, so a new player can learn each telegraph before they have to read several.
## It ends on its own once enough runs are on record; bosses are never softened.

const RUNS := 3
const WINDUP_SCALE := 1.25


static func active() -> bool:
	return LocalSave != null and RunHistoryService.run_count() < RUNS


static func windup_scale(is_boss: bool) -> float:
	return WINDUP_SCALE if not is_boss and active() else 1.0


static func max_attackers(is_boss: bool) -> int:
	return 1 if not is_boss and active() else AttackTokenService.DEFAULT_MAX_TOKENS
