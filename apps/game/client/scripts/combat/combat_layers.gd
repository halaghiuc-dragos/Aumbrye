class_name CombatLayers
extends RefCounted

## Named physics layer masks for combat queries.
##
## These mirror the layer names in project.godot. They exist so that "what counts as an occluder"
## is stated once and can be changed in one place, instead of living as a bare `collision_mask = 1`
## duplicated across perception, targeting and camera code.

## project.godot 3d_physics/layer_1 = "world"
const WORLD := 1 << 0
## layer_2 = "player_body"
const PLAYER_BODY := 1 << 1
## layer_3 = "hitbox"
const HITBOX := 1 << 2
## layer_4 = "hurtbox"
const HURTBOX := 1 << 3
## layer_5 = "interactable"
const INTERACTABLE := 1 << 4
## layer_6 = "trap"
const TRAP := 1 << 5
## layer_7 = "projectile"
const PROJECTILE := 1 << 6
## layer_8 = "camera_blocker"
const CAMERA_BLOCKER := 1 << 7

## Geometry that blocks an enemy's line of sight to the player.
##
## Currently just `world`: every occluder the game authors — blockout walls, floor shells, boss
## doors, locked-door and puzzle-gate barriers (created as bare StaticBody3D, which defaults to
## layer 1) — lands there. `interactable` is deliberately excluded, since levers and chests sit on
## it and must not blind enemies.
##
## If you author new occluding geometry on a different layer, add the layer here rather than
## editing individual raycasts — cover mechanics silently depend on this mask being complete.
const WORLD_OCCLUDERS := WORLD
