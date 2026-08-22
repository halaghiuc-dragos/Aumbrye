extends Node

## Crisp low-res 3D: shared-world SubViewport + mirrored camera (no node reparenting).
##
## The scene graph is never reparented into the SubViewport; only the camera is
## mirrored. See docs/design/visual_enhancement_plan.md for the rejected
## alternatives (own_world_3d, scaling_3d_scale, pivot snapping) and why.

signal world_attached(scene_root: Node)

enum ScreenPulse { DAMAGE, HEAL, PARRY, LOW_STAMINA }

const PULSE_TUNING := {
	ScreenPulse.DAMAGE: {
		"param": "damage_pulse",
		"peak": 0.72,
		"decay": 0.28,
		"tint": Color(0.62, 0.08, 0.08),
	},
	ScreenPulse.HEAL: {
		"param": "damage_pulse",
		"peak": 0.34,
		"decay": 0.45,
		"tint": Color(0.24, 0.68, 0.32),
	},
	ScreenPulse.PARRY: {
		"param": "damage_pulse",
		"peak": 0.55,
		"decay": 0.16,
		"tint": Color(0.98, 0.88, 0.35),
	},
	ScreenPulse.LOW_STAMINA: {
		"param": "damage_pulse",
		"peak": 0.22,
		"decay": 0.60,
		"tint": Color(0.35, 0.32, 0.52),
	},
}

## Fallback focus distance when the spring arm cannot be resolved.
const SNAP_FOCUS_DISTANCE_FALLBACK := 5.0

var _layer: CanvasLayer
## Visual layer the contour quad lives on.
##
## The SubViewport shares the main World3D (`own_world_3d = false`), so anything parented under the
## render camera is in the same world the gameplay camera is looking at. Giving the quad a layer of
## its own and adding only that bit to the render camera's cull mask is what keeps a full-screen
## black quad from being drawn over the actual game.
const OUTLINE_LAYER_BIT := 19
const OUTLINE_LAYER_MASK := 1 << OUTLINE_LAYER_BIT

var _outline_quad: MeshInstance3D
var _outline_material: ShaderMaterial
var _container: SubViewportContainer
var _viewport: SubViewport
var _render_camera: Camera3D
var _source_camera: Camera3D
var _spring_arm: SpringArm3D
var _finish_material: ShaderMaterial
var _distress := 0.0
var _distress_tween: Tween
var _attached_scene: Node
var _root_3d_was_disabled: Variant = null
var _bind_warned := false
var _last_source_xform: Transform3D
var _last_source_fov := -1.0
var _pipeline_active := false
var _menu_hidden := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_nodes()
	get_tree().root.size_changed.connect(_on_root_size_changed)
	get_tree().root.child_entered_tree.connect(_on_root_child_entered)
	if MenuStack and not MenuStack.stack_changed.is_connected(_on_menu_stack_changed):
		MenuStack.stack_changed.connect(_on_menu_stack_changed)
	if OS.is_debug_build() and OS.get_environment("AUMBRYE_GFX_DUMP") != "":
		get_tree().create_timer(3.0).timeout.connect(_dbg_dump)


func _on_menu_stack_changed(depth: int) -> void:
	_menu_hidden = depth > 0
	_update_layer_visibility()


func _update_layer_visibility() -> void:
	if _layer:
		_layer.visible = _pipeline_active and not _menu_hidden


func dump_render_state() -> Dictionary:
	var counts := {}
	var lights: Array[String] = []
	_dbg_walk(get_tree().root, counts, lights)
	return {
		"cast_shadow_counts": counts,
		"directional_light_count": lights.size(),
		"directional_lights": lights,
		"renderer": ProjectSettings.get_setting("rendering/renderer/rendering_method", "?"),
	}


func _dbg_dump() -> void:
	if not OS.is_debug_build() or OS.get_environment("AUMBRYE_GFX_DUMP") == "":
		return
	var state := dump_render_state()
	print("[DBG] cast_shadow counts: ", state.get("cast_shadow_counts", {}))
	for l in state.get("directional_lights", []):
		print("[DBG] ", l)
	print("[DBG] renderer: ", state.get("renderer", "?"))


