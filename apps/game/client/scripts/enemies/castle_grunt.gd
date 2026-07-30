extends "res://scripts/enemies/castle_enemy_base.gd"

## Melee castle grunt — patrol/chase/attack (ENEMY-2.1).

const DATA_RELATIVE := "content/enemies/castle_grunt.json"


func get_data_path() -> String:
	return DATA_RELATIVE
