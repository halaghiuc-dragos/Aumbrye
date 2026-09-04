extends Node
class_name Knockback

## `PH-01`: the piece that was missing entirely -- a hit changed numbers, never positions. This is
## a small impulse accumulator, not a physics body: it owns a horizontal velocity that decays
## toward zero, and the owning `CharacterBody3D` reads it once a frame (`consume()`) and folds it
## into its own `velocity` before `move_and_slide()`. Nothing here calls `move_and_slide()` itself
## -- this codebase's only mover is the character body's own physics step (see the trap in PH-01:
## no `RigidBody3D`, no `global_position +=`).

## Impulse bleeds off at this rate (m/s per second), so a typical strength is spent in ~0.15 s.
const DECAY_RATE := 18.0

var _impulse := Vector3.ZERO


## `direction` is normalised and flattened here (Trap 1: knockback is horizontal-only for grounded
## targets -- a hit that launched enemies into the ceiling would read as a bug, not an impact).
## Applying while an existing impulse is still live takes whichever is stronger per axis rather
## than stacking, so a flurry of light hits cannot out-shove one heavy one.
func apply(direction: Vector3, strength: float) -> void:
	if strength <= 0.0:
		return
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length_squared() < 0.0001:
		return
	var next := flat.normalized() * strength
	if next.length_squared() > _impulse.length_squared():
		_impulse = next


## Call once a frame from the owner's `_physics_process()`, before `move_and_slide()`. Returns the
## impulse to add into `velocity` this frame and decays the stored impulse toward zero.
func consume(delta: float) -> Vector3:
	if _impulse.length_squared() < 0.0001:
		_impulse = Vector3.ZERO
		return Vector3.ZERO
	var out := _impulse
	var speed := _impulse.length()
	var decayed := maxf(0.0, speed - DECAY_RATE * delta)
	_impulse = _impulse.normalized() * decayed if decayed > 0.0 else Vector3.ZERO
	return out


func clear() -> void:
	_impulse = Vector3.ZERO


func is_active() -> bool:
	return _impulse.length_squared() > 0.0001
