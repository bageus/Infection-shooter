extends SceneTree
## The hero and infected get a soft blob under their feet only while real shadows are off.
const BLOB := preload("res://game/core/vfx/public/character_blob_shadow.gd")
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	BLOB.set_shadows_allowed(self, false)
	BLOB.track(self)
	var stage := Node3D.new()
	root.add_child(stage)
	var hero := _character(stage, &"player")
	var enemy := _character(stage, &"infected")
	var prop := Node3D.new()
	prop.add_to_group(&"infected")
	stage.add_child(prop)
	await process_frame
	await process_frame
	var blob := enemy.get_node_or_null("BlobShadow") as MeshInstance3D
	_check(hero.has_node("BlobShadow") and blob != null, "Hero and infected both get a blob")
	_check(not prop.has_node("BlobShadow"), "A node that is not a character body gets none")
	if blob != null:
		_check(blob.visible, "The blob shows while real shadows are off")
		_check(is_equal_approx(blob.global_position.y, 0.02), "The blob lies just above the capsule's lowest point (%s)" % blob.global_position.y)
		_check(is_equal_approx(blob.scale.x, 0.45 * BLOB.SPAN), "The blob spans the capsule radius")
		BLOB.set_shadows_allowed(self, true)
		_check(not blob.visible, "Real shadows on hide every blob")
		BLOB.set_shadows_allowed(self, false)
	_check(not BLOB.attach(enemy), "A character never gets a second blob")
	enemy.emit_signal(&"blood_death", Vector3.ZERO, [], 0)
	await process_frame
	_check(not is_instance_valid(blob) or blob.is_queued_for_deletion(), "A dying enemy loses its blob")
	stage.queue_free()
	await process_frame
	print("Character blob shadow tests: %d failures" % failures)
	quit(0 if failures == 0 else 1)


func _character(stage: Node3D, group: StringName) -> CharacterBody3D:
	var body := CharacterBody3D.new()
	body.set_script(preload("res://game/core/vfx/tests/blob_shadow_body.gd"))
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.45
	capsule.height = 1.85
	shape.shape = capsule
	body.add_child(shape)
	body.position = Vector3(0, 0.925, 0)
	body.add_to_group(group)
	stage.add_child(body)
	return body


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
