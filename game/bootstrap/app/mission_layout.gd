extends Node3D

const KEY := preload("res://game/bootstrap/app/mission_key.gd")
const WEAPON := preload("res://game/bootstrap/app/weapon_pickup.gd")
const DOOR := preload("res://game/presentation/office_floor/public/structural/wall_emergency_door.tscn")
const OPENING := Rect2(Vector2(-22, 10), Vector2(4, 14))
const LOWER_END_Y := -3.4


func setup(stage: Node3D) -> void:
	stage.get_node("Floor").call("set_stair_opening", OPENING)
	_cut_floor_collision(stage.get_node("FloorBody") as StaticBody3D)
	_build_staircase()
	_build_stairwell_walls()
	var door := DOOR.instantiate() as Node3D
	door.name = "LockedEmergencyDoor"
	stage.get_node("Structure").add_child(door)
	door.global_position = Vector3(-20, 0, 8.6)
	var key := KEY.new()
	key.name = "EmergencyKey"
	add_child(key)
	key.global_position = Vector3(20, 0.25, 15)
	spawn_weapon(3, Vector3(-20, 0.25, -15))


func spawn_weapon(index: int, world_position: Vector3) -> void:
	var item := WEAPON.new()
	item.weapon_index = index
	item.name = "DroppedLauncher" if index == 3 else "DroppedWeapon"
	add_child(item)
	item.global_position = Vector3(world_position.x, 0.25, world_position.z)
	item.set("_base_position", item.global_position)


func goal_reached(location: Vector3) -> bool:
	return location.x > OPENING.position.x and location.x < OPENING.end.x and location.z > 19 and location.z < OPENING.end.y and location.y < -1.3


func _cut_floor_collision(body: StaticBody3D) -> void:
	body.get_node("CollisionShape3D").set_deferred("disabled", true)
	# Four boxes leave exactly the same 4 x 14 m hole as the missing floor tiles.
	for region in [Rect2(-40, -30, 18, 60), Rect2(-18, -30, 58, 60), Rect2(-22, -30, 4, 40), Rect2(-22, 24, 4, 6)]:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(region.size.x, 0.2, region.size.y)
		shape.shape = box
		shape.position = Vector3(region.get_center().x, -0.1, region.get_center().y)
		body.add_child(shape)


func _build_staircase() -> void:
	var body := StaticBody3D.new()
	body.name = "WalkableStairRamp"
	body.collision_layer = 3
	add_child(body)
	var collision := CollisionShape3D.new()
	var ramp := BoxShape3D.new()
	ramp.size = Vector3(3.7, 0.2, sqrt(14.0 * 14.0 + LOWER_END_Y * LOWER_END_Y))
	collision.shape = ramp
	collision.position = Vector3(-20, LOWER_END_Y * 0.5 - 0.1, 17)
	collision.rotation.x = atan(-LOWER_END_Y / 14.0)
	body.add_child(collision)
	var treads := StandardMaterial3D.new()
	treads.albedo_color = Color(0.33, 0.37, 0.4)
	var edges := StandardMaterial3D.new()
	edges.albedo_color = Color(0.73, 0.58, 0.29)
	for step in 14:
		var z := 10.5 + step
		var elevation := LOWER_END_Y * (float(step) + 0.5) / 14.0
		_box(Vector3(-20, elevation - 0.11, z), Vector3(3.65, 0.15, 0.97), treads)
		_box(Vector3(-20, elevation - 0.03, z + 0.43), Vector3(3.65, 0.025, 0.08), edges)
	for side in [-1.0, 1.0]:
		for step in 14:
			var z := 10.5 + step
			var elevation := LOWER_END_Y * (float(step) + 0.5) / 14.0
			_box(Vector3(-20 + side * 1.83, elevation + 0.18, z), Vector3(0.05, 0.36, 0.97), edges)


func _build_stairwell_walls() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.35, 0.38, 0.42)
	# Side and end walls join the locked door, so the stairwell has one entrance.
	for x in [-22.0, -18.0]:
		_wall(Vector3(x, -0.95, 16.2), Vector3(0.16, 5.0, 15.8), material)
	_wall(Vector3(-20, -0.95, 24.1), Vector3(4.0, 5.0, 0.16), material)
	for x in [-21.58, -18.42]:
		_wall(Vector3(x, 1.5, 8.6), Vector3(0.84, 3.0, 0.25), material)


func _wall(at: Vector3, dimensions: Vector3, material: Material) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 3
	add_child(body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = dimensions
	shape.shape = box
	body.add_child(shape)
	body.position = at
	var panel := BoxMesh.new()
	panel.size = dimensions
	panel.material = material
	var visual := MeshInstance3D.new()
	visual.mesh = panel
	body.add_child(visual)


func _box(at: Vector3, dimensions: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	mesh.material = material
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.position = at
	add_child(visual)
