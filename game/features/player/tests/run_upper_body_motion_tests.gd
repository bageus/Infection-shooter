extends SceneTree
const PLAYER := preload("res://game/features/player/public/player.tscn")
const KICK := preload("res://game/features/player/player_kick_pose.gd")
const RECOIL := preload("res://game/features/player/shot_recoil.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	for weapon in RECOIL.DISTANCES:
		_check(KICK.RECOIL.has(weapon), "%s has a recoil profile" % weapon)
	var pistol: Dictionary = KICK.RECOIL["PISTOL"]
	_check(pistol.has("RightHand") and pistol.has("RightForeArm") and not pistol.has("RightShoulder") and not pistol.has("Spine2"), "Pistol kicks only hands and elbows")
	_check(KICK.RECOIL["AK"].has("RightShoulder") and not KICK.RECOIL["AK"].has("Spine2"), "Automatic rifles add the shoulders")
	_check(KICK.RECOIL["SHOTGUN"].has("Spine2") and KICK.RECOIL["SNIPER RIFLE"].has("Spine2"), "Shotgun and sniper kick the upper body")
	_check(not KICK.RECOIL["MINIGUN"].has("RightHand") and KICK.RECOIL["MINIGUN"].has("RightShoulder"), "Minigun kicks elbows and shoulders")
	for weapon in KICK.RECOIL:
		for bone in KICK.RECOIL[weapon]:
			_check(float(KICK.RECOIL[weapon][bone]) <= 4.0, "Recoil stays a micro movement")
	var stage := Node3D.new()
	root.add_child(stage)
	var player = PLAYER.instantiate()
	stage.add_child(player)
	player.set_physics_process(false)
	player.configure_world(stage, null)
	await process_frame
	var kick: Node = player.get_node("WeaponMount").skeleton.get_node("KickPose")
	var skeleton: Skeleton3D = kick.get_parent()
	var bone := skeleton.find_bone("RightHand")
	var before := skeleton.global_basis * skeleton.get_bone_global_pose(bone).basis
	kick.call("_pitch", skeleton, "RightHand", Vector3.RIGHT, 0.2)
	var after := skeleton.global_basis * skeleton.get_bone_global_pose(bone).basis
	var expected := Basis(Vector3.RIGHT, 0.2) * before
	_check((after.x - expected.x).length() < 0.001 and (after.y - expected.y).length() < 0.001, "A bone turns about the world axis")
	player.velocity = Vector3(0, 0, -5)
	for i in 90:
		await process_frame
	_check(float(kick.get("_lean")) > 0.9, "Running leans the body")
	player.velocity = Vector3.ZERO
	for i in 90:
		await process_frame
	_check(float(kick.get("_lean")) < 0.05, "Standing still straightens up")
	var driver: Node = player.get_node("AnimationDriver")
	_check(driver.call("play_dodge", Vector3.FORWARD, 0.55, &"Pistol"), "Roll plays")
	var roll: Animation = driver.get("animation_player").get_animation(&"Running_Dive_Roll")
	var shown := {}
	for track in roll.get_track_count():
		var path := str(roll.track_get_path(track))
		if "RightHand/Weapon_" in path and roll.track_get_type(track) == Animation.TYPE_SCALE_3D:
			shown[path] = roll.track_get_key_value(track, 0)
	_check(not shown.is_empty(), "Roll clip has weapon scale tracks")
	for path in shown:
		_check((shown[path] == Vector3.ONE) == ("Weapon_Pistol" in path), "Roll draws only the held gun: " + path)
	print("Upper body motion tests: %d failures" % failures)
	quit(1 if failures else 0)
