extends RefCounted
class_name PixelCameraSnap

## Snaps a camera origin and rotation to the pixel grid so surface patterns stop crawling.


## Quantizes a camera origin onto a world-axis grid of `step` metres.
## `enabled` is passed in so the function is pure and testable.
static func snap_origin(origin: Vector3, step: float, enabled: bool = true) -> Vector3:
	if not enabled or step <= 0.0:
		return origin
	return Vector3(
		snappedf(origin.x, step),
		snappedf(origin.y, step),
		snappedf(origin.z, step)
	)


## One rendered pixel of angular travel at the frame's vertical resolution.
static func rotation_step_radians(fov_degrees: float) -> float:
	var height := float(maxi(90, PixelDioramaSettings.active_render_height))
	return deg_to_rad(clampf(fov_degrees, 10.0, 170.0)) / height


static func snap_basis(basis: Basis, enabled: bool = true) -> Basis:
	if not enabled:
		return basis
	var step := rotation_step_radians(PixelDioramaSettings.snap_fov_hint)
	var euler := basis.get_euler()
	return Basis.from_euler(Vector3(snappedf(euler.x, step), snappedf(euler.y, step), euler.z))


static func snap_transform(
	source: Transform3D,
	fov_degrees: float,
	focus_distance: float,
	enabled: bool = true
) -> Transform3D:
	if not enabled:
		return source
	var step := PixelDioramaSettings.camera_snap_step(fov_degrees, focus_distance)
	if step <= 0.0:
		return source
	return Transform3D(
		snap_basis(source.basis, enabled), snap_origin(source.origin, step, enabled)
	)
