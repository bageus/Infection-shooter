extends SceneTree
## An unaware infected far from the hero stops processing and wakes when the hero nears, a shot lands or a cry reaches it;
## a hunting one, or one near the hero, never sleeps.
const HUNGER := "res://game/features/infected/public/infected_hunger.tscn"
var failures := 0


func _init() -> void:
	call_deferred("_run")


func _make(stage: Node3D, target: Node3D, at: Vector3, hunting: bool) -> Node3D:
	var e := (load(HUNGER) as PackedScene).instantiate() as Node3D
	e.position = at
	stage.add_child(e)
	e.call("set_target" if hunting else "watch_target", target)
	return e


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(300, 1, 300)
	shape.shape = box
	ground.add_child(shape)
	ground.position.y = -0.5
	stage.add_child(ground)
	var hero := Node3D.new()
	hero.position = Vector3(0, 1, 0)
	stage.add_child(hero)
	var far := _make(stage, hero, Vector3(60, 0.05, 0), false)
	var near := _make(stage, hero, Vector3(25, 0.05, 0), false)
	var hunter := _make(stage, hero, Vector3(60, 0.05, 20), true)
	await _frames(30)
	_check(far.process_mode == Node.PROCESS_MODE_DISABLED, "a far unaware infected falls asleep")
	_check(near.process_mode != Node.PROCESS_MODE_DISABLED, "one inside the sleep margin stays awake")
	_check(hunter.process_mode != Node.PROCESS_MODE_DISABLED, "a hunting infected never sleeps")
	await _frames(60)
	_check(far.process_mode == Node.PROCESS_MODE_DISABLED, "it stays asleep while the hero is away")
	hero.position = Vector3(45, 1, 0)
	await create_timer(0.8).timeout
	_check(far.process_mode != Node.PROCESS_MODE_DISABLED, "it wakes when the hero comes within wake range")
	_check(far.get("_senses").state == 0, "waking by distance alone does not alert it")
	hero.position = Vector3(0, 1, 0)
	far.position = Vector3(60, 0.05, 0)
	await _frames(30)
	_check(far.process_mode == Node.PROCESS_MODE_DISABLED, "it sleeps again when the hero leaves")
	far.call("take_damage", 1.0)
	_check(far.process_mode != Node.PROCESS_MODE_DISABLED, "damage wakes it at once")
	await _frames(30)
	_check(far.process_mode != Node.PROCESS_MODE_DISABLED, "a hurt infected does not go back to sleep")
	var cry := _make(stage, hero, Vector3(60, 0.05, -20), false)
	await _frames(30)
	_check(cry.process_mode == Node.PROCESS_MODE_DISABLED, "a second far infected sleeps")
	cry.call("hear_alert", cry.global_position, 30.0)
	_check(cry.process_mode != Node.PROCESS_MODE_DISABLED and cry.call("is_alerted"), "an ally's cry wakes it and starts the chase")
	print("Enemy slumber tests: %d failure(s)" % failures)
	quit(failures)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
		print("FAIL: " + message)
