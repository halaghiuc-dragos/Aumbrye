class_name DioramaAnimLibrary
extends RefCounted

## Authored keyframe tables for voxel characters, compiled into AnimationLibrary
## resources at runtime.
##
## Clips are stored as offsets from each part's rest pose, not absolute transforms,
## because the rigs are built procedurally and every profile has different limb
## positions. Compiling per rig lets one clip table drive the player, a hound, and
## a brute without re-authoring anything.
##
## Key format: [time, x, y, z]. "rot" is euler radians on the part's pivot, "pos"
## is a metre offset. Attack clips use normalised time (0..1) and are stretched to
## the weapon's real startup/active/recovery timings when compiled.

const HITBOX_ON := &"anim_hitbox_on"
const HITBOX_OFF := &"anim_hitbox_off"
const SWING_VFX := &"anim_swing_vfx"
const FOOTSTEP := &"anim_footstep"

## Locomotion, reaction, and guard clips. Times are in seconds.
const CLIPS := {
	&"idle": {
		"length": 2.6,
		"loop": true,
		"tracks": {
			"Torso": {
				"pos": [[0.0, 0.0, 0.0, 0.0], [1.3, 0.0, 0.018, 0.0], [2.6, 0.0, 0.0, 0.0]],
				"rot": [[0.0, 0.0, 0.0, 0.0], [1.3, 0.02, 0.0, 0.0], [2.6, 0.0, 0.0, 0.0]],
			},
			"Head": {
				"rot": [[0.0, 0.0, 0.0, 0.0], [0.9, 0.0, 0.09, 0.0], [1.8, 0.0, -0.06, 0.0], [2.6, 0.0, 0.0, 0.0]],
			},
			"ArmL": {"rot": [[0.0, 0.0, 0.0, 0.05], [1.3, 0.05, 0.0, 0.08], [2.6, 0.0, 0.0, 0.05]]},
			"ArmR": {"rot": [[0.0, 0.0, 0.0, -0.05], [1.3, -0.04, 0.0, -0.08], [2.6, 0.0, 0.0, -0.05]]},
		},
	},
	&"walk": {
		"length": 0.8,
		"loop": true,
		"tracks": {
			"Root": {
				"pos": [[0.0, 0.0, 0.0, 0.0], [0.2, 0.0, 0.035, 0.0], [0.4, 0.0, 0.0, 0.0], [0.6, 0.0, 0.035, 0.0], [0.8, 0.0, 0.0, 0.0]],
			},
			"Torso": {
				"rot": [[0.0, 0.06, 0.1, 0.0], [0.4, 0.06, -0.1, 0.0], [0.8, 0.06, 0.1, 0.0]],
			},
			"Head": {"rot": [[0.0, 0.0, -0.07, 0.0], [0.4, 0.0, 0.07, 0.0], [0.8, 0.0, -0.07, 0.0]]},
			"LegL": {"rot": [[0.0, 0.55, 0.0, 0.0], [0.4, -0.45, 0.0, 0.0], [0.8, 0.55, 0.0, 0.0]]},
			"LegR": {"rot": [[0.0, -0.45, 0.0, 0.0], [0.4, 0.55, 0.0, 0.0], [0.8, -0.45, 0.0, 0.0]]},
			"ArmL": {"rot": [[0.0, -0.4, 0.0, 0.06], [0.4, 0.38, 0.0, 0.06], [0.8, -0.4, 0.0, 0.06]]},
			"ArmR": {"rot": [[0.0, 0.38, 0.0, -0.06], [0.4, -0.4, 0.0, -0.06], [0.8, 0.38, 0.0, -0.06]]},
			# Quadruped-only pivots; skipped on rigs that do not have them.
			"LegBL": {"rot": [[0.0, -0.45, 0.0, 0.0], [0.4, 0.55, 0.0, 0.0], [0.8, -0.45, 0.0, 0.0]]},
			"LegBR": {"rot": [[0.0, 0.55, 0.0, 0.0], [0.4, -0.45, 0.0, 0.0], [0.8, 0.55, 0.0, 0.0]]},
			"Tail": {"rot": [[0.0, 0.0, 0.22, 0.0], [0.4, 0.0, -0.22, 0.0], [0.8, 0.0, 0.22, 0.0]]},
		},
		"methods": [[0.18, FOOTSTEP], [0.58, FOOTSTEP]],
	},
	&"run": {
		"length": 0.56,
		"loop": true,
		"tracks": {
			"Root": {
				"pos": [[0.0, 0.0, 0.0, 0.0], [0.14, 0.0, 0.06, 0.0], [0.28, 0.0, 0.0, 0.0], [0.42, 0.0, 0.06, 0.0], [0.56, 0.0, 0.0, 0.0]],
			},
			"Torso": {
				"rot": [[0.0, 0.2, 0.16, 0.0], [0.28, 0.2, -0.16, 0.0], [0.56, 0.2, 0.16, 0.0]],
			},
			"Head": {"rot": [[0.0, -0.12, -0.1, 0.0], [0.28, -0.12, 0.1, 0.0], [0.56, -0.12, -0.1, 0.0]]},
			"LegL": {"rot": [[0.0, 0.95, 0.0, 0.0], [0.28, -0.7, 0.0, 0.0], [0.56, 0.95, 0.0, 0.0]]},
			"LegR": {"rot": [[0.0, -0.7, 0.0, 0.0], [0.28, 0.95, 0.0, 0.0], [0.56, -0.7, 0.0, 0.0]]},
			"ArmL": {"rot": [[0.0, -0.85, 0.0, 0.12], [0.28, 0.7, 0.0, 0.12], [0.56, -0.85, 0.0, 0.12]]},
			"ArmR": {"rot": [[0.0, 0.7, 0.0, -0.12], [0.28, -0.85, 0.0, -0.12], [0.56, 0.7, 0.0, -0.12]]},
			"LegBL": {"rot": [[0.0, -0.7, 0.0, 0.0], [0.28, 0.95, 0.0, 0.0], [0.56, -0.7, 0.0, 0.0]]},
			"LegBR": {"rot": [[0.0, 0.95, 0.0, 0.0], [0.28, -0.7, 0.0, 0.0], [0.56, 0.95, 0.0, 0.0]]},
			"Tail": {"rot": [[0.0, 0.0, 0.34, 0.0], [0.28, 0.0, -0.34, 0.0], [0.56, 0.0, 0.34, 0.0]]},
		},
		"methods": [[0.1, FOOTSTEP], [0.38, FOOTSTEP]],
	},
	&"air": {
		"length": 0.9,
		"loop": true,
		"tracks": {
			"Torso": {"rot": [[0.0, -0.14, 0.0, 0.0], [0.45, -0.2, 0.0, 0.0], [0.9, -0.14, 0.0, 0.0]]},
			"Head": {"rot": [[0.0, 0.1, 0.0, 0.0], [0.9, 0.1, 0.0, 0.0]]},
			"LegL": {"rot": [[0.0, 0.55, 0.0, 0.1], [0.45, 0.7, 0.0, 0.1], [0.9, 0.55, 0.0, 0.1]]},
			"LegR": {"rot": [[0.0, -0.25, 0.0, -0.1], [0.45, -0.35, 0.0, -0.1], [0.9, -0.25, 0.0, -0.1]]},
			"ArmL": {"rot": [[0.0, -0.5, 0.0, 0.5], [0.45, -0.62, 0.0, 0.55], [0.9, -0.5, 0.0, 0.5]]},
			"ArmR": {"rot": [[0.0, -0.5, 0.0, -0.5], [0.45, -0.62, 0.0, -0.55], [0.9, -0.5, 0.0, -0.5]]},
		},
	},
	&"land": {
		"length": 0.26,
		"tracks": {
			"Root": {"pos": [[0.0, 0.0, 0.0, 0.0], [0.07, 0.0, -0.16, 0.0], [0.26, 0.0, 0.0, 0.0]]},
			"Torso": {"rot": [[0.0, 0.0, 0.0, 0.0], [0.07, 0.32, 0.0, 0.0], [0.26, 0.0, 0.0, 0.0]]},
			"LegL": {"rot": [[0.0, 0.2, 0.0, 0.16], [0.07, 0.5, 0.0, 0.22], [0.26, 0.0, 0.0, 0.0]]},
			"LegR": {"rot": [[0.0, 0.2, 0.0, -0.16], [0.07, 0.5, 0.0, -0.22], [0.26, 0.0, 0.0, 0.0]]},
			"ArmL": {"rot": [[0.0, -0.2, 0.0, 0.3], [0.07, -0.5, 0.0, 0.45], [0.26, 0.0, 0.0, 0.05]]},
			"ArmR": {"rot": [[0.0, -0.2, 0.0, -0.3], [0.07, -0.5, 0.0, -0.45], [0.26, 0.0, 0.0, -0.05]]},
		},
	},
	&"dash_f": {
		"length": 0.45,
		"tracks": {
			"Root": {"pos": [[0.0, 0.0, 0.0, 0.0], [0.12, 0.0, 0.1, 0.0], [0.3, 0.0, 0.02, 0.0], [0.45, 0.0, 0.0, 0.0]]},
			"Torso": {"rot": [[0.0, 0.0, 0.0, 0.0], [0.12, 0.72, 0.0, 0.0], [0.3, 0.42, 0.0, 0.0], [0.45, 0.0, 0.0, 0.0]]},
			"Head": {"rot": [[0.0, 0.0, 0.0, 0.0], [0.12, -0.35, 0.0, 0.0], [0.45, 0.0, 0.0, 0.0]]},
			"LegL": {"rot": [[0.0, 0.0, 0.0, 0.0], [0.12, 1.0, 0.0, 0.18], [0.3, -0.3, 0.0, 0.1], [0.45, 0.0, 0.0, 0.0]]},
			"LegR": {"rot": [[0.0, 0.0, 0.0, 0.0], [0.12, -0.55, 0.0, -0.18], [0.3, 0.65, 0.0, -0.1], [0.45, 0.0, 0.0, 0.0]]},
			"ArmL": {"rot": [[0.0, 0.0, 0.0, 0.05], [0.12, -0.7, 0.0, 0.3], [0.45, 0.0, 0.0, 0.05]]},
			"ArmR": {"rot": [[0.0, 0.0, 0.0, -0.05], [0.12, -0.7, 0.0, -0.3], [0.45, 0.0, 0.0, -0.05]]},
		},
	},
	&"dash_b": {
		"length": 0.45,
		"tracks": {
			"Root": {"pos": [[0.0, 0.0, 0.0, 0.0], [0.12, 0.0, 0.12, 0.0], [0.45, 0.0, 0.0, 0.0]]},
			"Torso": {"rot": [[0.0, 0.0, 0.0, 0.0], [0.12, -0.48, 0.0, 0.0], [0.45, 0.0, 0.0, 0.0]]},
			"Head": {"rot": [[0.0, 0.0, 0.0, 0.0], [0.12, 0.28, 0.0, 0.0], [0.45, 0.0, 0.0, 0.0]]},
			"LegL": {"rot": [[0.0, 0.0, 0.0, 0.0], [0.12, -0.6, 0.0, 0.14], [0.45, 0.0, 0.0, 0.0]]},
			"LegR": {"rot": [[0.0, 0.0, 0.0, 0.0], [0.12, -0.35, 0.0, -0.14], [0.45, 0.0, 0.0, 0.0]]},
			"ArmL": {"rot": [[0.0, 0.0, 0.0, 0.05], [0.12, 0.5, 0.0, 0.35], [0.45, 0.0, 0.0, 0.05]]},
			"ArmR": {"rot": [[0.0, 0.0, 0.0, -0.05], [0.12, 0.5, 0.0, -0.35], [0.45, 0.0, 0.0, -0.05]]},
		},
	},
	&"dash_l": {
		"length": 0.45,
		"tracks": {
			"Root": {"pos": [[0.0, 0.0, 0.0, 0.0], [0.12, 0.0, 0.09, 0.0], [0.45, 0.0, 0.0, 0.0]]},
			"Torso": {"rot": [[0.0, 0.0, 0.0, 0.0], [0.12, 0.18, -0.4, 0.55], [0.45, 0.0, 0.0, 0.0]]},
			"Head": {"rot": [[0.0, 0.0, 0.0, 0.0], [0.12, 0.0, 0.35, -0.2], [0.45, 0.0, 0.0, 0.0]]},
			"LegL": {"rot": [[0.0, 0.0, 0.0, 0.0], [0.12, 0.3, 0.0, 0.5], [0.45, 0.0, 0.0, 0.0]]},
			"LegR": {"rot": [[0.0, 0.0, 0.0, 0.0], [0.12, 0.45, 0.0, 0.2], [0.45, 0.0, 0.0, 0.0]]},
			"ArmL": {"rot": [[0.0, 0.0, 0.0, 0.05], [0.12, -0.3, 0.0, 0.7], [0.45, 0.0, 0.0, 0.05]]},
			"ArmR": {"rot": [[0.0, 0.0, 0.0, -0.05], [0.12, -0.45, 0.0, 0.25], [0.45, 0.0, 0.0, -0.05]]},
		},
	},
	&"dash_r": {
		"length": 0.45,
		"tracks": {
			"Root": {"pos": [[0.0, 0.0, 0.0, 0.0], [0.12, 0.0, 0.09, 0.0], [0.45, 0.0, 0.0, 0.0]]},
			"Torso": {"rot": [[0.0, 0.0, 0.0, 0.0], [0.12, 0.18, 0.4, -0.55], [0.45, 0.0, 0.0, 0.0]]},
			"Head": {"rot": [[0.0, 0.0, 0.0, 0.0], [0.12, 0.0, -0.35, 0.2], [0.45, 0.0, 0.0, 0.0]]},
			"LegL": {"rot": [[0.0, 0.0, 0.0, 0.0], [0.12, 0.45, 0.0, -0.2], [0.45, 0.0, 0.0, 0.0]]},
			"LegR": {"rot": [[0.0, 0.0, 0.0, 0.0], [0.12, 0.3, 0.0, -0.5], [0.45, 0.0, 0.0, 0.0]]},
			"ArmL": {"rot": [[0.0, 0.0, 0.0, 0.05], [0.12, -0.45, 0.0, -0.25], [0.45, 0.0, 0.0, 0.05]]},
			"ArmR": {"rot": [[0.0, 0.0, 0.0, -0.05], [0.12, -0.3, 0.0, -0.7], [0.45, 0.0, 0.0, -0.05]]},
		},
	},
	&"block_start": {
		"length": 0.14,
		"tracks": {
			"Root": {"pos": [[0.0, 0.0, 0.0, 0.0], [0.14, 0.0, -0.05, 0.0]]},
			"Torso": {"rot": [[0.0, 0.0, 0.0, 0.0], [0.14, 0.12, 0.28, 0.0]]},
			"Head": {"rot": [[0.0, 0.0, 0.0, 0.0], [0.14, 0.08, -0.18, 0.0]]},
			"ArmL": {"rot": [[0.0, 0.0, 0.0, 0.05], [0.14, -1.15, 0.35, 0.5]]},
			"ArmR": {"rot": [[0.0, 0.0, 0.0, -0.05], [0.14, -0.62, -0.28, -0.3]]},
			"LegL": {"rot": [[0.0, 0.0, 0.0, 0.0], [0.14, 0.16, 0.0, 0.08]]},
			"LegR": {"rot": [[0.0, 0.0, 0.0, 0.0], [0.14, -0.16, 0.0, -0.08]]},
		},
	},
	&"block_hold": {
		"length": 1.8,
		"loop": true,
		"tracks": {
			"Root": {"pos": [[0.0, 0.0, -0.05, 0.0], [0.9, 0.0, -0.035, 0.0], [1.8, 0.0, -0.05, 0.0]]},
			"Torso": {"rot": [[0.0, 0.12, 0.28, 0.0], [0.9, 0.14, 0.3, 0.0], [1.8, 0.12, 0.28, 0.0]]},
			"Head": {"rot": [[0.0, 0.08, -0.18, 0.0], [1.8, 0.08, -0.18, 0.0]]},
			"ArmL": {"rot": [[0.0, -1.15, 0.35, 0.5], [0.9, -1.2, 0.35, 0.52], [1.8, -1.15, 0.35, 0.5]]},
			"ArmR": {"rot": [[0.0, -0.62, -0.28, -0.3], [1.8, -0.62, -0.28, -0.3]]},
			"LegL": {"rot": [[0.0, 0.16, 0.0, 0.08], [1.8, 0.16, 0.0, 0.08]]},
			"LegR": {"rot": [[0.0, -0.16, 0.0, -0.08], [1.8, -0.16, 0.0, -0.08]]},
		},
	},
	&"block_hit": {
		"length": 0.24,
		"tracks": {
			"Root": {"pos": [[0.0, 0.0, -0.05, 0.0], [0.06, 0.0, -0.09, -0.14], [0.24, 0.0, -0.05, 0.0]]},
			"Torso": {"rot": [[0.0, 0.12, 0.28, 0.0], [0.06, 0.3, 0.46, 0.0], [0.24, 0.12, 0.28, 0.0]]},
			"Head": {"rot": [[0.0, 0.08, -0.18, 0.0], [0.06, 0.24, -0.3, 0.0], [0.24, 0.08, -0.18, 0.0]]},
			"ArmL": {"rot": [[0.0, -1.15, 0.35, 0.5], [0.06, -0.95, 0.5, 0.66], [0.24, -1.15, 0.35, 0.5]]},
			"ArmR": {"rot": [[0.0, -0.62, -0.28, -0.3], [0.24, -0.62, -0.28, -0.3]]},
		},
	},
	&"parry_success": {
		"length": 0.36,
		"tracks": {
			"Root": {"pos": [[0.0, 0.0, 0.0, 0.0], [0.08, 0.0, 0.05, 0.0], [0.36, 0.0, 0.0, 0.0]]},
			"Torso": {"rot": [[0.0, 0.1, 0.24, 0.0], [0.08, -0.1, -0.55, 0.0], [0.36, 0.0, 0.0, 0.0]]},
			"Head": {"rot": [[0.0, 0.0, 0.0, 0.0], [0.08, -0.12, 0.3, 0.0], [0.36, 0.0, 0.0, 0.0]]},
			"ArmL": {"rot": [[0.0, -1.1, 0.3, 0.45], [0.08, -1.5, -0.55, 0.9], [0.36, 0.0, 0.0, 0.05]]},
			"ArmR": {"rot": [[0.0, -0.6, -0.25, -0.3], [0.08, -0.35, 0.4, -0.5], [0.36, 0.0, 0.0, -0.05]]},
		},
		"methods": [[0.05, SWING_VFX]],
	},
	&"guard_break": {
		"length": 0.6,
		"tracks": {
			"Root": {"pos": [[0.0, 0.0, 0.0, 0.0], [0.12, 0.0, -0.14, -0.18], [0.45, 0.0, -0.06, -0.06], [0.6, 0.0, 0.0, 0.0]]},
			"Torso": {"rot": [[0.0, 0.0, 0.0, 0.0], [0.12, -0.42, 0.1, 0.0], [0.45, -0.2, 0.05, 0.0], [0.6, 0.0, 0.0, 0.0]]},
			"Head": {"rot": [[0.0, 0.0, 0.0, 0.0], [0.12, -0.5, 0.0, 0.0], [0.6, 0.0, 0.0, 0.0]]},
			"ArmL": {"rot": [[0.0, -1.1, 0.3, 0.45], [0.12, 0.3, 0.6, 1.0], [0.6, 0.0, 0.0, 0.05]]},
			"ArmR": {"rot": [[0.0, -0.6, -0.25, -0.3], [0.12, 0.3, -0.6, -1.0], [0.6, 0.0, 0.0, -0.05]]},
			"LegL": {"rot": [[0.0, 0.0, 0.0, 0.0], [0.12, -0.4, 0.0, 0.2], [0.6, 0.0, 0.0, 0.0]]},
			"LegR": {"rot": [[0.0, 0.0, 0.0, 0.0], [0.12, 0.25, 0.0, -0.2], [0.6, 0.0, 0.0, 0.0]]},
		},
	},
	&"flinch": {
		"length": 0.26,
		"tracks": {
			"Root": {"pos": [[0.0, 0.0, 0.0, 0.0], [0.05, 0.0, 0.02, -0.1], [0.26, 0.0, 0.0, 0.0]]},
			"Torso": {"rot": [[0.0, 0.0, 0.0, 0.0], [0.05, -0.3, 0.14, 0.1], [0.26, 0.0, 0.0, 0.0]]},
			"Head": {"rot": [[0.0, 0.0, 0.0, 0.0], [0.05, -0.36, 0.2, 0.0], [0.26, 0.0, 0.0, 0.0]]},
			"ArmL": {"rot": [[0.0, 0.0, 0.0, 0.05], [0.05, 0.3, 0.0, 0.4], [0.26, 0.0, 0.0, 0.05]]},
			"ArmR": {"rot": [[0.0, 0.0, 0.0, -0.05], [0.05, 0.25, 0.0, -0.35], [0.26, 0.0, 0.0, -0.05]]},
		},
	},
	&"stagger": {
		"length": 0.85,
		"tracks": {
			"Root": {
				"pos": [[0.0, 0.0, 0.0, 0.0], [0.1, 0.06, -0.1, -0.2], [0.35, -0.05, -0.05, -0.1], [0.6, 0.03, -0.02, -0.04], [0.85, 0.0, 0.0, 0.0]],
			},
			"Torso": {
				"rot": [[0.0, 0.0, 0.0, 0.0], [0.1, -0.5, 0.25, 0.18], [0.35, -0.3, -0.15, -0.1], [0.6, -0.15, 0.08, 0.05], [0.85, 0.0, 0.0, 0.0]],
			},
			"Head": {"rot": [[0.0, 0.0, 0.0, 0.0], [0.1, -0.55, 0.3, 0.0], [0.4, -0.25, -0.2, 0.0], [0.85, 0.0, 0.0, 0.0]]},
			"ArmL": {"rot": [[0.0, 0.0, 0.0, 0.05], [0.1, 0.45, 0.0, 0.6], [0.45, 0.2, 0.0, 0.3], [0.85, 0.0, 0.0, 0.05]]},
			"ArmR": {"rot": [[0.0, 0.0, 0.0, -0.05], [0.1, 0.35, 0.0, -0.55], [0.45, 0.15, 0.0, -0.28], [0.85, 0.0, 0.0, -0.05]]},
			"LegL": {"rot": [[0.0, 0.0, 0.0, 0.0], [0.1, -0.35, 0.0, 0.18], [0.5, 0.15, 0.0, 0.06], [0.85, 0.0, 0.0, 0.0]]},
			"LegR": {"rot": [[0.0, 0.0, 0.0, 0.0], [0.1, 0.3, 0.0, -0.18], [0.5, -0.12, 0.0, -0.06], [0.85, 0.0, 0.0, 0.0]]},
		},
	},
	&"death": {
		"length": 1.0,
		"tracks": {
			"Root": {
				"pos": [[0.0, 0.0, 0.0, 0.0], [0.12, 0.0, 0.06, 0.0], [0.5, 0.0, -0.45, -0.2], [0.72, 0.0, -0.62, -0.32], [1.0, 0.0, -0.62, -0.32]],
				"rot": [[0.0, 0.0, 0.0, 0.0], [0.12, -0.2, 0.0, 0.1], [0.5, -0.9, 0.15, 0.35], [0.72, -1.45, 0.2, 0.5], [1.0, -1.45, 0.2, 0.5]],
			},
			"Torso": {"rot": [[0.0, 0.0, 0.0, 0.0], [0.12, -0.35, 0.0, 0.0], [0.5, 0.25, 0.1, 0.1], [1.0, 0.3, 0.12, 0.12]]},
			"Head": {"rot": [[0.0, 0.0, 0.0, 0.0], [0.12, -0.45, 0.0, 0.0], [0.5, 0.4, 0.2, 0.0], [1.0, 0.45, 0.25, 0.0]]},
			"ArmL": {"rot": [[0.0, 0.0, 0.0, 0.05], [0.12, -0.6, 0.0, 0.5], [0.5, 0.5, 0.0, 0.9], [1.0, 0.55, 0.0, 1.0]]},
			"ArmR": {"rot": [[0.0, 0.0, 0.0, -0.05], [0.12, -0.5, 0.0, -0.45], [0.5, 0.45, 0.0, -0.85], [1.0, 0.5, 0.0, -0.95]]},
			"LegL": {"rot": [[0.0, 0.0, 0.0, 0.0], [0.12, 0.2, 0.0, 0.1], [0.5, -0.5, 0.0, 0.3], [1.0, -0.55, 0.0, 0.35]]},
			"LegR": {"rot": [[0.0, 0.0, 0.0, 0.0], [0.12, 0.15, 0.0, -0.1], [0.5, -0.4, 0.0, -0.3], [1.0, -0.45, 0.0, -0.35]]},
		},
	},
}

