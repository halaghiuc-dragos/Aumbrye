extends SceneTree

## Headless exporter — no autoloads required.
##   godot --path . --headless --script res://scripts/tools/export_diorama_anim_libraries.gd

const AnimLibrary := preload("res://scripts/art/characters/diorama_anim_library.gd")

const OUTPUT_DIR := "res://assets/animations/diorama/"

const REST_POSES := {
	"player": {
		"Root": {"path": "Root", "position": Vector3.ZERO, "rotation": Vector3.ZERO},
		"LegL": {"path": "Root/LegL", "position": Vector3(-0.13, 0.46, 0.0), "rotation": Vector3.ZERO},
		"LegR": {"path": "Root/LegR", "position": Vector3(0.13, 0.46, 0.0), "rotation": Vector3.ZERO},
		"Torso": {"path": "Root/Torso", "position": Vector3(0.0, 0.46, 0.0), "rotation": Vector3.ZERO},
		"Head": {"path": "Root/Torso/Head", "position": Vector3(0.0, 0.62, 0.0), "rotation": Vector3.ZERO},
		"ArmL": {"path": "Root/Torso/ArmL", "position": Vector3(-0.3, 0.5456, 0.0), "rotation": Vector3.ZERO},
		"ArmR": {"path": "Root/Torso/ArmR", "position": Vector3(0.3, 0.5456, 0.0), "rotation": Vector3.ZERO},
	},
	"melee": {
		"Root": {"path": "Root", "position": Vector3.ZERO, "rotation": Vector3.ZERO},
		"LegL": {"path": "Root/LegL", "position": Vector3(-0.14, 0.48, 0.0), "rotation": Vector3.ZERO},
		"LegR": {"path": "Root/LegR", "position": Vector3(0.14, 0.48, 0.0), "rotation": Vector3.ZERO},
		"Torso": {"path": "Root/Torso", "position": Vector3(0.0, 0.48, 0.0), "rotation": Vector3.ZERO},
		"Head": {"path": "Root/Torso/Head", "position": Vector3(0.0, 0.64, 0.0), "rotation": Vector3.ZERO},
		"ArmL": {"path": "Root/Torso/ArmL", "position": Vector3(-0.33, 0.5632, 0.0), "rotation": Vector3.ZERO},
		"ArmR": {"path": "Root/Torso/ArmR", "position": Vector3(0.33, 0.5632, 0.0), "rotation": Vector3.ZERO},
	},
	"hound": {
		"Root": {"path": "Root", "position": Vector3.ZERO, "rotation": Vector3.ZERO},
		"Torso": {"path": "Root/Torso", "position": Vector3(0.0, 0.3, 0.0), "rotation": Vector3.ZERO},
		"Head": {"path": "Root/Torso/Head", "position": Vector3(0.0, 0.2, 0.36), "rotation": Vector3.ZERO},
		"Tail": {"path": "Root/Torso/Tail", "position": Vector3(0.0, 0.24, -0.38), "rotation": Vector3.ZERO},
		"LegL": {"path": "Root/LegL", "position": Vector3(-0.16, 0.3, 0.26), "rotation": Vector3.ZERO},
		"LegR": {"path": "Root/LegR", "position": Vector3(0.16, 0.3, 0.26), "rotation": Vector3.ZERO},
		"LegBL": {"path": "Root/LegBL", "position": Vector3(-0.16, 0.3, -0.26), "rotation": Vector3.ZERO},
		"LegBR": {"path": "Root/LegBR", "position": Vector3(0.16, 0.3, -0.26), "rotation": Vector3.ZERO},
	},
}


func _initialize() -> void:
	var global_dir := ProjectSettings.globalize_path("res://assets/animations/diorama")
	if not DirAccess.dir_exists_absolute(global_dir):
		DirAccess.make_dir_recursive_absolute(global_dir)

	for profile_key in REST_POSES:
		var rest_pose: Dictionary = REST_POSES[profile_key]
		var library := AnimLibrary.build_library(rest_pose, "", profile_key, true)
		var out_path := "%s%s_locomotion.res" % [OUTPUT_DIR, profile_key]
		var err := ResourceSaver.save(library, out_path)
		if err != OK:
			push_error("Failed to save %s: %s" % [out_path, error_string(err)])
		else:
			print("Saved %s (%d clips)" % [out_path, library.get_animation_list().size()])

	print("Diorama anim export complete.")
	quit()
