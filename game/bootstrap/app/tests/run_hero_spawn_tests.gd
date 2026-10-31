extends SceneTree
## Hero spawn settings: old records load as automatic, values are clamped, and a manual spawn
## sets the hero's start state (slots, ammo, health, armor, antidotes, threshold, gas mask).
const MAIN := preload("res://game/bootstrap/app/main.tscn")
const HERO := preload("res://game/bootstrap/app/planning_hero_spawn.gd")
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_expect(str(HERO.sanitize({}).mode) == "auto", "A record without hero settings loads as automatic")
	var clean: Dictionary = HERO.sanitize({"mode": "manual", "slots": [4, -1, 0], "health": 999.0, "antidotes": 9, "threshold": 5.0, "armor": true})
	_expect(str(clean.mode) == "manual" and clean.slots == [4, -1, 0], "Manual mode and slots are kept")
	_expect(is_equal_approx(float(clean.health), HERO.MAX_HEALTH) and int(clean.antidotes) == HERO.MAX_ANTIDOTES, "Health and antidotes are clamped")
	_expect(is_equal_approx(float(clean.threshold), HERO.MIN_THRESHOLD), "Threshold is clamped to the base minimum")
	_expect(HERO.sanitize({"mode": "manual", "slots": [-1, 3, -1]}).slots == [0, -1, -1], "Slot 1 without a weapon falls back to the default slots")
	_expect(HERO.sanitize({"mode": "manual", "slots": [2, 2, -1]}).slots == [0, -1, -1], "Duplicate weapons fall back to the default slots")

	root.size = Vector2i(320, 180)
	var stage := MAIN.instantiate()
	root.add_child(stage)
	current_scene = stage
	(stage.get_node("Gameplay/Enemies") as Node).process_mode = Node.PROCESS_MODE_DISABLED
	for i in 3:
		await process_frame
	var player := stage.get("player") as Node3D
	player.set_physics_process(false)

	var hero := HERO.defaults()
	hero.mode = "manual"
	hero.slots = [4, 1, -1]
	hero.health = 40.0
	hero.armor = true
	hero.antidotes = 3
	hero.threshold = 55.0
	hero.gas_mask = true
	hero.ammo[4] = 30
	player.call("apply_hero_spawn", HERO.sanitize(hero))
	_expect(is_equal_approx(float(player.get("health")), 40.0), "Manual spawn sets health")
	_expect(is_equal_approx(float(player.get("armor")), float(player.get("max_armor"))), "Manual spawn with a vest fills the armor")
	_expect(int(player.get("antidotes")) == 3, "Manual spawn sets antidotes")
	_expect(Array(player.get("_slot_weapons")) == [4, 1, -1], "Manual spawn sets the weapon slots")
	_expect(int(player.get("current_weapon_index")) == 0, "Manual spawn selects the first slot")
	var infection: Node = stage.get("infection_runtime")
	_expect(is_equal_approx(float(infection.get("_domain").critical_threshold), 55.0), "Manual spawn sets the mutagen threshold")
	_expect(bool(infection.call("is_gas_mask_worn")), "Manual spawn sets the gas mask")

	player.call("apply_hero_spawn", HERO.defaults())
	_expect(is_equal_approx(float(player.get("health")), 40.0), "Automatic settings leave the start state alone")
	player.call("apply_hero_spawn", HERO.sanitize(hero))
	player.call("restore_manual_hero_spawn")
	_expect(is_equal_approx(float(player.get("health")), 40.0), "A manual spawn is restored after a carry")

	if failures == 0:
		print("hero spawn tests passed")
	quit(failures)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	printerr("FAIL: " + message)
