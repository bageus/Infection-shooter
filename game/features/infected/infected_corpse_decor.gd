extends Node3D
## Planner decoration: a dead infected lying in its final death pose
## (ADR-0017). Its limbs and head can still be shot off in play; variants
## start with parts already missing.

const BODY_PARTS := preload("res://game/features/infected/body_parts.gd")

@export var visual_scene: PackedScene
## Optional clip set replacing the model's own clips (zombie/mutant GLBs).
@export var animation_library: AnimationLibrary
@export var visual_scale := 1.0
## Height of the model's feet below its origin, before scaling.
@export var feet_offset := 0.0
@export var pose_clip := "Death"
@export var severed_parts: PackedStringArray = PackedStringArray()
@export var durability := 60.0

var parts: Node


func _ready() -> void:
	if visual_scene == null:
		return
	var body := Node3D.new()
	body.name = "Body"
	body.scale = Vector3.ONE * visual_scale
	body.position.y = feet_offset * visual_scale
	add_child(body)
	var visual := visual_scene.instantiate() as Node3D
	body.add_child(visual)
	var players := visual.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		var player := players[0] as AnimationPlayer
		if animation_library != null:
			for library_name in player.get_animation_library_list():
				player.remove_animation_library(library_name)
			player.add_animation_library(&"", animation_library)
		if player.has_animation(pose_clip):
			player.play(pose_clip)
			player.seek(player.get_animation(pose_clip).length, true)
			player.pause()
	parts = BODY_PARTS.new()
	parts.name = "BodyParts"
	add_child(parts)
	if not parts.setup(self, body, durability):
		return
	for part_name in severed_parts:
		parts.sever(StringName(part_name), Vector3.ZERO, false)
	parts.enable_corpse_hitboxes()
