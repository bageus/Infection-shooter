extends SceneTree
## Costume skins: a Hunger, Brute or Revenant spawned with meta `skin` wears the matching skinned
## costume; "normal" wears none; the body wound skin ignores the costume; a severed limb takes its
## clothes along.
const SCENES := {
	"hunger": preload("res://game/features/infected/public/infected_hunger.tscn"),
	"brute": preload("res://game/features/infected/public/infected_brute.tscn"),
	"revenant": preload("res://game/features/infected/public/infected_revenant.tscn"),
}
const SKINS := ["normal", "no_tie", "janitor", "guard", "scientist", "hazmat"]
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	for label: String in SCENES:
		for skin: String in SKINS:
			await _skin(stage, SCENES[label], label, skin)
	await _severed(stage)
	stage.queue_free()
	for frame in 3:
		await process_frame
	print("Enemy costume tests: %d failures" % failures)
	quit(failures)


func _spawn(stage: Node3D, scene: PackedScene, skin: String) -> CharacterBody3D:
	var actor := scene.instantiate() as CharacterBody3D
	actor.set_meta(&"skin", skin)
	stage.add_child(actor)
	actor.set_physics_process(false)
	await process_frame
	return actor


func _skin(stage: Node3D, scene: PackedScene, label: String, skin: String) -> void:
	var actor := await _spawn(stage, scene, skin)
	var skeleton := actor.body_visual.find_child("Skeleton3D", true, false) as Skeleton3D
	var costume := skeleton.get_node_or_null("Costume") as MeshInstance3D
	if skin == "normal":
		_check(costume == null, "%s normal wears no costume" % label)
	else:
		_check(costume != null and costume.mesh.get_surface_count() >= 1 and costume.skin != null, "%s %s wears a skinned costume" % [label, skin])
		if costume != null:
			var arrays := costume.mesh.surface_get_arrays(0)
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			_check(bones.size() == (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() * 4 and Array(bones).max() < skeleton.get_bone_count(), "%s %s costume bones fit the skeleton" % [label, skin])
	if actor._parts != null:
		var covered := 0
		for node in skeleton.find_children("*", "MeshInstance3D", true, false):
			covered += 1 if (node as MeshInstance3D).get_meta(&"body_part_cap", false) else 0
		_check(covered == (0 if skin == "normal" else 1), "%s %s: the costume stays out of the wound skin" % [label, skin])
	actor.queue_free()
	await process_frame


func _severed(stage: Node3D) -> void:
	var actor := await _spawn(stage, SCENES["hunger"], "guard")
	if actor._parts == null:
		_check(false, "hunger has body parts")
		return
	var piece: RigidBody3D = actor._parts.sever(&"arm_l", Vector3.LEFT)
	_check(piece != null, "the arm comes off")
	if piece != null:
		var meshes := piece.find_children("*", "MeshInstance3D", true, false)
		_check(meshes.size() == 2, "the severed arm carries its sleeve (%d meshes)" % meshes.size())
		piece.queue_free()
	actor.queue_free()
	await process_frame


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