func _dbg_walk(n: Node, counts: Dictionary, lights: Array[String]) -> void:
	if n is GeometryInstance3D:
		var k := str((n as GeometryInstance3D).cast_shadow)
		counts[k] = int(counts.get(k, 0)) + 1
	if n is DirectionalLight3D:
		var d := n as DirectionalLight3D
		lights.append(
			(
				"%s shadow=%s energy=%.2f rot=%s vis=%s layers=%d"
				% [
					d.name,
					d.shadow_enabled,
					d.light_energy,
					d.rotation,
					d.is_visible_in_tree(),
					d.light_cull_mask
				]
			)
		)
	for c in n.get_children():
		_dbg_walk(c, counts, lights)


func _build_nodes() -> void:
	_layer = CanvasLayer.new()
	_layer.name = "PixelDioramaViewportLayer"
	_layer.layer = -1
	_layer.visible = false
	add_child(_layer)
	_container = SubViewportContainer.new()
	_container.name = "PixelViewportContainer"
	_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_container.stretch = true
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_container)
	_viewport = SubViewport.new()
	_viewport.name = "PixelSubViewport"
	_viewport.disable_3d = false
	_viewport.own_world_3d = false
	_viewport.transparent_bg = false
	_viewport.handle_input_locally = false
	_viewport.gui_disable_input = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	# C-94: verified — no anti-aliasing mode is set anywhere in the project, so B-02 (FXAA inside
	# the low-res viewport) does not reproduce; these three took Godot's disabled defaults. Stated
	# explicitly so a later project-wide AA setting cannot silently start smearing the pixel render,
	# which is the failure the original finding was reaching for. Nearest filtering
	# (`default_texture_filter=0`) is already correct project-wide.
	_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	_viewport.msaa_3d = Viewport.MSAA_DISABLED
	_viewport.use_taa = false
	_container.add_child(_viewport)
	_render_camera = Camera3D.new()
	_render_camera.name = "PixelRenderCamera"
	_render_camera.current = false
	# Copied from the gameplay camera every frame in _process, which is the only way it can track a
	# camera that itself moves at render cadence. With project-wide physics interpolation on, that
	# made Godot warn on every write, and interpolating this camera would smear the low-resolution
	# render off the gameplay camera it is meant to reproduce exactly.
	_render_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_viewport.add_child(_render_camera)
	_build_outline_pass()
	_finish_material = PixelDioramaSettings.make_screen_finish_material()


## A clip-space quad parented to the render camera. It reads the depth and normal buffers of the
## pass it is drawn in, so it has to live inside the SubViewport rather than being a canvas shader
## over the top of it — the screen finish is a `canvas_item` shader and has no depth to read.
func _build_outline_pass() -> void:
	_outline_material = PixelDioramaSettings.make_outline_material()
	if _outline_material.shader == null:
		return
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	_outline_quad = MeshInstance3D.new()
	_outline_quad.name = "PixelOutlinePass"
	_outline_quad.mesh = quad
	_outline_quad.material_override = _outline_material
	_outline_quad.layers = OUTLINE_LAYER_MASK
	_outline_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The vertex shader rewrites POSITION into clip space, so the quad's real bounds say nothing
	# about where it lands on screen. Without a cull margin the engine frustum-culls it away the
	# moment the camera turns.
	_outline_quad.extra_cull_margin = 16384.0
	# Drawn after the world, so the contour sits over the geometry it was derived from.
	_outline_material.render_priority = 100
	_render_camera.add_child(_outline_quad)


func _process(_delta: float) -> void:
	if not _layer.visible:
		return
	if not PixelDioramaSettings.low_res_viewport_enabled:
		return
	if _source_camera == null or not is_instance_valid(_source_camera):
		if _attached_scene:
			_bind_source_camera(_attached_scene)
		return
	var xform := _source_camera.global_transform
	var fov := _source_camera.fov
	if xform.is_equal_approx(_last_source_xform) and is_equal_approx(fov, _last_source_fov):
		return
	_render_camera.projection = _source_camera.projection
	_render_camera.fov = fov
	_render_camera.near = _source_camera.near
	_render_camera.far = _source_camera.far
	_render_camera.keep_aspect = _source_camera.keep_aspect
	# Everything the gameplay camera sees, plus the contour layer that only this camera may see.
	_render_camera.cull_mask = _source_camera.cull_mask | OUTLINE_LAYER_MASK
	_render_camera.global_transform = _mirrored_transform()
	_last_source_xform = xform
	_last_source_fov = fov


