extends SceneTree
const LOOT := preload("res://game/features/pickups/public/drop_table.gd")
const TEXT := preload("res://game/bootstrap/app/mutation_text.gd")
const CATALOG := preload("res://game/features/infection/public/infection_runtime.gd")
const PLAYER := preload("res://game/features/player/public/player.tscn")
const CLOUD := preload("res://game/features/infection_source/public/mutagen_cloud.tscn")
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_loot_probabilities()
	_cards()
	await _cloud_healing()
	print("Issue7 card and loot tests: %d failures" % failures)
	quit(failures)

func _loot_probabilities() -> void:
	var plain := {"ammo": 0, "medkit": 0}
	var boosted := plain.duplicate()
	for sample in 10000:
		var roll := (float(sample) + 0.5) / 10000.0
		for pair in [[plain, 1.0], [boosted, 1.3]]:
			var id := LOOT.roll_item(roll, {"ammo_pistol": 1.0, "medkit": 1.0}, 0.6, pair[1])
			if not id.is_empty():
				pair[0]["ammo" if id.begins_with("ammo_") else "medkit"] += 1
	_check(boosted.ammo == plain.ammo * 1.3, "Recycling raises actual ammo drop chance by thirty percent")
	_check(boosted.medkit == plain.medkit, "Recycling preserves non-ammo drop probabilities")

func _cards() -> void:
	var catalogue := CATALOG.new()
	var old_locale := TranslationServer.get_locale()
	for locale in ["ru", "en"]:
		TranslationServer.set_locale(locale)
		for row in catalogue.skill_catalog():
			var text := TEXT.description(str(row[0]))
			_check(not text.contains("{") and not text.begins_with("mutationSkill_"), "Every card resolves localized tuning: " + str(row[0]))
	TranslationServer.set_locale("ru")
	_check(TEXT.description("bone_armor").contains("23%"), "Bone Armor rounds only its displayed percentage")
	TranslationServer.set_locale(old_locale)
	catalogue.free()

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func _cloud_healing() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var player := PLAYER.instantiate()
	stage.add_child(player)
	player.position = Vector3(0, 1, 0)
	player.set_physics_process(false)
	player.get("mutation_effects").set_process(false)
	var runtime: Node = player.get("infection_runtime")
	runtime.set_physics_process(false)
	runtime._domain.mutation = 65.0
	runtime._domain.critical_threshold = 95.0
	for id in ["claws", "blood_scent", "adrenaline", "hypertrophy", "regeneration", "second_heart"]:
		runtime.tree.learned[id] = true
	var clouds: Array[Node] = []
	for index in 5:
		var cloud := CLOUD.instantiate()
		stage.add_child(cloud)
		cloud.heals_visitors = index > 0
		cloud.absorb_delay = 0.0
		cloud.activate()
		cloud.set_physics_process(false)
		clouds.append(cloud)
	await physics_frame
	await physics_frame
	_check(clouds.all(func(cloud: Node) -> bool: return cloud.get_overlapping_bodies().has(player)), "All five clouds overlap the real player")
	player.health = 50.0
	for cloud in clouds:
		cloud.call("_physics_process", 0.1)
	_check(is_equal_approx(player.health, 50.2), "Five clouds heal only2HP/s without a duplicate absorption heal")
	await _cloud_presence_cases(player, runtime, clouds)
	stage.queue_free()
	await process_frame


func _cloud_presence_cases(player: Node, runtime: Node, clouds: Array[Node]) -> void:
	clouds[0].call("_feed", player, float(clouds[0].get("_absorption_remaining")))
	_check(clouds[0].monitoring, "Spent ordinary clouds still monitor Devourer presence")
	for cloud in clouds:
		cloud.set("_absorption_remaining", 0.0)
	await physics_frame
	player.health = 50.0
	for cloud in clouds:
		cloud.call("_physics_process", 0.1)
	_check(is_equal_approx(player.health, 50.2), "Spent clouds still provide Devourer presence, once per frame")
	clouds[0].permanent = true
	runtime._domain.control_loss_remaining = 2.0
	await physics_frame
	player.health = 50.0
	for cloud in clouds:
		cloud.call("_physics_process", 0.1)
	_check(is_equal_approx(player.health, 50.2), "Permanent clouds heal when mutagen absorption is refused")
	runtime.tree.learned.erase("second_heart")
	await physics_frame
	player.health = 50.0
	for cloud in clouds:
		cloud.call("_physics_process", 0.1)
	_check(is_equal_approx(player.health, 50.0), "Previously spawned healing clouds stop healing after Devourer deactivates")
