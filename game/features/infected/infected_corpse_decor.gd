extends Node3D
## Planner decoration: a dead infected lying in its final death pose
## (ADR-0017). Its limbs and head can still be shot off in play; variants
## start with parts already missing.

const POSES := preload("res://game/features/infected/decor_pose.gd")
@export var pose_seed := 0
@export var pose_variant := "legacy"
@export var pose_facing := 0.0
var _posed_bounds := AABB()
const BODY_PARTS := preload("res://game/features/infected/body_parts.gd")

@export var visual_scene: PackedScene
## Optional authored clip set.
@export var animation_library: AnimationLibrary
@export var visual_scale := 1.0
## Height of the model's feet below its origin, before scaling.
@export var feet_offset := 0.0
@export var pose_clip := "Death"
@export var severed_parts: PackedStringArray = PackedStringArray()
@export var durability := 60.0

var parts: Node
var _physics: RefCounted


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
	if pose_variant != "legacy":
		for animator in players:
			animator.free()
	parts = BODY_PARTS.new()
	parts.name = "BodyParts"
	add_child(parts)
	if not parts.setup(self, body, durability):
		return
	if pose_variant != "legacy":
		_apply_pose(body, visual)
	for part_name in severed_parts:
		parts.sever(StringName(part_name), Vector3.ZERO, false)
	parts.enable_corpse_hitboxes()


func get_decor_pose() -> Dictionary:
	return {"seed": pose_seed, "pose": pose_variant, "facing": pose_facing}


func configure_decor_pose(config: Dictionary) -> void:
	pose_seed = maxi(0, int(config.get("seed", 1)))
	pose_variant = str(config.get("pose", "auto"))
	pose_facing = float(config.get("facing", float(posmod(pose_seed, 6283)) / 1000.0 - PI))
	if is_node_ready() and parts != null:
		var body := get_node("Body") as Node3D
		_apply_pose(body, body.get_child(0) as Node3D)


func _apply_pose(body: Node3D, visual: Node3D) -> void:
	for animator in visual.find_children("*", "AnimationPlayer", true, false):
		animator.pause()
		animator.active = false
	POSES.apply(body, parts.skeleton, get_decor_pose())
	_posed_bounds = POSES.bounds(parts, self)
	body.position.y -= _posed_bounds.position.y
	_posed_bounds.position.y = 0.0


func get_planner_bounds() -> AABB:
	return _posed_bounds


func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE:
		return
	# Release skin geometry while its per-instance wound materials still exist.
	if parts != null:
		for entry: Dictionary in parts.get("_entries"):
			var mesh := entry.get("instance") as MeshInstance3D
			if is_instance_valid(mesh):
				mesh.mesh = null


func set_runtime_physics(enabled: bool) -> void:
	if enabled and _physics == null and parts != null:
		_physics = preload("res://game/features/infected/corpse_physics.gd").new()
		_physics.call("setup", parts)
	if _physics != null:
		_physics.call("set_enabled", enabled)