func _focus_distance() -> float:
	if is_instance_valid(_spring_arm):
		return maxf(0.5, _spring_arm.spring_length)
	return SNAP_FOCUS_DISTANCE_FALLBACK


## Snapping happens on the render camera only. Snapping the gameplay CameraPivot
## decouples yaw from player movement and breaks SpringArm follow.
func _mirrored_transform() -> Transform3D:
	PixelDioramaSettings.snap_fov_hint = _source_camera.fov
	return PixelCameraSnap.snap_transform(
		_source_camera.global_transform,
		_source_camera.fov,
		_focus_distance(),
		PixelDioramaSettings.camera_snap_enabled
	)


func apply_settings() -> void:
	if _outline_material != null:
		PixelDioramaSettings.apply_outline_params(_outline_material)
	_apply_internal_size()
	if PixelDioramaSettings.is_native_hd_preset():
		_enforce_native_viewport_size()
	_apply_screen_finish()
	var quality_targets: Array = [get_tree().root, _viewport]
	PixelDioramaSettings.apply_render_quality(quality_targets)
	if PixelDioramaSettings.low_res_viewport_enabled and _attached_scene:
		_enable_pipeline()
	else:
		_disable_pipeline()


## Deferred entry point used by PixelDioramaBootstrap.attach_deferred().
func bootstrap_scene(scene_root: Node) -> void:
	if scene_root == null or not is_instance_valid(scene_root):
		return
	PixelDioramaSettings.bootstrap_scene_materials(scene_root)
	PixelDioramaSettings.apply_to_scene(scene_root)
	attach_to_scene(scene_root)


func attach_to_scene(scene_root: Node) -> void:
	# A new scene means a new player state. Without this, dying at 10% health and reloading into the
	# hub carried the low-health vignette across with it, because the fresh reactions node never
	# crosses the threshold downward and so never sends the release.
	clear_distress()
	if not PixelDioramaSettings.low_res_viewport_enabled:
		detach()
		return
	if scene_root == null:
		return
	if scene_root != _attached_scene:
		detach()
		_attached_scene = scene_root
		if not scene_root.tree_exiting.is_connected(_on_attached_scene_exiting):
			scene_root.tree_exiting.connect(_on_attached_scene_exiting)
	call_deferred("_bind_source_camera", scene_root)
	apply_settings()
	world_attached.emit(scene_root)


func detach() -> void:
	_disable_pipeline()
	if _attached_scene and _attached_scene.tree_exiting.is_connected(_on_attached_scene_exiting):
		_attached_scene.tree_exiting.disconnect(_on_attached_scene_exiting)
	_attached_scene = null
	_source_camera = null
	_spring_arm = null
	_bind_warned = false
	_root_3d_was_disabled = null
	_last_source_xform = Transform3D()
	_last_source_fov = -1.0


func get_gameplay_camera() -> Camera3D:
	## Active 3D camera for billboards, lock-on, and HUD (mirrors SubViewport when low-res is on).
	if PixelDioramaSettings.low_res_viewport_enabled:
		if is_instance_valid(_render_camera) and _render_camera.current:
			return _render_camera
		if is_instance_valid(_source_camera):
			return _source_camera
	var tree := get_tree()
	if tree == null:
		return null
	return tree.root.get_camera_3d()


