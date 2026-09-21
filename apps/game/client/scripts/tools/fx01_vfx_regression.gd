extends Node

## Headless regression probe for FX01. Run with the matching scene so project autoloads are active:
## `godot --headless --path apps/game/client res://scenes/debug/fx01_vfx_regression.tscn`.

func _ready() -> void:
	var vfx := get_node_or_null("/root/VfxService")
	if vfx == null:
		_fail("VfxService autoload is unavailable")
		return
	for direction in [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]:
		var aligned: Vector3 = vfx._aligned_direction(direction, "forward")
		if not aligned.is_equal_approx(direction.normalized()):
			_fail("forward burst direction was not preserved: %s" % direction)
			return
		var emitter := CPUParticles3D.new()
		vfx._root.add_child(emitter)
		emitter.global_basis = Basis(Vector3.UP, 0.75)
		vfx._reset_burst_transform(emitter, Vector3(3.0, 2.0, -1.0))
		if not emitter.global_basis.is_equal_approx(Basis.IDENTITY):
			_fail("pooled burst retained a previous orientation")
			return
		if not emitter.global_position.is_equal_approx(Vector3(3.0, 2.0, -1.0)):
			_fail("pooled burst position was not reset")
			return
		emitter.queue_free()
	var parity_cfg := {
		"chunk": "shard_small",
		"explosiveness": 1.0,
		"randomness": 0.15,
		"flatness": 0.05,
		"spread": 180.0,
		"gravity": Vector3.ZERO,
		"velocity_min": 7.0,
		"velocity_max": 12.0,
		"scale_min": 0.09,
		"scale_max": 0.16,
		"emission": 5.6,
	}
	vfx._emit_gpu_burst("Fx02Parity", Vector3.ZERO, Vector3.UP, Color.WHITE, 26, 0.16, parity_cfg)
	var gpu: GPUParticles3D = null
	for candidate in vfx._gpu_burst_pool:
		if candidate is GPUParticles3D and candidate.name == "Fx02Parity":
			gpu = candidate as GPUParticles3D
			break
	if gpu == null:
		_fail("GPU parity burst was not acquired from the pool")
		return
	var material := gpu.process_material as ParticleProcessMaterial
	if not is_equal_approx(gpu.explosiveness, 1.0) or not is_equal_approx(gpu.randomness, 0.15):
		_fail("GPU burst did not apply timing randomness/explosiveness")
		return
	if material == null or not is_equal_approx(material.flatness, 0.05):
		_fail("GPU burst did not apply flatness")
		return
	vfx._build_weapon_trail(Vector3.ZERO, Vector3.FORWARD, Color.WHITE, 1.0, 0.1, 90.0, 2.0)
	var trail := vfx._root.get_node_or_null("WeaponTrail") as Node3D
	var trail_mesh := trail.get_child(0) as MeshInstance3D if trail != null else null
	var trail_material := trail_mesh.material_override as ShaderMaterial if trail_mesh != null else null
	if trail_material == null or trail_material.shader == null or trail_material.shader.resource_path != "res://assets/shared/pixel_diorama_trail.gdshader":
		_fail("weapon trail did not use the alpha-aware transient material")
		return
	print("FX01-FX03 VFX regression passed.")
	get_tree().quit()


func _fail(message: String) -> void:
	push_error("FX01 VFX regression failed: %s" % message)
	get_tree().quit(1)
