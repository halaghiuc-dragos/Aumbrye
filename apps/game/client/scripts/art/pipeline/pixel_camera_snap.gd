extends RefCounted
class_name PixelCameraSnap

## Snaps a camera origin to the pixel grid so surface patterns stop crawling.


static func snap_transform(source: Transform3D, fov_degrees: float, focus_distance: float) -> Transform3D:
	if not PixelDioramaSettings.camera_snap_enabled:
		return source
	var step := PixelDioramaSettings.camera_snap_step(fov_degrees, focus_distance)
	if step <= 0.0:
		return source
	var right := source.basis.x
	var up := source.basis.y
	var origin := source.origin
	var lateral := right.dot(origin)
	var vertical := up.dot(origin)
	var snapped_origin := origin
	snapped_origin += right * (snappedf(lateral, step) - lateral)
	snapped_origin += up * (snappedf(vertical, step) - vertical)
	return Transform3D(source.basis, snapped_origin)