## Attack clips in normalised time. "startup_end" / "active_end" mark where the
## real weapon phases must land; compile_attack() stretches each segment to match
## the JSON timings so the strike frame and the hitbox always agree.
const ATTACKS := {
	&"attack_light_1": {
		"startup_end": 0.34,
		"active_end": 0.58,
		"tracks": {
			"Root": {"pos": [[0.0, 0.0, 0.0, 0.0], [0.34, 0.0, 0.02, -0.05], [0.46, 0.0, 0.0, 0.12], [1.0, 0.0, 0.0, 0.0]]},
			"Torso": {"rot": [[0.0, 0.0, 0.0, 0.0], [0.34, -0.1, -0.62, 0.0], [0.5, 0.12, 0.68, 0.0], [1.0, 0.0, 0.0, 0.0]]},
			"Head": {"rot": [[0.0, 0.0, 0.0, 0.0], [0.34, 0.0, 0.3, 0.0], [0.5, 0.0, -0.22, 0.0], [1.0, 0.0, 0.0, 0.0]]},
			"ArmR": {"rot": [[0.0, 0.0, 0.0, -0.05], [0.34, -1.5, -0.35, -0.85], [0.5, 0.55, 0.5, 0.5], [0.7, 0.2, 0.2, 0.1], [1.0, 0.0, 0.0, -0.05]]},
			"ArmL": {"rot": [[0.0, 0.0, 0.0, 0.05], [0.34, 0.35, 0.0, 0.45], [0.5, -0.4, 0.0, -0.1], [1.0, 0.0, 0.0, 0.05]]},
			"LegL": {"rot": [[0.0, 0.0, 0.0, 0.0], [0.34, -0.2, 0.0, 0.0], [0.5, 0.3, 0.0, 0.0], [1.0, 0.0, 0.0, 0.0]]},
			"LegR": {"rot": [[0.0, 0.0, 0.0, 0.0], [0.34, 0.25, 0.0, 0.0], [0.5, -0.22, 0.0, 0.0], [1.0, 0.0, 0.0, 0.0]]},
		},
		"methods": [[0.35, SWING_VFX]],
	},
	&"attack_light_2": {
		"startup_end": 0.32,
		"active_end": 0.56,
		"tracks": {
			"Root": {"pos": [[0.0, 0.0, 0.0, 0.0], [0.32, 0.0, 0.03, -0.04], [0.46, 0.0, 0.0, 0.14], [1.0, 0.0, 0.0, 0.0]]},
			"Torso": {"rot": [[0.0, 0.0, 0.0, 0.0], [0.32, -0.08, 0.66, 0.0], [0.48, 0.14, -0.7, 0.0], [1.0, 0.0, 0.0, 0.0]]},
			"Head": {"rot": [[0.0, 0.0, 0.0, 0.0], [0.32, 0.0, -0.32, 0.0], [0.48, 0.0, 0.24, 0.0], [1.0, 0.0, 0.0, 0.0]]},
			"ArmR": {"rot": [[0.0, 0.0, 0.0, -0.05], [0.32, -0.55, 0.75, 0.95], [0.48, -0.5, -0.7, -1.1], [0.7, -0.2, -0.25, -0.4], [1.0, 0.0, 0.0, -0.05]]},
			"ArmL": {"rot": [[0.0, 0.0, 0.0, 0.05], [0.32, -0.3, 0.0, -0.2], [0.48, 0.4, 0.0, 0.6], [1.0, 0.0, 0.0, 0.05]]},
			"LegL": {"rot": [[0.0, 0.0, 0.0, 0.0], [0.32, 0.24, 0.0, 0.0], [0.48, -0.2, 0.0, 0.0], [1.0, 0.0, 0.0, 0.0]]},
			"LegR": {"rot": [[0.0, 0.0, 0.0, 0.0], [0.32, -0.2, 0.0, 0.0], [0.48, 0.28, 0.0, 0.0], [1.0, 0.0, 0.0, 0.0]]},
		},
		"methods": [[0.33, SWING_VFX]],
	},
	&"attack_light_3": {
		"startup_end": 0.4,
		"active_end": 0.62,
		"tracks": {
			"Root": {"pos": [[0.0, 0.0, 0.0, 0.0], [0.4, 0.0, 0.12, -0.08], [0.54, 0.0, -0.06, 0.2], [1.0, 0.0, 0.0, 0.0]]},
			"Torso": {"rot": [[0.0, 0.0, 0.0, 0.0], [0.4, -0.5, -0.2, 0.0], [0.56, 0.5, 0.15, 0.0], [1.0, 0.0, 0.0, 0.0]]},
			"Head": {"rot": [[0.0, 0.0, 0.0, 0.0], [0.4, -0.3, 0.0, 0.0], [0.56, 0.35, 0.0, 0.0], [1.0, 0.0, 0.0, 0.0]]},
			"ArmR": {"rot": [[0.0, 0.0, 0.0, -0.05], [0.4, -2.35, 0.0, -0.3], [0.56, 1.05, 0.0, -0.1], [0.74, 0.4, 0.0, -0.05], [1.0, 0.0, 0.0, -0.05]]},
			"ArmL": {"rot": [[0.0, 0.0, 0.0, 0.05], [0.4, -2.2, 0.0, 0.3], [0.56, 0.95, 0.0, 0.1], [1.0, 0.0, 0.0, 0.05]]},
			"LegL": {"rot": [[0.0, 0.0, 0.0, 0.0], [0.4, -0.3, 0.0, 0.0], [0.56, 0.45, 0.0, 0.0], [1.0, 0.0, 0.0, 0.0]]},
			"LegR": {"rot": [[0.0, 0.0, 0.0, 0.0], [0.4, 0.3, 0.0, 0.0], [0.56, -0.35, 0.0, 0.0], [1.0, 0.0, 0.0, 0.0]]},
		},
		"methods": [[0.41, SWING_VFX]],
	},
	&"attack_heavy": {
		"startup_end": 0.46,
		"active_end": 0.66,
		"tracks": {
			"Root": {
				"pos": [[0.0, 0.0, 0.0, 0.0], [0.3, 0.0, -0.1, -0.12], [0.46, 0.0, 0.14, -0.16], [0.6, 0.0, -0.1, 0.26], [1.0, 0.0, 0.0, 0.0]],
			},
			"Torso": {"rot": [[0.0, 0.0, 0.0, 0.0], [0.3, -0.18, -0.5, 0.0], [0.46, -0.42, -0.85, 0.0], [0.62, 0.55, 0.75, 0.0], [1.0, 0.0, 0.0, 0.0]]},
			"Head": {"rot": [[0.0, 0.0, 0.0, 0.0], [0.46, -0.2, 0.45, 0.0], [0.62, 0.3, -0.3, 0.0], [1.0, 0.0, 0.0, 0.0]]},
			"ArmR": {"rot": [[0.0, 0.0, 0.0, -0.05], [0.3, -1.6, -0.4, -0.7], [0.46, -2.5, -0.5, -1.0], [0.62, 1.15, 0.45, 0.35], [0.8, 0.5, 0.2, 0.1], [1.0, 0.0, 0.0, -0.05]]},
			"ArmL": {"rot": [[0.0, 0.0, 0.0, 0.05], [0.3, -1.4, 0.3, 0.5], [0.46, -2.3, 0.4, 0.8], [0.62, 1.0, -0.35, -0.25], [1.0, 0.0, 0.0, 0.05]]},
			"LegL": {"rot": [[0.0, 0.0, 0.0, 0.0], [0.46, -0.42, 0.0, 0.12], [0.62, 0.6, 0.0, 0.0], [1.0, 0.0, 0.0, 0.0]]},
			"LegR": {"rot": [[0.0, 0.0, 0.0, 0.0], [0.46, 0.4, 0.0, -0.12], [0.62, -0.45, 0.0, 0.0], [1.0, 0.0, 0.0, 0.0]]},
		},
		"methods": [[0.47, SWING_VFX]],
	},
	&"attack_thrust": {
		"startup_end": 0.36,
		"active_end": 0.6,
		"tracks": {
			"Root": {"pos": [[0.0, 0.0, 0.0, 0.0], [0.36, 0.0, 0.0, -0.14], [0.5, 0.0, 0.0, 0.28], [1.0, 0.0, 0.0, 0.0]]},
			"Torso": {"rot": [[0.0, 0.0, 0.0, 0.0], [0.36, 0.0, -0.42, 0.0], [0.5, 0.18, 0.22, 0.0], [1.0, 0.0, 0.0, 0.0]]},
			"ArmR": {"rot": [[0.0, 0.0, 0.0, -0.05], [0.36, -0.55, -0.6, -0.2], [0.5, -1.45, 0.1, -0.05], [0.72, -0.6, 0.0, -0.05], [1.0, 0.0, 0.0, -0.05]]},
			"ArmL": {"rot": [[0.0, 0.0, 0.0, 0.05], [0.36, -0.4, 0.3, 0.3], [0.5, -1.2, -0.1, 0.1], [1.0, 0.0, 0.0, 0.05]]},
			"LegL": {"rot": [[0.0, 0.0, 0.0, 0.0], [0.36, -0.15, 0.0, 0.0], [0.5, 0.55, 0.0, 0.0], [1.0, 0.0, 0.0, 0.0]]},
			"LegR": {"rot": [[0.0, 0.0, 0.0, 0.0], [0.36, 0.2, 0.0, 0.0], [0.5, -0.45, 0.0, 0.0], [1.0, 0.0, 0.0, 0.0]]},
		},
		"methods": [[0.37, SWING_VFX]],
	},
	&"attack_shoot": {
		"startup_end": 0.55,
		"active_end": 0.7,
		"tracks": {
			"Torso": {"rot": [[0.0, 0.0, 0.0, 0.0], [0.55, 0.0, -0.5, 0.0], [0.7, 0.0, -0.42, 0.0], [1.0, 0.0, 0.0, 0.0]]},
			"Head": {"rot": [[0.0, 0.0, 0.0, 0.0], [0.55, 0.0, 0.34, 0.0], [1.0, 0.0, 0.0, 0.0]]},
			"ArmL": {"rot": [[0.0, 0.0, 0.0, 0.05], [0.55, -1.5, 0.35, 0.15], [0.7, -1.5, 0.35, 0.15], [1.0, 0.0, 0.0, 0.05]]},
			"ArmR": {"rot": [[0.0, 0.0, 0.0, -0.05], [0.55, -1.2, -0.75, -0.1], [0.7, -1.4, -0.15, -0.1], [1.0, 0.0, 0.0, -0.05]]},
			"Bow": {"rot": [[0.0, 0.0, 0.0, 0.0], [0.55, 0.0, 0.0, 0.12], [0.7, 0.0, 0.0, -0.05], [1.0, 0.0, 0.0, 0.0]]},
		},
		"methods": [[0.56, SWING_VFX]],
	},
	&"attack_bite": {
		"startup_end": 0.4,
		"active_end": 0.62,
		"tracks": {
			"Root": {"pos": [[0.0, 0.0, 0.0, 0.0], [0.4, 0.0, -0.06, -0.16], [0.54, 0.0, 0.1, 0.34], [1.0, 0.0, 0.0, 0.0]]},
			"Torso": {"rot": [[0.0, 0.0, 0.0, 0.0], [0.4, 0.28, 0.0, 0.0], [0.54, -0.34, 0.0, 0.0], [1.0, 0.0, 0.0, 0.0]]},
			"Head": {"rot": [[0.0, 0.0, 0.0, 0.0], [0.4, 0.45, 0.0, 0.0], [0.54, -0.62, 0.0, 0.0], [1.0, 0.0, 0.0, 0.0]]},
			"Tail": {"rot": [[0.0, 0.0, 0.0, 0.0], [0.4, -0.4, 0.35, 0.0], [0.54, 0.3, -0.3, 0.0], [1.0, 0.0, 0.0, 0.0]]},
			"LegL": {"rot": [[0.0, 0.0, 0.0, 0.0], [0.4, -0.5, 0.0, 0.0], [0.54, 0.7, 0.0, 0.0], [1.0, 0.0, 0.0, 0.0]]},
			"LegR": {"rot": [[0.0, 0.0, 0.0, 0.0], [0.4, -0.5, 0.0, 0.0], [0.54, 0.7, 0.0, 0.0], [1.0, 0.0, 0.0, 0.0]]},
		},
		"methods": [[0.41, SWING_VFX]],
	},
	&"attack_shield_bash": {
		"startup_end": 0.42,
		"active_end": 0.62,
		"tracks": {
			"Root": {"pos": [[0.0, 0.0, 0.0, 0.0], [0.42, 0.0, 0.0, -0.16], [0.55, 0.0, 0.0, 0.3], [1.0, 0.0, 0.0, 0.0]]},
			"Torso": {"rot": [[0.0, 0.0, 0.0, 0.0], [0.42, 0.0, 0.62, 0.0], [0.55, 0.12, -0.5, 0.0], [1.0, 0.0, 0.0, 0.0]]},
			"ArmL": {"rot": [[0.0, 0.0, 0.0, 0.05], [0.42, -0.8, 0.7, 0.55], [0.55, -1.1, -0.35, 0.2], [1.0, 0.0, 0.0, 0.05]]},
			"ArmR": {"rot": [[0.0, 0.0, 0.0, -0.05], [0.42, -0.2, -0.3, -0.4], [1.0, 0.0, 0.0, -0.05]]},
			"LegL": {"rot": [[0.0, 0.0, 0.0, 0.0], [0.42, -0.2, 0.0, 0.0], [0.55, 0.5, 0.0, 0.0], [1.0, 0.0, 0.0, 0.0]]},
			"LegR": {"rot": [[0.0, 0.0, 0.0, 0.0], [0.42, 0.25, 0.0, 0.0], [0.55, -0.4, 0.0, 0.0], [1.0, 0.0, 0.0, 0.0]]},
		},
		"methods": [[0.43, SWING_VFX]],
	},
}

