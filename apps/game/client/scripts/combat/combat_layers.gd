class_name CombatLayers
extends RefCounted


const WORLD := 1 << 0
const PLAYER_BODY := 1 << 1
const HITBOX := 1 << 2
const HURTBOX := 1 << 3
const INTERACTABLE := 1 << 4
const TRAP := 1 << 5
const PROJECTILE := 1 << 6
const CAMERA_BLOCKER := 1 << 7

## Named rather than a bare `collision_mask = 1` at each call site: perception, targeting, camera
## and projectiles all need the same value, and a literal drifts silently when one of them moves.
const WORLD_OCCLUDERS := WORLD
