extends SceneTree
## Runtime checks for destruction debris: collision layers, wall blocking,
## contactless characters, lifecycle (fade, budget), inherited motion, prop
## shudder and full breakage of environment props and physical props.

const FRAGMENT := preload("res://game/presentation/office_floor/environment_fragment.gd")
const DEBRIS := preload("res://game/presentation/office_floor/debris_lifecycle.gd")
const PROP_SCENE := preload("res://game/presentation/office_floor/public/props/environment_prop.tscn")
const CABINET := "res://models/objects/enviroments/03/03_file_cabinet_largest.glb"
const PHYSICAL := preload("res://game/presentation/office_floor/physical_prop.gd")

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	_add_floor(stage)
	await _test_fragment_layers(stage)
	await _test_fragment_blocked_by_wall(stage)
	await _test_fragment_ignores_characters(stage)
	await _test_expire_fades_and_frees(stage)
	await _test_budget(stage)
	await _test_physical_prop_break(stage)
	await _test_environment_prop(stage)
	stage.queue_free()
	await process_frame
	print("Debris tests: %d failure(s)." % failures)
	quit(failures)


func _add_floor(stage: Node3D) -> void:
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 2
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 1, 40)
	shape.shape = box
	floor_body.add_child(shape)
	stage.add_child(floor_body)
	floor_body.position = Vector3(0, -0.5, 0)


func _fragment(stage: Node3D, at: Vector3, kickable := false) -> RigidBody3D:
	var piece := RigidBody3D.new()
	piece.set_script(FRAGMENT)
	piece.set("kickable", kickable)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.2, 0.2, 0.2)
	shape.shape = box
	piece.add_child(shape)
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	piece.add_child(mesh)
	stage.add_child(piece)
	piece.global_position = at
	return piece


func _ray(stage: Node3D, from: Vector3, to: Vector3, mask: int) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, mask)
	return stage.get_world_3d().direct_space_state.intersect_ray(query)


func _test_fragment_layers(stage: Node3D) -> void:
	var piece := _fragment(stage, Vector3(0, 0.5, 0))
	await physics_frame
	_expect(piece.collision_layer == 4, "Fragments live on the bullet-visible layer 3.")
	_expect(piece.collision_mask == 3, "Fragments collide with floor and walls/props only.")
	await physics_frame
	var hit := _ray(stage, Vector3(2, piece.global_position.y, 0), Vector3(-2, piece.global_position.y, 0), 7)
	_expect(hit.has("collider") and hit["collider"] == piece, "Bullets (mask 7) can hit a fragment.")
	var player_mask_hit := _ray(stage, Vector3(2, piece.global_position.y, 0), Vector3(-2, piece.global_position.y, 0), 3)
	_expect(not player_mask_hit.has("collider") or player_mask_hit["collider"] != piece, "Characters (mask 3) do not see fragments.")
	piece.queue_free()
	await process_frame


func _test_fragment_blocked_by_wall(stage: Node3D) -> void:
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.3, 4, 10)
	shape.shape = box
	wall.add_child(shape)
	stage.add_child(wall)
	wall.position = Vector3(3, 2, 0)
	var piece := _fragment(stage, Vector3(1.0, 0.5, 0))
	await physics_frame
	piece.linear_velocity = Vector3(30, 0, 0)
	await create_timer(0.8).timeout
	_expect(piece.global_position.x < 2.9, "A fast fragment is stopped by a wall (x=%.2f)." % piece.global_position.x)
	piece.queue_free()
	wall.queue_free()
	await process_frame


func _test_fragment_ignores_characters(stage: Node3D) -> void:
	var character := CharacterBody3D.new()
	character.collision_layer = 1
	character.add_to_group("player")
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	shape.shape = capsule
	character.add_child(shape)
	stage.add_child(character)
	character.global_position = Vector3(-6, 1.0, 0)
	var piece := _fragment(stage, Vector3(-6, 0.6, 0))
	await physics_frame
	await create_timer(0.5).timeout
	_expect(piece.get_collision_exceptions().has(character), "Fragments ignore the player explicitly.")
	piece.queue_free()
	character.queue_free()
	await process_frame