## Which attack clip an enemy or weapon archetype swings.
const PROFILE_ATTACKS := {
	"player": [&"attack_light_1", &"attack_light_2", &"attack_light_3"],
	"melee": [&"attack_light_1", &"attack_light_2"],
	"brute": [&"attack_heavy"],
	"shield": [&"attack_shield_bash"],
	"ranged": [&"attack_shoot"],
	"hound": [&"attack_bite"],
}

const WEAPON_ATTACKS := {
	"sword": [&"attack_light_1", &"attack_light_2", &"attack_light_3"],
	"greatsword": [&"attack_light_3", &"attack_heavy"],
	"dagger": [&"attack_light_1", &"attack_light_2"],
	"spear": [&"attack_thrust"],
	"bow": [&"attack_shoot"],
}


static func attack_clips_for(profile: String, weapon_archetype: String = "") -> Array:
	if weapon_archetype != "" and WEAPON_ATTACKS.has(weapon_archetype):
		return WEAPON_ATTACKS[weapon_archetype]
	return PROFILE_ATTACKS.get(profile, PROFILE_ATTACKS["melee"])


static func heavy_clip_for(weapon_archetype: String) -> StringName:
	match weapon_archetype:
		"spear":
			return &"attack_thrust"
		"bow":
			return &"attack_shoot"
		_:
			return &"attack_heavy"


