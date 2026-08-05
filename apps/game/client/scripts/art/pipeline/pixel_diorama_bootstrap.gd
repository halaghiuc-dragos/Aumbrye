class_name PixelDioramaBootstrap
extends RefCounted

## The one call every playable scene makes to enter the pixel-diorama pipeline.
##
## Replaces the load/apply/attach sequence that used to be copy-pasted into each
## scene root. Use attach_deferred() from _ready() so the player camera exists
## before the render camera binds to it.


## Boot-time settings load, before any scene exists.
static func prime() -> void:
	PixelDioramaSettings.load_from_save()
	PixelDioramaSettings.apply_rendering_project_settings()


static func attach(scene_root: Node) -> void:
	if scene_root == null:
		return
	prime()
	PixelDioramaSettings.apply_to_scene(scene_root)
	PixelDioramaViewport.attach_to_scene(scene_root)


static func attach_deferred(scene_root: Node) -> void:
	if scene_root == null:
		return
	prime()
	PixelDioramaViewport.call_deferred("bootstrap_scene", scene_root)


## Re-applies materials, environment, and shadow tuning without rebinding the
## camera. Use after a scene spawns geometry at runtime (procgen rooms, waves).
static func refresh(scene_root: Node) -> void:
	if scene_root == null:
		return
	PixelDioramaSettings.apply_to_scene(scene_root)
