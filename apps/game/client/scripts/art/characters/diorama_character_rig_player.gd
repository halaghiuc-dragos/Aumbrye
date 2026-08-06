extends Node3D

## Reference player rig for authoring AnimationPlayer clips in-editor.

const CharacterSkin := preload("res://scripts/art/characters/diorama_character_skin.gd")
const AnimLibrary := preload("res://scripts/art/characters/diorama_anim_library.gd")
const PixelStyle := preload("res://scripts/art/style/pixel_diorama_style.gd")


func _ready() -> void:
	var facing := get_node_or_null("Facing") as Node3D
	if facing == null:
		facing = Node3D.new()
		facing.name = "Facing"
		add_child(facing)
	var visual := CharacterSkin.build_player_body(facing, -1)
	_attach_animation_player(visual)


func _attach_animation_player(visual: Node3D) -> void:
	var anim_player := get_node_or_null("AnimationPlayer") as AnimationPlayer
	if anim_player == null:
		anim_player = AnimationPlayer.new()
		anim_player.name = "AnimationPlayer"
		visual.add_child(anim_player)
	elif anim_player.get_parent() != visual:
		anim_player.reparent(visual)
	anim_player.root_node = NodePath("..")
	var rest_pose := CharacterSkin.collect_rest_pose(visual)
	if rest_pose.is_empty():
		return
	for lib_name in anim_player.get_animation_library_list():
		anim_player.remove_animation_library(lib_name)
	var library := AnimLibrary.build_library(rest_pose, "", "player")
	anim_player.add_animation_library("", library)
