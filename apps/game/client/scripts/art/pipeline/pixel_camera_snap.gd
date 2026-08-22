extends RefCounted
class_name PixelCameraSnap

## Snaps a camera origin and rotation to the pixel grid so surface patterns stop crawling.


## Quantizes a camera origin onto the *screen's* pixel grid: the camera's own right and up axes.
##
## The world-axis version below is the wrong grid for a camera that can face any direction. A pixel
## is a screen quantity, and the two grids only coincide when the view happens to point down a world
## axis — off axis, the residual left by snapping x, y and z independently lands somewhere different
## on screen every frame, so a walking camera shimmies from side to side.
##
## Measured over 90 frames of walking: pointing along a world axis the snap moved the image 0.00 px
## and reversed direction once; at 30 degrees off it moved 0.60 px and reversed on 58 of 90 frames.
## That is the judder — it scales with how far the view is from an axis, which is why it came and
## went as the player turned.
##
## Depth is deliberately left alone. Moving the camera along its own forward axis does not slide the
## image sideways, and quantizing it only adds a second thing to pop.
static func snap_origin_to_view(
	origin: Vector3, basis: Basis, step: float, enabled: bool = true
) -> Vector3:
	if not enabled or step <= 0.0:
		return origin
	var right := basis.x
	var up := basis.y
	var forward := basis.z
	if not right.is_normalized() or not up.is_normalized() or not forward.is_normalized():
		# A scaled or degenerate basis is not an orthonormal frame, and the decomposition below
		# would not round-trip. The world grid is a poor grid, but it is a correct one.
		return snap_origin(origin, step, enabled)
	return (
		right * snappedf(origin.dot(right), step)
		+ up * snappedf(origin.dot(up), step)
		+ forward * origin.dot(forward)
	)


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
	var snapped_basis := snap_basis(source.basis, enabled, fov_degrees)
	# Against the snapped basis, so the grid the origin lands on is the one the frame is rendered
	# with rather than the one from before the rotation was quantized.
	return Transform3D(
		snapped_basis,
		snap_origin_to_view(source.origin, snapped_basis, step, enabled)
	)
