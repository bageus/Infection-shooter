extends SceneTree
## Spawn hole loot setting (auto / none / manual with a chance), its save format, and a spent hole as a quest target.

const CONFIG := preload("res://game/features/spawning/public/spawn_config.gd")
const LOOT_CONFIG := preload("res://game/features/pickups/public/loot_config.gd")
const TARGET := preload("res://game/presentation/office_floor/public/tutorial_target.gd")
const POINT := preload("res://game/features/spawning/public/spawn_point.tscn")
const DIRECTOR := preload("res://game/features/spawning/public/wave_director.gd")
const HUNGER := preload("res://game/features/infected/public/infected_hunger.tscn")
var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_defaults()
	_save_format()
	_enemy_chance()
	await _target()
	await _wave_loot()
	print("Spawn loot/target tests: %d failures" % failures)
	quit(failures)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func _defaults() -> void:
	_check(CONFIG.defaults()["loot"] == {"mode": "auto", "chance": CONFIG.LOOT_CHANCE_DEFAULT}, "a new hole drops loot as enemies do")
	_check(CONFIG.sanitize({"queues": [CONFIG.default_queue()]})["loot"]["mode"] == "auto", "a map saved before the setting is auto")
	_check(CONFIG.sanitize({"queues": [], "loot": {"mode": "bogus", "chance": 300.0}})["loot"] == {"mode": "auto", "chance": 100.0}, "unknown mode falls back to auto, chance is clamped")


func _save_format() -> void:
	var saved := CONFIG.sanitize({"queues": [CONFIG.default_queue()], "loot": {"mode": "manual", "chance": 35.0}})
	_check(saved["loot"] == {"mode": "manual", "chance": 35.0}, "manual loot keeps its chance")
	var again := CONFIG.sanitize(saved)
	_check(again == saved, "the config survives a round trip")
	_check(CONFIG.sanitize({"queues": [CONFIG.default_queue()], "loot": {"mode": "none"}})["loot"]["mode"] == "none", "no loot is kept")


func _enemy_chance() -> void:
	var manual := LOOT_CONFIG.sanitize({"mode": "auto", "chance": 35.0}, "auto")
	_check(manual.get("chance") == 35.0 and manual["mode"] == "auto", "an enemy keeps its drop chance")
	_check(not LOOT_CONFIG.sanitize({"mode": "auto", "chance": 100.0}, "auto").has("chance"), "a full chance is the usual drop and is not stored")
	_check(not LOOT_CONFIG.sanitize(null, "auto").has("chance"), "a normal enemy has no chance")


func _target() -> void:
	var hole := POINT.instantiate() as Node3D
	root.add_child(hole)
	_check(TARGET.kind_of(hole) == "spawn", "a spawn hole is a target of its own kind")
	_check(TARGET.applies_to(hole), "a spawn hole can be flagged as a target")
	_check(TARGET.is_standing(hole), "a hole with waves left is an unfinished target")
	hole.set_meta(&"spawn_spent", true)
	_check(not TARGET.is_standing(hole), "a spent hole finishes its target")
	hole.free()
	await process_frame


## A hole set to "none" spawns infected without loot; the hole is spent only once its wave is dead.
func _wave_loot() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var enemies := Node3D.new()
	enemies.name = "Enemies"
	stage.add_child(enemies)
	var player := Node3D.new()
	player.position = Vector3(10, 1, 0)
	stage.add_child(player)
	var point := POINT.instantiate() as Node3D
	point.set_meta("planning_object_id", "spawn_loot")
	stage.add_child(point)
	point.call("configure_spawn", {"queues": [{"enemies": [{"enemy": "hunger", "count": 2}], "interval": 0.1, "rule": "stream", "batch": 1, "start": "trigger", "trigger": "any", "delay": 0.0, "health": 100.0, "damage": 100.0}], "loot": {"mode": "none", "chance": 50.0}})
	var guard := HUNGER.instantiate() as Node3D
	guard.position = Vector3(0, 1, 0)
	guard.set_meta(DIRECTOR.TRIGGER_META, ["spawn_loot"])
	enemies.add_child(guard)
	var director := DIRECTOR.new()
	stage.add_child(director)
	director.configure(enemies, player)
	director.arm()
	await physics_frame
	guard.call("take_damage", 9999.0)
	for _i in 120:
		await physics_frame
	_check(not point.has_meta(&"spawn_spent"), "a hole whose wave is alive is not spent")
	var spawned := enemies.get_children().filter(func(node: Node) -> bool: return node.has_meta(&"spawned_by"))
	_check(spawned.size() == 2, "the wave spawns its two infected (%d)" % spawned.size())
	_check(spawned.all(func(node: Node) -> bool: return node.call("get_loot_config")["mode"] == "empty"), "infected of a 'none' hole carry no loot")
	for node in spawned:
		node.call("take_damage", 9999.0)
	for _i in 30:
		await physics_frame
	_check(point.call("is_target_done"), "a hole is spent once its wave is dead")
	director.disarm()
	stage.queue_free()
	await process_frame
