extends RefCounted
class_name PixelCameraSnap


static func snap_origin_to_view(
	origin: Vector3, basis: Basis, step: float, enabled: bool = true
) -> Vector3:
	if not enabled or step <= 0.0:
		return origin
	var right := basis.x
	var up := basis.y
	var forward := basis.z
	if not right.is_normalized() or not up.is_normalized() or not forward.is_normalized():
		return snap_origin(origin, step, enabled)
	return (
		right * snappedf(origin.dot(right), step)
		+ up * snappedf(origin.dot(up), step)
		+ forward * origin.dot(forward)
	)


static func snap_origin(origin: Vector3, step: float, enabled: bool = true) -> Vector3:
	if not enabled or step <= 0.0:
		return origin
	return Vector3(
		snappedf(origin.x, step),
		snappedf(origin.y, step),
		snappedf(origin.z, step)
	)


static func rotation_step_radians(fov_degrees: float) -> float:
	var height := float(maxi(90, PixelDioramaSettings.active_render_height))
	return deg_to_rad(clampf(fov_degrees, 10.0, 170.0)) / height


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
	var snapped_basis := snap_basis(source.basis, enabled, fov_degrees)
	return Transform3D(
		snapped_basis,
		snap_origin_to_view(source.origin, snapped_basis, step, enabled)
	)
