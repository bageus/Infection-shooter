extends SceneTree
## A bucket with a mop splits into two objects on its first hit or touch; the mop becomes its own prop.
const PROP := preload("res://game/presentation/office_floor/public/props/environment_prop.tscn")
const DAMAGE := preload("res://game/presentation/office_floor/environment_damage.gd")
const BUCKET := "res://models/objects/enviroments/09/09_bucket_with_mop.glb"
const MOP := "res://models/objects/enviroments/09/09_mop.glb"
var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	await _hit_splits(stage)
	await _touch_splits(stage)
	await _other_props_stay_whole(stage)
	stage.free()
	await process_frame
	print("Bucket mop split tests: %d failure(s)." % failures)
	quit(failures)


func _spawn(stage: Node3D, model: String, at: Vector3) -> RigidBody3D:
	var prop := PROP.instantiate() as RigidBody3D
	prop.model_path = model
	prop.position = at
	stage.add_child(prop)
	return prop


func _mops(stage: Node3D) -> Array:
	var found := []
	for child in stage.get_children():
		if child is RigidBody3D and child.model_path == MOP:
			found.append(child)
	return found


func _mop_hidden(bucket: RigidBody3D) -> bool:
	var mop := DAMAGE.find_named(bucket.get("_visual"), "Mop") as Node3D
	return mop != null and not mop.visible


func _hit_splits(stage: Node3D) -> void:
	var bucket := _spawn(stage, BUCKET, Vector3(0, 0.5, 0))
	await process_frame
	bucket.take_melee_hit(10.0, bucket.global_position, Vector3.FORWARD)
	await process_frame
	await process_frame
	_expect(_mops(stage).size() == 1, "A melee hit releases exactly one mop")
	_expect(_mop_hidden(bucket), "The bucket hides its own mop once it splits")
	bucket.take_melee_hit(10.0, bucket.global_position, Vector3.FORWARD)
	await process_frame
	await process_frame
	_expect(_mops(stage).size() == 1, "Further hits do not release a second mop")
	for mop in _mops(stage):
		mop.free()
	bucket.free()


func _touch_splits(stage: Node3D) -> void:
	var bucket := _spawn(stage, BUCKET, Vector3(5, 0.5, 0))
	await process_frame
	bucket.push_from_character(bucket.global_position + Vector3(-1, 0, 0), Vector3(2, 0, 0), 1.0)
	await process_frame
	await process_frame
	_expect(_mops(stage).size() == 1, "Touching the bucket releases the mop")
	for mop in _mops(stage):
		mop.free()
	bucket.free()


func _other_props_stay_whole(stage: Node3D) -> void:
	var mug := _spawn(stage, "res://models/objects/enviroments/09/09_bucket.glb", Vector3(10, 0.5, 0))
	await process_frame
	mug.take_melee_hit(10.0, mug.global_position, Vector3.FORWARD)
	mug.push_from_character(mug.global_position + Vector3(-1, 0, 0), Vector3(2, 0, 0), 1.0)
	await process_frame
	await process_frame
	_expect(_mops(stage).is_empty(), "Other props never release a mop")
	mug.free()


func _expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
