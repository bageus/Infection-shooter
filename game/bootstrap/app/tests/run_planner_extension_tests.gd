extends SceneTree
const MAIN := preload("res://game/bootstrap/app/main.tscn")
const CORPSE := preload("res://game/features/infected/public/decor/corpse_hunger.tscn")
const HORDE := preload("res://game/features/infected/public/decor/corpse_horde.tscn")
const PART := preload("res://game/features/infected/public/decor/part_hunger_head.tscn")
const PREFS := preload("res://game/bootstrap/app/menu/menu_preferences.gd")
var failures := 0
var stage: Node3D

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	stage = MAIN.instantiate()
	root.add_child(stage)
	current_scene = stage
	(stage.get_node("Gameplay/Enemies") as Node).process_mode = Node.PROCESS_MODE_DISABLED
	await process_frame
	var player: Node3D = stage.get("player")
	player.set_physics_process(false)
	var planner: Node = stage.get("planning_mode")
	var catalog = planner.get("catalog")
	_check(catalog.group_catalogs["13"].size() == 10, "All ten wall objects are in group 13")
	var wall = catalog.call("_instantiate_asset", "res://models/objects/enviroments/13/13_wall_cafeteria.glb")
	stage.add_child(wall)
	_check(wall.get_meta("planning_wall_mount", false) and wall.freeze, "Group 13 stays attached to wall")
	_snap(catalog)
	await _wall_drag(planner, catalog)
	await _particles(catalog)
	await _corpse()
	await _aim(player)
	_installed_lamps(planner)
	stage.queue_free()
	await process_frame
	await create_timer(.2).timeout
	print("Planner extension tests: %d failures" % failures)
	quit(failures)

func _snap(catalog: RefCounted) -> void:
	var path := "res://models/objects/enviroments/05/05_wall_TV_frameless_destructible.glb"
	var first: Node3D = catalog.call("_instantiate_asset", path)
	var second: Node3D = catalog.call("_instantiate_asset", path)
	stage.add_child(first)
	stage.add_child(second)
	first.position = Vector3(25, 3, 0)
	second.position = first.position
	var a: Dictionary = first.call("get_display_edges")
	var neighbors: Array[Dictionary] = [a]
	var size: Vector2 = a["size"]
	var frame: Transform3D = a["frame"]
	for axis in [Vector3.RIGHT, Vector3.UP]:
		var span := size.x if axis == Vector3.RIGHT else size.y
		second.global_position = first.global_position + frame.basis * axis * (span + .07)
		second.call("snap_display_edges", neighbors)
		var b: Transform3D = second.call("get_display_edges")["frame"]
		_check((frame.affine_inverse() * b.origin).is_equal_approx(axis * span), "TV snaps exactly to horizontal/vertical edge")
	second.position.z += .3
	var before := second.position
	second.call("snap_display_edges", neighbors)
	_check(second.position.is_equal_approx(before), "TV does not snap across wall planes")

func _wall_drag(planner: Node, catalog: RefCounted) -> void:
	# A placed wall object slides along its wall and keeps TV edge snapping.
	var wall := StaticBody3D.new()
	var box := CollisionShape3D.new()
	box.shape = BoxShape3D.new()
	box.shape.size = Vector3(20, 6, .2)
	wall.add_child(box)
	stage.add_child(wall)
	wall.global_position = Vector3(0, 3, 300.1)
	var camera: Camera3D = planner.get("camera")
	camera.global_position = Vector3(0, 2.5, 292)
	camera.look_at(Vector3(0, 2.5, 300))
	await physics_frame
	await physics_frame
	var objects: Node = planner.get("objects")
	var path := "res://models/objects/enviroments/05/05_wall_TV_frameless_destructible.glb"
	var tvs: Array[Node3D] = []
	for x in [0.0, 2.6]:
		var tv: Node3D = catalog.call("_instantiate_asset", path)
		stage.add_child(tv)
		tv.global_position = Vector3(x, 2.5, 300)
		tv.set_meta("planning_wall_normal", Vector3.BACK * -1.0)
		planner.get("geometry").call("_apply_wall_mount", tv)
		objects.placed.append(tv)
		tvs.append(tv)
	var a: Dictionary = tvs[0].call("get_display_edges")
	var frame: Transform3D = a["frame"]
	var span: float = (a["size"] as Vector2).x
	objects.call("_select", tvs[1])
	var target := tvs[0].global_position + frame.basis.x.normalized() * (span + .08) + Vector3.UP * .03
	objects.call("_drag_selected", camera.unproject_position(target))
	var b: Transform3D = tvs[1].call("get_display_edges")["frame"]
	var local := frame.affine_inverse() * b.origin
	_check(absf(local.z) < .01 and absf(absf(local.x) - span) < .001 and absf(local.y) < .1, "Dragged TV stays on the wall and snaps to its neighbour")
	var floor_y := tvs[1].global_position.y
	objects.call("_drag_selected", camera.unproject_position(Vector3(40, 2.5, 300)))
	_check(is_equal_approx(tvs[1].global_position.y, floor_y), "Dragging off the wall keeps the last wall position")
	objects.call("_select", null)
	for tv in tvs:
		objects.placed.erase(tv)
		tv.queue_free()
	wall.queue_free()


