extends Node3D
## Planner decoration: a dead infected lying in its final death pose
## (ADR-0017). Its limbs and head can still be shot off in play; variants
## start with parts already missing.

const PHYSICS_POSE := preload("res://game/features/infected/decor_physics_pose.gd")
const CORPSE_GROUP := &"infected_corpse"
# Parts lost by each destruction level, cumulative (index = level).
const HUMANOID_LEVELS := [
	[], [&"forearm_r"], [&"arm_r"], [&"arm_r", &"forearm_l"], [&"arm_r", &"arm_l"],
	[&"arm_r", &"arm_l", &"shin_r"], [&"arm_r", &"arm_l", &"leg_r"], [&"arm_r", &"arm_l", &"leg_r", &"shin_l"],
	[&"arm_r", &"arm_l", &"leg_r", &"leg_l"], [&"arm_r", &"arm_l", &"leg_r", &"leg_l", &"head"],
]
const HORDE_LEVELS := 9
@export var physics_pose: Dictionary = {}
var _settling := false

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
## How wrecked the body is: 0 whole, higher levels cumulatively lose forearms, arms, shins, legs, head
## (Horde: tentacles one by one). Added to severed_parts.
@export var destruction := 0
@export var durability := 60.0

var parts: Node
## Set with the body: the hunger's corpse search reads it, like a killed infected's.
var body_visual: Node3D
var _physics: RefCounted


func _ready() -> void:
	_build()


# Number of destruction levels of this body (level 0 is whole).
func level_count() -> int:
	return (HORDE_LEVELS if _is_horde() else HUMANOID_LEVELS.size())


func _is_horde() -> bool:
	return visual_scene != null and visual_scene.resource_path.contains("Horde")


func _destroyed_parts() -> Array[StringName]:
	var result: Array[StringName] = []
	for part_name in severed_parts:
		result.append(StringName(part_name))
	var level := clampi(destruction, 0, level_count() - 1)
	if _is_horde():
		for index in level:
			result.append(StringName("tentacle_%d" % index))
	else:
		for part_name: StringName in HUMANOID_LEVELS[level]:
			if not result.has(part_name):
				result.append(part_name)
	return result


func _teardown() -> void:
	remove_from_group(CORPSE_GROUP)
	if _physics != null:
		_physics.call("dispose")
		_physics = null
	_release_meshes()
	if has_node("Body"):
		var body := get_node("Body")
		remove_child(body)
		body.free()
	if parts != null:
		remove_child(parts)
		parts.free()
		parts = null


func _build() -> void:
	if visual_scene == null:
		return
	var body := Node3D.new()
	body.name = "Body"
	body.scale = Vector3.ONE * visual_scale
	body.position.y = feet_offset * visual_scale
	add_child(body)
	body_visual = body
	add_to_group(CORPSE_GROUP)
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
	for part_name in _destroyed_parts():
		parts.sever(part_name, Vector3.ZERO, false)
	parts.enable_corpse_hitboxes()
	_restore_physics_pose()


func get_decor_pose() -> Dictionary:
	var result := {"seed": pose_seed, "pose": pose_variant, "facing": pose_facing, "destruction": destruction}
	if not physics_pose.is_empty():
		result["physics_v1"] = physics_pose.duplicate(true)
	return result


func configure_decor_pose(config: Dictionary) -> void:
	var level := maxi(0, int(config.get("destruction", destruction)))
	var rebuild := is_node_ready() and parts != null and level != destruction
	destruction = level
	physics_pose = config.get("physics_v1", {}).duplicate(true)
	pose_seed = maxi(0, int(config.get("seed", 1)))
	pose_variant = str(config.get("pose", "auto"))
	pose_facing = float(config.get("facing", float(posmod(pose_seed, 6283)) / 1000.0 - PI))
	if rebuild:
		# Fewer parts than before cannot be put back: build the body again.
		_teardown()
		_build()
	elif is_node_ready() and parts != null:
		var body := get_node("Body") as Node3D
		_apply_pose(body, body.get_child(0) as Node3D)
		_restore_physics_pose()


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


func is_dead() -> bool:
	return true


func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE:
		return
	_release_meshes()


# Release skin geometry while its per-instance wound materials still exist.
func _release_meshes() -> void:
	if parts != null:
		for entry: Dictionary in parts.get("_entries"):
			var mesh := entry.get("instance") as MeshInstance3D
			if is_instance_valid(mesh):
				mesh.mesh = null


func set_runtime_physics(enabled: bool) -> void:
	if enabled and not _settling and not physics_pose.is_empty():
		return
	if enabled and _physics == null and parts != null:
		_physics = preload("res://game/features/infected/corpse_physics.gd").new()
		_physics.call("setup", parts)
	if _physics != null:
		_physics.call("set_enabled", enabled)


func _restore_physics_pose() -> void:
	if physics_pose.is_empty() or parts == null:
		return
	PHYSICS_POSE.restore(get_node("Body"), parts.skeleton, physics_pose)
	_posed_bounds = POSES.bounds(parts, self)


func prepare_planner_physics() -> void:
	_settling = true
	set_runtime_physics(true)
	if _physics != null:
		_physics.call("launch", Vector3.ZERO)
	if _physics != null and _physics.get("_guard") != null:
		_physics.get("_guard").process_mode = Node.PROCESS_MODE_ALWAYS
		# The planner decides when the whole scene is supported and at rest.
		_physics.get("_guard").busy_limit_seconds = INF


func finalize_planner_physics() -> void:
	if _physics != null:
		_physics.call("freeze_pose")
		physics_pose = PHYSICS_POSE.capture(get_node("Body"), parts.skeleton)
		_posed_bounds = POSES.bounds(parts, self)
		_physics.call("dispose")
		_physics = null
	_settling = false
