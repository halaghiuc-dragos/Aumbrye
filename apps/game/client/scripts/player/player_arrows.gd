extends Node
class_name PlayerArrows

## `RG-02`: the recovering quiver -- `arrows_max` (12) that refills fully at a bonfire
## (`RunFlow.rest_at_bonfire`) and by 1 every `REGEN_INTERVAL` seconds out of combat. Mirrors
## `PlayerHeal` deliberately: charges, a signal, HUD pips, refill at rest -- the same shape rather
## than a second inventory system for a quiver that was never meant to have pickups.

const DEFAULT_MAX_ARROWS := 12
const REGEN_INTERVAL := 6.0
## A shot fired or a hit taken both count as "still in the fight" -- the regen timer holds off
## rather than ticking through a fight, the same rule `PlayerHeal.REGEN_SUPPRESSION_AFTER_HIT`
## already applies to health regen.
const REGEN_SUPPRESSION := 4.0

signal arrows_changed(current: int, max_value: int)

var max_arrows := DEFAULT_MAX_ARROWS
var current_arrows := DEFAULT_MAX_ARROWS

var _body: CharacterBody3D
var _weapon: WeaponController
var _regen_timer := 0.0
var _regen_suppressed := 0.0


func _ready() -> void:
	_body = get_parent() as CharacterBody3D
	_weapon = _body.get_node_or_null("WeaponController") as WeaponController
	if _weapon and not _weapon.attack_started.is_connected(_on_attack_started):
		_weapon.attack_started.connect(_on_attack_started)
	call_deferred("_bind_hurtbox")
	arrows_changed.emit(current_arrows, max_arrows)


func _bind_hurtbox() -> void:
	if _body == null or not is_instance_valid(_body):
		return
	var hurtbox := _body.get_node_or_null("Hurtbox")
	if hurtbox and hurtbox.has_signal("hurt_received"):
		if not hurtbox.hurt_received.is_connected(_on_hurt_received):
			hurtbox.hurt_received.connect(_on_hurt_received)


func _on_hurt_received(amount: float, _poise_damage: float, _direction: Vector3) -> void:
	if amount > 0.0:
		_suppress_regen()


func _on_attack_started(attack_name: String) -> void:
	if attack_name == "bow_shot":
		_suppress_regen()


func _suppress_regen() -> void:
	_regen_suppressed = REGEN_SUPPRESSION


func _physics_process(delta: float) -> void:
	if _regen_suppressed > 0.0:
		_regen_suppressed -= delta
		return
	if current_arrows >= max_arrows:
		_regen_timer = 0.0
		return
	_regen_timer += delta
	if _regen_timer >= REGEN_INTERVAL:
		_regen_timer -= REGEN_INTERVAL
		grant_arrow(1)


func has_arrow() -> bool:
	return current_arrows > 0


func consume_arrow() -> bool:
	if current_arrows <= 0:
		return false
	current_arrows -= 1
	arrows_changed.emit(current_arrows, max_arrows)
	return true


func grant_arrow(count: int = 1) -> void:
	if count <= 0:
		return
	var granted := mini(max_arrows, current_arrows + count)
	if granted == current_arrows:
		return
	current_arrows = granted
	arrows_changed.emit(current_arrows, max_arrows)


func refill_arrows() -> void:
	_regen_timer = 0.0
	_regen_suppressed = 0.0
	if current_arrows == max_arrows:
		return
	current_arrows = max_arrows
	arrows_changed.emit(current_arrows, max_arrows)