func _installed_lamps(planner: Node) -> void:
	var objects: Node = planner.get("objects")
	var controls: Node = planner.get("controls")
	var lamp_path := "res://game/presentation/office_floor/public/props/planner_light.tscn"
	var records: Array = []
	for shape in ["point", "linear", "rectangle"]:
		records.append({"scene": lamp_path, "fixture_shape": shape, "fixture_visible_in_game": true, "x": 0.0, "y": 2.5, "z": 0.0})
	objects.call("_apply_layout_data", {"version": 8, "objects": records})
	var fixtures: RefCounted = controls.get("fixtures")
	var lamps := (objects.get("placed") as Array).filter(func(node: Node3D) -> bool: return node.has_method("get_fixture_config"))
	_check(lamps.size() == 3, "Every lamp shape loads from a saved map")
	for lamp: Node3D in lamps:
		objects.call("_select", lamp)
		var shape := str(lamp.call("get_fixture_config")["shape"])
		_check(fixtures.selected_panel.visible and controls.selected_light_color.get_parent().visible, "Installed lamp shows its settings: " + shape)
		for spin: SpinBox in [fixtures.selected_height, fixtures.selected_energy, fixtures.selected_angle]:
			_check(spin.get_parent().visible, "Installed lamp shows editable %s: %s" % [spin.get_parent().name, shape])
		fixtures.selected_height.value = 3.75
		_check(is_equal_approx(lamp.global_position.y, 3.75), "Height field moves the installed lamp: " + shape)
		fixtures.selected_energy.value = 9.5
		_check(is_equal_approx(float(lamp.call("get_authored_energy")), 9.5), "Brightness field edits the installed lamp: " + shape)
		fixtures.selected_angle.value = 30.0
		_check(is_equal_approx((lamp.get_node("Light") as SpotLight3D).spot_angle, 30.0), "Cone field edits the installed lamp: " + shape)
		planner.get("edit_history").call("undo")
		_check(not is_equal_approx((lamp.get_node("Light") as SpotLight3D).spot_angle, 30.0), "Cone edit is undoable: " + shape)
		objects.call("_select", lamp)
		_check(is_equal_approx(fixtures.selected_height.value, lamp.global_position.y), "Fields refresh from the selected lamp: " + shape)
	objects.call("_select", null)


func _particles(catalog: RefCounted) -> void:
	var prop = catalog.call("_instantiate_asset", "res://models/objects/enviroments/05/05_wall_TV_frameless_destructible.glb")
	stage.add_child(prop)
	stage.call("set_electronic_particles_enabled", false)
	_check(not prop.get("repeated_electronic_particles"), "Settings reach existing electronic objects")
	var later = catalog.call("_instantiate_asset", "res://models/objects/enviroments/05/05_wall_TV_frameless_destructible.glb")
	stage.add_child(later)
	_check(not later.get("repeated_electronic_particles"), "Settings reach subsequently placed electronics")
	var prefs := PREFS.new()
	_check(prefs.values.electronic_particles, "Old settings preserve sparks by default")
	# First-hit effects finish before measuring only subsequent hits.
	prop.call("take_projectile_hit", 0.0, prop.global_position, Vector3.BACK, Vector3.FORWARD, "PISTOL")
	await create_timer(1.3).timeout
	var effects := stage.get("mission_objects") as Node3D
	var count := effects.get_child_count()
	prop.call("take_projectile_hit", 0.0, prop.global_position, Vector3.BACK, Vector3.FORWARD, "PISTOL")
	_check(effects.get_child_count() == count, "Disabled repeat hit creates no spark particles")
	stage.call("set_electronic_particles_enabled", true)
	_check(prop.get("repeated_electronic_particles"), "Toggle re-enables effects")
	prop.call("take_projectile_hit", 0.0, prop.global_position, Vector3.BACK, Vector3.FORWARD, "PISTOL")
	_check(effects.get_child_count() > count, "Enabled repeat hit creates spark particles")

