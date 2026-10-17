extends SceneTree
## Every catalog wall prop loses its real backing; adjacent supports stay intact.
const PROP := preload("res://game/presentation/office_floor/public/props/environment_prop.tscn")
const BATHROOM := preload("res://game/presentation/office_floor/public/props/bathroom_fixture.tscn")
const MOUNTS := preload("res://game/presentation/office_floor/wall_mount_models.gd")
const PARTITION := "res://models/objects/enviroments/01/01_wood_slat_partition_destructible.glb"
const MODELS := "res://models/objects/enviroments/"
var failures := 0
var stage: Node3D

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	_floor()
	var paths: Array[String] = []
	_models(MODELS, paths)
	paths.sort()
	_expect(paths.size() >= 25, "All wall-mounted catalog models are covered")
	for path in paths:
		await _mount(path)
	stage.queue_free()
	await process_frame
	await process_frame
	print("Wall mount support tests: %d models, %d failures" % [paths.size(), failures])
	quit(1 if failures else 0)

func _mount(path: String) -> void:
	var partition := _prop(PARTITION)
	partition.position = Vector3(8, .02, 8)
	partition.rotation.y = .63
	partition.scale = Vector3.ONE * 1.15
	var bounds := _bounds(partition, partition)
	var props: Array[RigidBody3D] = []
	var heights: Array[float] = []
	for side in [-1.0, 1.0]:
		var prop := _prop(path)
		# Use the same back-plane rule as planner placement, including shifted model pivots.
		prop.global_basis = partition.global_basis.orthonormalized() * Basis(Vector3.UP, PI if side < 0.0 else 0.0)
		var item := _bounds(prop, partition)
		var target := bounds.get_center()
		target.y = bounds.get_center().y
		var back := item.position.z if side > 0 else item.end.z
		target.z = (bounds.end.z if side > 0 else bounds.position.z) + side * .005
		var shift := Vector3(target.x - item.get_center().x, target.y - item.get_center().y, target.z - back)
		prop.global_position += partition.global_basis * shift
		props.append(prop)
		heights.append(prop.global_position.y)
	# An unrelated mount beyond the end and one on a parallel neighbouring wall.
	var neighbor := _prop(path)
	neighbor.global_transform = props[0].global_transform
	neighbor.global_position += partition.global_basis.z * -1.0
	var end_mount := _prop(path)
	end_mount.global_transform = props[1].global_transform
	end_mount.global_position += partition.global_basis.x * (bounds.size.x + 1.0)
	await _settle(3)
	for prop in props:
		_expect(prop.freeze, path + ": starts attached")
	partition.call("take_projectile_hit", 1.0, partition.global_position, Vector3.BACK, Vector3.FORWARD, "PISTOL")
	await _settle(2)
	for prop in props:
		_expect(prop.freeze, path + ": remains attached while the partition is intact")
	var weapon := "UZI" if "wall_TV" in path or "wall_clock" in path or "capboard" in path else "GRENADE"
	for shot in 12:
		if bool(partition.get("_broken")):
			break
		partition.call("take_projectile_hit", 1000.0, partition.global_position, Vector3.BACK, Vector3.FORWARD, weapon)
		await _settle(2)
	await _settle(3)
	_expect(bool(partition.get("_broken")), "Backing partition really breaks")
	for prop in props:
		_expect(not prop.freeze and not prop.sleeping, path + ": loses its mount on either face")
	_expect(neighbor.freeze and end_mount.freeze, path + ": unrelated mounts do not fall")
	await _settle(30)
	for i in props.size():
		_expect(is_instance_valid(props[i]) and props[i].global_position.y < heights[i] - .15, path + ": falls under real gravity")
		# Duplicate support notifications cannot add another impulse or disable damage.
		if is_instance_valid(props[i]):
			var speed := props[i].linear_velocity
			props[i].call("fall_off_with_glass")
			_expect(props[i].linear_velocity.is_equal_approx(speed), path + ": repeated detach is harmless")
	for prop in props + [partition, neighbor, end_mount]:
		if is_instance_valid(prop):
			prop.queue_free()
	await _settle(2)

func _prop(path: String) -> RigidBody3D:
	var scene := BATHROOM if "wall_urinal" in path or "wall_hand_dryer" in path else PROP
	var prop := scene.instantiate() as RigidBody3D
	prop.set("model_path", path)
	prop.collision_mask = 3
	stage.add_child(prop)
	# No debris container: this verifies the support command, not a projectile blast.
	return prop

func _bounds(prop: Node3D, frame: Node3D) -> AABB:
	var result := AABB()
	var inverse := frame.global_transform.affine_inverse()
	for mesh: MeshInstance3D in prop.get("_shape_meshes"):
		var box: AABB = (inverse * mesh.global_transform) * mesh.get_aabb()
		result = box if result.size == Vector3.ZERO else result.merge(box)
	return result

func _floor() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 2
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(100, .2, 100)
	collision.shape = shape
	body.add_child(collision)
	stage.add_child(body)
	body.position.y = -.1

func _models(path: String, paths: Array[String]) -> void:
	for file in DirAccess.get_files_at(path):
		if file.ends_with(".glb") and MOUNTS.contains(path + file):
			paths.append(path + file)
	for directory in DirAccess.get_directories_at(path):
		_models(path + directory + "/", paths)

func _settle(ticks: int) -> void:
	for i in ticks:
		await physics_frame
	await process_frame

func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