## The internal resolution is expressed as an integer divisor of the window, not
## as an absolute size: SubViewportContainer.stretch drives the SubViewport size
## from the container, and any non-integer ratio would put the nearest-neighbour
## upscale on fractional pixel boundaries and shimmer.
func _apply_internal_size() -> void:
	if _viewport == null or _container == null:
		return
	if not PixelDioramaSettings.low_res_viewport_enabled:
		var window_height := 1080.0
		var tree := get_tree()
		if tree and tree.root:
			window_height = maxf(1.0, tree.root.get_visible_rect().size.y)
		PixelDioramaSettings.active_render_height = int(maxf(90.0, window_height))
		_container.texture_filter = (
			CanvasItem.TEXTURE_FILTER_NEAREST
			if PixelDioramaSettings.nearest_texture_filter
			else CanvasItem.TEXTURE_FILTER_LINEAR
		)
		return
	var target := PixelDioramaSettings.viewport_internal_size()
	# Godot 4.7+: SubViewport.size cannot change while container stretch is on.
	_container.stretch = false
	if PixelDioramaSettings.is_native_hd_preset():
		_viewport.size = target
		PixelDioramaSettings.active_render_height = target.y
		_container.stretch_shrink = 1
		_container.stretch = true
	else:
		var window_height := 1080.0
		var tree := get_tree()
		if tree and tree.root:
			window_height = maxf(1.0, tree.root.get_visible_rect().size.y)
		var shrink := maxi(1, int(round(window_height / float(maxi(90, target.y)))))
		_container.stretch_shrink = shrink
		PixelDioramaSettings.active_render_height = int(round(window_height / float(shrink)))
		_container.stretch = true
	_viewport.snap_2d_transforms_to_pixel = true
	_viewport.snap_2d_vertices_to_pixel = true
	_container.texture_filter = (
		CanvasItem.TEXTURE_FILTER_NEAREST
		if PixelDioramaSettings.nearest_texture_filter
		else CanvasItem.TEXTURE_FILTER_LINEAR
	)


func _enforce_native_viewport_size() -> void:
	if _viewport == null or _container == null:
		return
	var target := PixelDioramaSettings.viewport_internal_size()
	if _viewport.size != target:
		var was_stretch := _container.stretch
		_container.stretch = false
		_viewport.size = target
		PixelDioramaSettings.active_render_height = target.y
		_container.stretch = was_stretch


func _apply_screen_finish() -> void:
	if _container == null:
		return
	if not PixelDioramaSettings.screen_finish_enabled:
		_container.material = null
		return
	if _finish_material == null:
		_finish_material = PixelDioramaSettings.make_screen_finish_material()
	PixelDioramaSettings.apply_to_screen_finish(_finish_material)
	# Re-assert after the grade: applying a grade rebuilds every uniform from settings and would
	# otherwise silently clear a distress state the player is currently in.
	_finish_material.set_shader_parameter("distress", _distress)
	_container.material = _finish_material


func pulse_screen(kind: ScreenPulse, scale: float = 1.0) -> void:
	if _finish_material == null or not PixelDioramaSettings.screen_finish_enabled:
		return
	# The Accessibility page's "Screen Pulse" slider is applied here and nowhere else. It was
	# previously stored and displayed but never consulted, so full-screen damage and heal flashes
	# fired at full strength no matter where the player set it — and at zero it should not fire.
	var accessibility_scale := AccessibilitySettings.screen_pulse_scale()
	if accessibility_scale <= 0.0:
		return
	var tuning: Dictionary = PULSE_TUNING[kind]
	var peak := float(tuning.peak) * scale * accessibility_scale
	var decay := float(tuning.decay)
	var param: String = tuning.param
	_finish_material.set_shader_parameter("pulse_tint", tuning.tint)
	_finish_material.set_shader_parameter(param, peak)
	var tween := create_tween()
	tween.tween_method(
		func(v: float) -> void:
			if _finish_material:
				_finish_material.set_shader_parameter(param, v),
		peak,
		0.0,
		decay
	)


## Holds (or releases) the sustained low-health vignette.
##
## `CombatEvents.notify_health_ratio` has latched a low-health state since it was written, and
## dispatched `onLowHealth` for gear affixes to hook, but nothing ever showed the player anything —
## the only signal you were about to die was the health bar itself. This is the visual half.
##
## Ramping rather than snapping matters both ways: appearing instantly reads as a glitch, and
## clearing instantly on a heal robs the recovery of its moment. The release is quicker than the
## onset because relief should feel immediate where dread should creep.
func set_distress(active: bool, strength: float = 0.85) -> void:
	# Respects the Accessibility "Screen Pulse" slider. A player who set it to zero has asked for no
	# full-screen effects, and the health bar still carries the information.
	var scale := AccessibilitySettings.screen_pulse_scale()
	var target := (clampf(strength, 0.0, 1.0) * scale) if active else 0.0
	if is_equal_approx(target, _distress):
		return
	if _distress_tween and _distress_tween.is_valid():
		_distress_tween.kill()
	if _finish_material == null or not PixelDioramaSettings.screen_finish_enabled:
		_distress = target
		return
	var duration := 0.9 if active else 0.35
	_distress_tween = create_tween()
	_distress_tween.tween_method(
		func(v: float) -> void:
			_distress = v
			if _finish_material:
				_finish_material.set_shader_parameter("distress", v),
		_distress,
		target,
		duration
	)


