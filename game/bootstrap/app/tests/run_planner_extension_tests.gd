extends SceneTree
const MAIN := preload("res://game/bootstrap/app/main.tscn")
const CORPSE := preload("res://game/features/infected/public/decor/corpse_hunger.tscn")
const PREFS := preload("res://game/bootstrap/app/menu/menu_preferences.gd")
var failures := 0
var stage: Node3D

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	stage = MAIN.instantiate()
	root.add_child(stage)
	current_scene = stage
	await process_frame
	var player: Node3D = stage.get("player")
	player.set_physics_process(false)
	var planner: Node = stage.get("planning_mode")
	var catalog = planner.get("catalog")
	_check(catalog.group_catalogs["13"].size() == 10, "All ten wall objects are in group 13")
	var wall = catalog.call("_instantiate_asset", "res://models/objects/enviroments/13/13_wall_cafeteria.glb")
	stage.add_child(wall)
	_check(wall.get_meta("planning_wall_mount", false) and wall.freeze, "Group 13 stays attached to wall")
	await _snap(catalog)
	await _particles(catalog)
	await _corpse()
	await _aim(player)
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
	var corpse := CORPSE.instantiate()
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
	await _capture("corpse_authored")
	corpse.call("set_runtime_physics", true)
	for frame in 90:
		await physics_frame
	var simulation: PhysicalBoneSimulator3D = corpse.get("_physics").get("simulator")
	var physical: PhysicalBone3D = simulation.get_node("Physics_Hips")
	var after := physical.global_transform
	_check(physical.get_bone_id() == hips and physical.is_simulating_physics(), "Physical body is bound to the actual hips bone")
	_check(after.origin.y < before.origin.y - .2, "Airborne corpse falls through physical bones")
	_check(not after.basis.is_equal_approx(before.basis), "Articulated corpse changes its authored pose")
	_check(after.origin.is_finite(), "Corpse physics remains finite")
	await _capture("corpse_settled")
	corpse.call("set_runtime_physics", false)

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
			await process_frame
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
