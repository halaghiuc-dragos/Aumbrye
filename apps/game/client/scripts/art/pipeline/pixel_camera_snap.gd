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


## C-173: this derived its rotation step from the **global** `PixelDioramaSettings.snap_fov_hint`
## rather than the FOV its caller was working with. `snap_transform` sets that hint one line before
## calling in, so the two agreed by assignment order rather than by construction — and a second
## caller with a different FOV would silently have used the first one's. The FOV is a parameter now,
## defaulting to the hint so existing callers are unaffected.
##
## `euler.z` is deliberately left unquantised: roll should not step.
static func snap_basis(basis: Basis, enabled: bool = true, fov_degrees: float = -1.0) -> Basis:
	if not enabled:
		return basis
	var fov := fov_degrees if fov_degrees > 0.0 else PixelDioramaSettings.snap_fov_hint
	var step := rotation_step_radians(fov)
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
		snap_basis(source.basis, enabled, fov_degrees),
		snap_origin(source.origin, step, enabled)
	)
