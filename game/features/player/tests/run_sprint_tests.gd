extends SceneTree
## Sprint (Vadim, 25.11.2026): baked Sprint_<gun> clips, no cursor / no fire / minigun does not speed up, pistol and uzi
## reload sounds (mag out, then the reversed recording for mag in), and the roll's arm hold outlasting the roll.

const PLAYER := preload("res://game/features/player/public/player.tscn")
const SFX_GROUP := "sfx_"
const GUNS := ["Pistol", "Uzi", "Shotgun", "Launcher", "AK", "M4", "Sniper"]
var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	current_scene = stage
	var player := PLAYER.instantiate() as CharacterBody3D
	stage.add_child(player)
	var effects := Node3D.new()
	stage.add_child(effects)
	player.call("configure_world", effects, null)
	player.set("gravity_acceleration", 0.0)
	var animations := (player.get_node("AnimationDriver").get("animation_player") as AnimationPlayer)
	for gun in GUNS:
		var clip: String = "Sprint_" + gun
		_expect(animations.has_animation(clip), clip + " is baked.")
		if not animations.has_animation(clip):
			continue
		var animation := animations.get_animation(clip)
		_expect(animation.loop_mode == Animation.LOOP_LINEAR, clip + " loops.")
		_expect(float(animation.get_meta("ref_speed", 0.0)) > 0.0, clip + " names the pace it is played at.")
		_expect(_scale_of(animation, gun) > 0.99, clip + " draws its gun in the hand.")
		_expect(_scale_of(animation, "Pistol" if gun != "Pistol" else "AK") < 0.01, clip + " hides the other guns.")
	_expect(not animations.has_animation("Sprint_Minigun"), "The minigun has no sprint.")

	_expect(not bool(player.call("is_sprinting")), "Standing still is no sprint.")
	Input.action_press("move_up")
	await physics_frame
	_expect(not bool(player.call("is_sprinting")), "Walking is no sprint.")
	Input.action_press("sprint")
	await physics_frame
	_expect(bool(player.call("is_sprinting")), "Holding sprint while moving sprints.")
	var shots: int = int(player.call("get_current_weapon").call("get_magazine_ammo"))
	player.set("input_locked", false)
	Input.action_press("fire")
	for i in 4:
		await physics_frame
	Input.action_release("fire")
	_expect(int(player.call("get_current_weapon").call("get_magazine_ammo")) == shots, "Fire does nothing while sprinting.")
	_expect(String(player.get("_animation_selection").call("select_clip")) == "Sprint_Pistol", "The pistol plays its sprint clip.")
	var view: Dictionary = player.call("get_weapon_view")
	_expect(float(view["magnification"]) == 0.0, "No scope while sprinting.")
	player.set("_roll_remaining", 0.3)
	_expect(bool(player.call("is_sprinting")), "A roll in the middle of a sprint does not drop the sprint stance or cursor.")
	player.set("_roll_remaining", 0.0)
	Input.action_release("sprint")
	await physics_frame
	_expect(not bool(player.call("is_sprinting")), "Letting go of sprint brings the normal stance back.")
	_expect(String(player.get("_animation_selection").call("select_clip")).begins_with("Run_"), "The run clip returns after the sprint.")
	player.call("pickup_weapon", 7)
	player.call("select_weapon_slot", 1)
	Input.action_press("sprint")
	await physics_frame
	_expect(String(player.call("get_current_weapon").call("get_weapon_name")) == "MINIGUN", "The minigun is held.")
	_expect(not bool(player.call("is_sprinting")), "The minigun cannot sprint.")
	Input.action_release("sprint")
	Input.action_release("move_up")

	# Reload sounds: mag out at once, the reversed recording (mag in) halfway through.
	player.call("select_weapon_slot", 0)
	var pistol: Node3D = player.call("get_current_weapon")
	pistol.set("_magazine_ammo", 0)
	pistol.set("_cooldown_remaining", 0.0)
	pistol.call("start_reload")
	_expect(_voices(&"pistol_reload") == 1 and _voices(&"pistol_reload_in") == 0, "Mag out is heard first.")
	await create_timer(float(pistol.get("reload_time")) * 0.5 + 0.2).timeout
	_expect(_voices(&"pistol_reload_in") == 1, "Mag in is heard in the middle of the reload.")
	pistol.call("cancel_reload")

	# The roll's arm hold lasts through the cross-fade back to locomotion.
	player.get_node("AnimationDriver").call("play_dodge", Vector3(1, 0, 0), 0.55, &"Pistol")
	var hold := player.get_node("Body").find_child("RollArms", true, false)
	_expect(hold != null and float(hold.call("remaining")) > 0.55 + 0.25, "The pistol's arms are held until the roll has blended out.")
	Input.action_press("move_up")
	Input.action_press("sprint")
	player.call("_update_move", 0.016)
	_expect(bool(player.call("is_sprinting")), "Still sprinting when the roll starts.")
	Input.action_release("move_up")
	Input.action_release("sprint")
	stage.queue_free()
	print("Sprint tests: %d failures" % failures)
	quit(failures)


func _scale_of(animation: Animation, gun: String) -> float:
	for track in animation.get_track_count():
		if str(animation.track_get_path(track)).ends_with("RightHand/Weapon_" + gun) and animation.track_get_type(track) == Animation.TYPE_SCALE_3D:
			return (animation.track_get_key_value(track, 0) as Vector3).x
	return -1.0


func _voices(event: StringName) -> int:
	return get_nodes_in_group(StringName(SFX_GROUP + String(event))).size()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
	else:
		print("PASS: " + message)