## Drops the distress state immediately, without the release ramp. For scene changes, where there
## is no continuity to preserve and a fade would just bleed one screen into the next.
func clear_distress() -> void:
	if _distress_tween and _distress_tween.is_valid():
		_distress_tween.kill()
	_distress = 0.0
	if _finish_material:
		_finish_material.set_shader_parameter("distress", 0.0)


func pulse_damage_vignette(strength: float = 0.7) -> void:
	pulse_screen(ScreenPulse.DAMAGE, strength / float(PULSE_TUNING[ScreenPulse.DAMAGE].peak))


func _enable_pipeline() -> void:
	var root := get_tree().root
	if root == null:
		return
	root.scaling_3d_scale = 1.0
	if _root_3d_was_disabled == null:
		_root_3d_was_disabled = root.disable_3d
	root.disable_3d = true
	_pipeline_active = true
	_update_layer_visibility()
	if _source_camera and is_instance_valid(_source_camera):
		_source_camera.current = false
	_render_camera.current = true


func _disable_pipeline() -> void:
	var root := get_tree().root
	if root:
		root.scaling_3d_scale = 1.0
		if _root_3d_was_disabled != null:
			root.disable_3d = _root_3d_was_disabled
		var window_height := maxf(1.0, root.get_visible_rect().size.y)
		PixelDioramaSettings.active_render_height = int(maxf(90.0, window_height))
	if _render_camera:
		_render_camera.current = false
	if _source_camera and is_instance_valid(_source_camera):
		_source_camera.current = true
	_pipeline_active = false
	_update_layer_visibility()


func _bind_source_camera(scene_root: Node) -> void:
	_source_camera = null
	_spring_arm = null
	var player: Node = null
	var group_cam := scene_root.get_tree().get_first_node_in_group("pixel_render_source") as Camera3D
	if group_cam:
		_source_camera = group_cam
		_spring_arm = group_cam.get_parent() as SpringArm3D
	else:
		player = scene_root.get_tree().get_first_node_in_group("player")
		if player == null and scene_root.has_node("Player"):
			player = scene_root.get_node("Player")
		if player:
			_source_camera = (
				player.get_node_or_null("CameraPivot/SpringArm3D/Camera3D") as Camera3D
			)
			if _source_camera:
				_spring_arm = player.get_node_or_null("CameraPivot/SpringArm3D") as SpringArm3D
	if _source_camera == null:
		if player != null and not _bind_warned:
			_bind_warned = true
			push_warning("PixelDioramaViewport: no source camera in %s" % scene_root.name)
		return
	# A Camera3D's default cull mask is all twenty layers, the contour layer among them. With the
	# pipeline on it made no visible difference — the gameplay camera's output is covered by the
	# SubViewportContainer — but with Low-Res Viewport turned off in Advanced Pixel Options the
	# gameplay camera draws straight to the window, and a full-screen contour quad drawn by a camera
	# whose depth buffer it was never derived from is just a dark sheet over the game.
	_source_camera.cull_mask &= ~OUTLINE_LAYER_MASK
	if PixelDioramaSettings.low_res_viewport_enabled:
		_enable_pipeline()


func _on_root_size_changed() -> void:
	if PixelDioramaSettings.low_res_viewport_enabled:
		_apply_internal_size()
		if PixelDioramaSettings.is_native_hd_preset():
			_enforce_native_viewport_size()


func _on_attached_scene_exiting() -> void:
	detach()


func _on_root_child_entered(node: Node) -> void:
	if node == self:
		return
	if not PixelDioramaSettings.low_res_viewport_enabled:
		return
	if node is Window:
		return
	if node != get_tree().current_scene:
		return
	call_deferred("_try_auto_attach", node)


func _try_auto_attach(scene_root: Node) -> void:
	if not PixelDioramaSettings.low_res_viewport_enabled:
		return
	if scene_root != get_tree().current_scene:
		return
	if scene_root.is_in_group("pixel_viewport_exclude"):
		return
	attach_to_scene(scene_root)