func _corpse() -> void:
	for scene: PackedScene in [CORPSE, HORDE]:
		await _settle(scene)
	var part := PART.instantiate() as RigidBody3D
	stage.add_child(part)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	floor_shape.shape = BoxShape3D.new()
	floor_shape.shape.size = Vector3(10, .2, 10)
	floor_body.add_child(floor_shape)
	stage.add_child(floor_body)
	floor_body.position = Vector3(1000, -.1, 1000)
	part.position = Vector3(1000, 3, 1000)
	for tick in 90:
		await physics_frame
	_check(part.position.y < 1.0 and part.position.is_finite(), "Airborne severed parts fall to the floor")
	floor_body.queue_free()
	part.queue_free()

func _settle(scene: PackedScene) -> void:
	var corpse := scene.instantiate()
	corpse.call("configure_decor_pose", {"seed": 9, "pose": "seated", "facing": 0.0})
	stage.add_child(corpse)
	corpse.position = Vector3(27, 3, 4)
	var skeleton: Skeleton3D = corpse.get("parts").get("skeleton")
	var hips := skeleton.find_bone("Hips")
	var before := skeleton.global_transform * skeleton.get_bone_global_pose(hips)
	_check(corpse.get("_physics") == null, "Authored decoration is not simulated before runtime activation")
	var camera := stage.get_node("Gameplay/Player/CameraRig/Camera3D") as Camera3D
	camera.global_position = corpse.global_position + Vector3(4, 2, 5)
	camera.look_at(corpse.global_position - Vector3(0, 1.3, 0))
	await _capture(corpse.name + "_authored")
	corpse.call("set_runtime_physics", true)
	var simulation: PhysicalBoneSimulator3D = corpse.get("_physics").get("simulator")
	var links: Array[Dictionary] = []
	for child: PhysicalBone3D in simulation.get_children():
		var parent_id := skeleton.get_bone_parent(child.get_bone_id())
		var parent := simulation.get_node_or_null("Physics_" + skeleton.get_bone_name(parent_id)) as PhysicalBone3D if parent_id >= 0 else null
		if parent != null:
			links.append({"child": child, "parent": parent, "length": _joint(child).distance_to(_joint(parent))})
	for frame in 90:
		await physics_frame
	for link in links:
		_check(absf(_joint(link["child"]).distance_to(_joint(link["parent"])) - float(link["length"])) < .065, "Joints retain anatomical segment lengths: " + corpse.name)
	var physical: PhysicalBone3D = simulation.get_node("Physics_Hips")
	var after := physical.global_transform
	_check(physical.get_bone_id() == hips and physical.is_simulating_physics(), "Physical body is bound to the actual hips bone")
	_check(after.origin.y < before.origin.y - .2, "Airborne corpse falls through physical bones")
	_check(not after.basis.is_equal_approx(before.basis), "Articulated corpse changes its authored pose")
	_check(after.origin.is_finite(), "Corpse physics remains finite")
	await _capture(corpse.name + "_settled")
	corpse.call("set_runtime_physics", false)
	corpse.queue_free()

func _aim(player: Node3D) -> void:
	var camera := player.get_node("CameraRig/Camera3D") as Camera3D
	camera.global_position = player.global_position + Vector3(3, 2.5, 4)
	camera.look_at(player.global_position + Vector3.UP)
	var mount := player.get_node("WeaponMount")
	for slot in [0, 2]:
		player.call("_select_weapon", slot)
		var weapon: Node3D = player.call("get_current_weapon")
		for height in [.1, 3.0]:
			var target := player.global_position + Vector3(0, height, 5)
			mount.call("aim_at", target)
			await physics_frame
			await physics_frame
			await process_frame
			var expected: Transform3D = (mount.get("socket") as Node3D).global_transform
			_check(weapon.global_position.distance_to(expected.origin) < .001, "Weapon remains at its hand socket")
			_check(weapon.global_basis.orthonormalized().is_equal_approx(expected.basis.orthonormalized()), "Weapon rotates with the hand rather than independently")
			var muzzle: Node3D = weapon.get_node("Muzzle")
			_check((-muzzle.global_basis.z.normalized()).dot((target - muzzle.global_position).normalized()) > .995, "Torso and barrel aim at 3D target")
			await _capture("aim_%d_%.1f" % [slot, height])

func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _capture(label: String) -> void:
	var directory := OS.get_environment("POSE_CAPTURE_DIR")
	if directory.is_empty() or DisplayServer.get_name() == "headless":
		return
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(directory)
	root.get_texture().get_image().save_png(directory.path_join(label + "_" + RenderingServer.get_current_rendering_method() + ".png"))

func _joint(bone: PhysicalBone3D) -> Vector3:
	return bone.global_transform * bone.body_offset.affine_inverse().origin
