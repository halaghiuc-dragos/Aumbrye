extends Node
class_name PixelCameraSnap

## Snaps a Camera3D (or SpringArm3D parent chain) to the pixel grid to reduce sub-pixel jitter.

@export var target_path: NodePath
@export var snap_enabled := true

var _target: Node3D


func _ready() -> void:
	if target_path:
		_target = get_node_or_null(target_path) as Node3D
	if _target == null:
		_target = get_parent() as Node3D


func _physics_process(_delta: float) -> void:
	if not snap_enabled or _target == null:
		return
	if not PixelDioramaSettings.camera_snap_enabled:
		return
	var step := PixelDioramaSettings.camera_snap_step()
	var pos := _target.global_position
	_target.global_position = Vector3(
		_snap_axis(pos.x, step),
		_snap_axis(pos.y, step),
		_snap_axis(pos.z, step)
	)


static func _snap_axis(value: float, step: float) -> float:
	if step <= 0.0:
		return value
	return roundf(value / step) * step