## Compiles every locomotion/reaction clip that the given rig can actually play.
## rest_pose maps part name -> {"position": Vector3, "rotation": Vector3}.
static func build_library(rest_pose: Dictionary, events_path: String) -> AnimationLibrary:
	var library := AnimationLibrary.new()
	for clip_name in CLIPS:
		var anim := _compile(CLIPS[clip_name], rest_pose, events_path, 1.0)
		if anim:
			library.add_animation(clip_name, anim)
	# RESET lets AnimationPlayer blend cleanly back to the rest pose.
	var reset := _compile_reset(rest_pose)
	if reset:
		library.add_animation(&"RESET", reset)
	return library


## Builds one attack clip stretched so its phase boundaries match the weapon data.
static func build_attack(
	clip_name: StringName,
	rest_pose: Dictionary,
	events_path: String,
	startup: float,
	active: float,
	recovery: float
) -> Animation:
	var spec: Dictionary = ATTACKS.get(clip_name, {})
	if spec.is_empty():
		return null
	var startup_end: float = float(spec.get("startup_end", 0.35))
	var active_end: float = float(spec.get("active_end", 0.6))
	var total := maxf(0.08, startup + active + recovery)
	var remap := {
		"startup_end": startup_end,
		"active_end": active_end,
		"startup_time": startup,
		"active_time": startup + active,
		"total": total,
	}
	return _compile(spec, rest_pose, events_path, 1.0, remap)


