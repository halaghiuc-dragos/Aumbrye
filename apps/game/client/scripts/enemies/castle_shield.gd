extends "res://scripts/enemies/castle_enemy_base.gd"

## Shield-bearer — frontal block, weak to rear/parry (ENEMY-2.3).

const DATA_RELATIVE := "content/enemies/castle_shield.json"


func get_data_path() -> String:
	return DATA_RELATIVE