func _test_expire_fades_and_frees(stage: Node3D) -> void:
	var piece := _fragment(stage, Vector3(5, 0.5, 5))
	await physics_frame
	piece.call("expire")
	_expect(piece.collision_layer == 0, "A fading fragment can no longer be hit.")
	_expect(DEBRIS.is_fading(piece), "A fading fragment is flagged.")
	await create_timer(DEBRIS.FADE_SECONDS + 0.3).timeout
	_expect(not is_instance_valid(piece) or piece.is_queued_for_deletion(), "An expired fragment is freed after shrinking.")
	await process_frame


func _test_budget(stage: Node3D) -> void:
	for i in 55:
		_fragment(stage, Vector3(8 + (i % 8) * 0.5, 0.5 + i * 0.01, -8 + (i / 8) * 0.5))
	await physics_frame
	var live := 0
	for piece in get_nodes_in_group(FRAGMENT.GROUP):
		if not DEBRIS.is_fading(piece):
			live += 1
	_expect(live <= FRAGMENT.MAX_FRAGMENTS, "Live debris stays within the budget (%d)." % live)
	await create_timer(DEBRIS.FAST_FADE_SECONDS + 0.3).timeout
	for piece in get_nodes_in_group(FRAGMENT.GROUP):
		piece.queue_free()
	await process_frame


func _test_physical_prop_break(stage: Node3D) -> void:
	var effects := Node3D.new()
	stage.add_child(effects)
	var prop := RigidBody3D.new()
	prop.set_script(PHYSICAL)
	prop.name = "Crate"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.6, 0.6, 0.6)
	shape.shape = box
	prop.add_child(shape)
	var mesh := MeshInstance3D.new()
	mesh.name = "Visual"
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(0.6, 0.6, 0.6)
	mesh.mesh = box_mesh
	prop.add_child(mesh)
	stage.add_child(prop)
	prop.global_position = Vector3(-10, 0.4, 8)
	prop.call("configure_world", effects, null)
	await physics_frame
	prop.call("take_melee_hit", 5000.0, prop.global_position, Vector3.FORWARD)
	await physics_frame
	var chunks := effects.get_children().filter(func(n: Node) -> bool: return n is RigidBody3D)
	_expect(chunks.size() >= 4, "Breaking a physical prop spawns debris (%d)." % chunks.size())
	await create_timer(1.5).timeout
	var resting := 0
	for chunk in chunks:
		if is_instance_valid(chunk) and (chunk as Node3D).global_position.y > -0.5:
			resting += 1
	_expect(resting == chunks.size(), "Physical prop shards rest on the floor instead of falling through.")
	for chunk in chunks:
		if is_instance_valid(chunk):
			chunk.queue_free()
	effects.queue_free()
	await process_frame


func _test_environment_prop(stage: Node3D) -> void:
	if not ResourceLoader.exists(CABINET):
		return
	var effects := Node3D.new()
	stage.add_child(effects)
	var prop := PROP_SCENE.instantiate() as RigidBody3D
	prop.set("model_path", CABINET)
	prop.collision_mask = 3 # same as the office layout props
	stage.add_child(prop)
	prop.global_position = Vector3(12, 0.0, 10)
	prop.call("configure_world", effects, null)
	await physics_frame
	await physics_frame
	var rest := prop.global_transform
	prop.call("take_projectile_hit", 1.0, prop.global_position + Vector3(0, 1, 0), Vector3.UP, Vector3.FORWARD, "SHOTGUN")
	await create_timer(1.5).timeout
	_expect(prop.global_position.distance_to(rest.origin) < 1.5, "A shot prop does not drift away (moved %.2f, freeze=%s, mass=%.1f)." % [prop.global_position.distance_to(rest.origin), prop.freeze, prop.mass])
	var before := effects.get_child_count()
	for i in 80:
		if not is_instance_valid(prop) or bool(prop.get("_broken")):
			break
		prop.call("take_projectile_hit", 400.0, prop.global_position + Vector3(0, 1, 0), Vector3.UP, Vector3.FORWARD, "GRENADE")
		await create_timer(0.1).timeout
	await create_timer(0.5).timeout
	_expect(bool(prop.get("_broken")), "Repeated heavy damage fully breaks the cabinet.")
	_expect(effects.get_child_count() > before, "Breaking spawns fragments or dust in the effects root.")
	for child in effects.get_children():
		child.queue_free()
	prop.queue_free()
	effects.queue_free()
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