static func _compile(
	spec: Dictionary,
	rest_pose: Dictionary,
	events_path: String,
	speed: float,
	remap: Dictionary = {}
) -> Animation:
	var anim := Animation.new()
	var length: float = float(remap.get("total", float(spec.get("length", 1.0)) / maxf(0.01, speed)))
	anim.length = maxf(0.02, length)
	anim.loop_mode = Animation.LOOP_LINEAR if bool(spec.get("loop", false)) else Animation.LOOP_NONE

	var tracks: Dictionary = spec.get("tracks", {})
	var wrote_any := false
	for part_name in tracks:
		if not rest_pose.has(part_name):
			continue
		var rest: Dictionary = rest_pose[part_name]
		var node_path: String = rest.get("path", part_name)
		var channels: Dictionary = tracks[part_name]
		if channels.has("pos"):
			_add_vector_track(
				anim, "%s:position" % node_path, channels["pos"], rest.get("position", Vector3.ZERO), remap
			)
			wrote_any = true
		if channels.has("rot"):
			_add_vector_track(
				anim, "%s:rotation" % node_path, channels["rot"], rest.get("rotation", Vector3.ZERO), remap
			)
			wrote_any = true

	if not wrote_any:
		return null

	var methods: Array = spec.get("methods", [])
	if not methods.is_empty() and events_path != "":
		var track := anim.add_track(Animation.TYPE_METHOD)
		anim.track_set_path(track, NodePath(events_path))
		for entry in methods:
			var time := _remap_time(float(entry[0]), remap)
			anim.track_insert_key(track, time, {"method": entry[1], "args": []})
	return anim


