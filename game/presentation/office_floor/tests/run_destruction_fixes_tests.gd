extends SceneTree
## Open glass door shards, cooler bottle burst, and blood marks on panes.

const PROP := preload("res://game/presentation/office_floor/public/props/environment_prop.tscn")
const DOOR := preload("res://game/presentation/office_floor/public/structural/sliding_glass_door.tscn")
const WALL := preload("res://game/presentation/office_floor/public/structural/glass_wall_full.tscn")
const IMPACTS := preload("res://game/features/combat/public/impact_effects.gd")
var failures := 0
var stage: Node3D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	await _open_door()
	await _cooler()
	await _blood_on_glass()
	stage.queue_free()
	await process_frame
	print("Destruction fix tests: %d failure(s)." % failures)
	quit(failures)


func _open_door() -> void:
	var door := DOOR.instantiate() as Node3D
	stage.add_child(door)
	door.position = Vector3(0, 0, 20)
	var effects := Node3D.new()
	stage.add_child(effects)
	var pane: StaticBody3D = door.get_node("GlassBody")
	pane.call("configure_world", effects, null)
	var controller: Node = door.get_node("DoorController")
	controller.set("_swing_side", 1.0)
	await process_frame
	var closed_gap := _gap(door, pane)
	controller.set("_open_amount", 1.0)
	controller.call("_update_door_visuals", Vector3(0, 0, 1))
	await process_frame
	var open_gap := _gap(door, pane)
	_check(absf(open_gap - closed_gap) < 0.1, "Shards keep their offset to the glass when the door opens (%.2f closed, %.2f open)" % [closed_gap, open_gap])


func _gap(door: Node3D, pane: StaticBody3D) -> float:
	var visual: Node3D = door.get_node("Visual")
	var shards: Node3D = load("res://game/presentation/office_floor/environment_damage.gd").find_named(visual, "Glass_Shards")
	var glass: MeshInstance3D = pane.get("_glass_nodes")[0]
	if shards == null or glass == null:
		return 99.0
	var glass_center := (glass.global_transform * glass.get_aabb()).get_center()
	var shard_center := Vector3.ZERO
	var meshes := shards.find_children("*", "MeshInstance3D", true, false)
	for mesh: MeshInstance3D in meshes:
		shard_center += (mesh.global_transform * mesh.get_aabb()).get_center()
	shard_center /= maxf(meshes.size(), 1)
	return glass_center.distance_to(shard_center)


func _cooler() -> void:
	var effects := Node3D.new()
	stage.add_child(effects)
	var prop: RigidBody3D = PROP.instantiate()
	prop.set("model_path", "res://models/objects/enviroments/02/02_water_cooler_bottle_attached_destructible.glb")
	stage.add_child(prop)
	prop.position = Vector3(30, 0.02, 0)
	prop.call("configure_world", effects, null)
	await physics_frame
	var meshes: Array = prop.get("_shape_meshes")
	var bottle := preload("res://game/presentation/office_floor/water_bottle_burst.gd").find_bottle(meshes)
	_check(bottle >= 0, "Cooler bottle is found by its PET material")
	if bottle < 0:
		return
	var mesh: MeshInstance3D = meshes[bottle]
	var position := mesh.global_transform * mesh.get_aabb().get_center()
	prop.call("take_projectile_hit_at_shape", 28.0, position, Vector3.BACK, Vector3.FORWARD, "AK", bottle)
	await physics_frame
	_check(not mesh.visible, "Shot bottle bursts instead of dropping off")
	_check(effects.get_node_or_null("BottleSplash") != null and effects.get_node_or_null("WaterPuddle") != null, "Burst bottle splashes and leaves a puddle")
	_check(not bool(prop.get("_broken")) and prop.get_child_count() > 0 and prop.global_position.distance_to(Vector3(30, 0.02, 0)) < 0.3, "The cooler body stays standing")
	prop.queue_free()


func _blood_on_glass() -> void:
	var wall := WALL.instantiate() as Node3D
	stage.add_child(wall)
	wall.position = Vector3(0, 0, 40)
	await physics_frame
	var glass: MeshInstance3D
	for mesh: MeshInstance3D in wall.find_children("*", "MeshInstance3D", true, false):
		if "glass" in mesh.name.to_lower() and mesh.visible and mesh.mesh != null:
			glass = mesh
			break
	_check(glass != null, "Glass wall has a pane mesh")
	if glass == null:
		return
	var stamp := preload("res://game/core/vfx/public/surface_stamp.gd")
	_check(stamp.is_glass(glass), "Pane is recognised as glass")
	var center := glass.global_transform * glass.get_aabb().get_center()
	var normal := glass.global_basis.z.normalized()
	var projector := Transform3D(Basis(glass.global_basis.x.normalized(), glass.global_basis.y.normalized(), normal), center + normal * 0.2)
	var mesh := stamp.build(glass, Transform3D(Basis(projector.basis.x, -projector.basis.z, projector.basis.y), center + normal * 0.0), Vector2(0.5, 0.5), 0.3)
	_check(mesh != null and mesh.get_surface_count() > 0, "Blood can be projected on the pane")


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + label)
	print(("PASS: " if condition else "FAIL: ") + label)