static func _add_vector_track(
	anim: Animation,
	path: String,
	keys: Array,
	rest_value: Vector3,
	remap: Dictionary
) -> void:
	var track := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(track, NodePath(path))
	anim.track_set_interpolation_type(track, Animation.INTERPOLATION_LINEAR)
	anim.value_track_set_update_mode(track, Animation.UPDATE_CONTINUOUS)
	for key in keys:
		var time := _remap_time(float(key[0]), remap)
		var offset := Vector3(float(key[1]), float(key[2]), float(key[3]))
		anim.track_insert_key(track, time, rest_value + offset)


## Piecewise-linear stretch of a normalised attack timeline onto real phase times.
static func _remap_time(normalised: float, remap: Dictionary) -> float:
	if remap.is_empty():
		return normalised
	var startup_end: float = remap["startup_end"]
	var active_end: float = remap["active_end"]
	var startup_time: float = remap["startup_time"]
	var active_time: float = remap["active_time"]
	var total: float = remap["total"]
	if normalised <= startup_end:
		return _segment(normalised, 0.0, startup_end, 0.0, startup_time)
	if normalised <= active_end:
		return _segment(normalised, startup_end, active_end, startup_time, active_time)
	return _segment(normalised, active_end, 1.0, active_time, total)


static func _segment(value: float, in_min: float, in_max: float, out_min: float, out_max: float) -> float:
	var span := in_max - in_min
	if span <= 0.0001:
		return out_min
	return out_min + (value - in_min) / span * (out_max - out_min)


static func _compile_reset(rest_pose: Dictionary) -> Animation:
	var anim := Animation.new()
	anim.length = 0.1
	anim.loop_mode = Animation.LOOP_NONE
	var wrote_any := false
	for part_name in rest_pose:
		var rest: Dictionary = rest_pose[part_name]
		var node_path: String = rest.get("path", part_name)
		var pos_track := anim.add_track(Animation.TYPE_VALUE)
		anim.track_set_path(pos_track, NodePath("%s:position" % node_path))
		anim.track_insert_key(pos_track, 0.0, rest.get("position", Vector3.ZERO))
		var rot_track := anim.add_track(Animation.TYPE_VALUE)
		anim.track_set_path(rot_track, NodePath("%s:rotation" % node_path))
		anim.track_insert_key(rot_track, 0.0, rest.get("rotation", Vector3.ZERO))
		wrote_any = true
	return anim if wrote_any else null
