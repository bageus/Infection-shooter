extends SceneTree
const ACTIVE := preload("res://game/features/player/active_mutation_effects.gd")
const RUNTIME := preload("res://game/features/infection/public/infection_runtime.gd")
var failures := 0

class Actor extends CharacterBody3D:
	var _roll_direction := Vector3.FORWARD
	func mutation_dash() -> void: pass

class Victim extends Node3D:
	var health := 10000.0
	var total := 0.0
	var push := 0.0
	var stun := 0.0
	var pushes := 0
	var infection := Vector2.ZERO
	func take_damage(amount: float) -> void:
		total += amount
		health -= amount
	func apply_skill_push(_direction: Vector3, distance: float) -> void:
		push = distance
		pushes += 1
	func apply_blast_stun(duration: float, _intensity: float) -> void: stun = duration
	func apply_skill_infection(duration: float, dps: float) -> void: infection = Vector2(duration, dps)

class Visual extends RefCounted:
	func spike_burst(_p: Vector3, _r: float) -> void: pass
	func chain_lightning(_p: Array[Vector3]) -> void: pass
	func power_strike(_p: Vector3, _d: Vector3) -> void: pass
	func heavy_hit() -> void: pass
	func active_aura(_id: String, _r: float, _t: float) -> void: pass
	func claw_slash(_enemy: Node3D) -> void: pass
	func dash_trail(_t: float) -> void: pass
	func buff_ended(_id: String) -> void: pass

class Breakable extends StaticBody3D:
	var hits := 0
	func take_melee_hit(_damage: float, _at: Vector3, _direction: Vector3) -> void: hits += 1

class Bridge extends Node:
	var player := Actor.new()
	var runtime := RUNTIME.new()
	var vfx := Visual.new()
	var enemies: Array[Victim] = []
	var buff := ""
	func _enemies_near(at: Vector3, radius: float, nearest: bool = false) -> Array[Victim]:
		var result: Array[Victim] = []
		for enemy in enemies:
			if enemy.health > 0.0 and enemy.global_position.distance_to(at) <= radius:
				result.append(enemy)
		if nearest:
			result.sort_custom(func(a: Victim, b: Victim) -> bool: return a.global_position.distance_to(at) < b.global_position.distance_to(at))
		return result
	func _skill_effect(id: String, duration: float) -> void: runtime.report_skill_effect(id, duration)
	func _start_buff(id: String, duration: float) -> void:
		buff = id
		_skill_effect(id, duration)


func _init() -> void: call_deferred("_run")

func _fixture() -> Bridge:
	var bridge := Bridge.new()
	root.add_child(bridge)
	bridge.add_child(bridge.player)
	bridge.add_child(bridge.runtime)
	bridge.runtime.set_physics_process(false)
	var aim := Node3D.new()
	aim.name = "AimPivot"
	bridge.player.add_child(aim)
	return bridge

func _victim(bridge: Bridge, at: Vector3) -> Victim:
	var enemy := Victim.new()
	bridge.add_child(enemy)
	enemy.position = at
	bridge.enemies.append(enemy)
	return enemy

func _breakable(bridge: Bridge, at: Vector3) -> Breakable:
	var body := Breakable.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1, 2, 0.2)
	shape.shape = box
	body.add_child(shape)
	bridge.add_child(body)
	body.position = at
	return body

func _run() -> void:
	_test_blood()
	_test_lightning()
	await _test_strike()
	_test_auras()
	_test_dash()
	print("Active mutation effects tests: %d failures" % failures)
	quit(failures)

func _test_blood() -> void:
	for id in ["blood_burst", "blood_burst_2", "blood_burst_3", "blood_infection"]:
		var b := _fixture()
		var hit := _victim(b, Vector3.RIGHT)
		var outside := _victim(b, Vector3.RIGHT * 2.41)
		ACTIVE.new(b).cast(id)
		var index: int = ["blood_burst", "blood_burst_2", "blood_burst_3", "blood_infection"].find(id)
		_expect(hit.total == [20.0, 30.0, 50.0, 30.0][index] and outside.total == 0.0, "Blood burst exact damage and radius: " + id)
		_expect(is_equal_approx(hit.push, [0.0, 4.4, 5.4, 4.4][index]), "Blood knockback ends beyond the radius: " + id)
		_expect(hit.stun == (1.0 if index == 2 else 0.0), "Only the strengthened final blood burst stuns")
		_expect(hit.infection == (Vector2(3, 10) if index == 3 else Vector2.ZERO), "Infection final applies exactly three seconds at10/s")
		b.free()

func _test_lightning() -> void:
	for pair in [["discharge", 60.0], ["discharge_2", 160.0], ["discharge_3", 300.0]]:
		var b := _fixture()
		var one := _victim(b, Vector3.RIGHT * 7.9)
		var far := _victim(b, Vector3.LEFT * 8.01)
		ACTIVE.new(b).cast(pair[0])
		_expect(one.total == pair[1] and far.total == 0.0, "An isolated target receives every fixed-damage hit: " + pair[0])
		_expect(one.stun == (1.2 if pair[0] == "discharge_3" else 0.0), "Lightning stun only on level3")
		b.free()
	var b := _fixture()
	var one := _victim(b, Vector3.RIGHT)
	var two := _victim(b, Vector3.RIGHT * 3.9)
	ACTIVE.new(b).cast("discharge")
	_expect(one.total == 30.0 and two.total == 30.0, "Two targets alternate all six links within3m")
	b.free()

func _test_strike() -> void:
	for level in range(1, 4):
		var b := _fixture()
		var hit := _victim(b, Vector3(0, 0, -2))
		var behind := _victim(b, Vector3(0, 0, 0.1))
		var near_side := _victim(b, Vector3(1, 0, -0.1))
		var distant := _victim(b, Vector3(0, 0, -3.01))
		var wide_end := _victim(b, Vector3(1.4, 0, -2.9))
		var glass := _breakable(b, Vector3(0, 1, -1.5))
		var rear_glass := _breakable(b, Vector3(0, 1, 0.8))
		var far_glass := _breakable(b, Vector3(0, 1, -3.5))
		await physics_frame
		ACTIVE.new(b).cast("power_strike" + ("_%d" % level if level > 1 else ""))
		_expect(hit.total == float(20 + 10 * level) and wide_end.total == hit.total, "Power strike widens to3m and applies ranked damage")
		_expect(glass.hits == 1 and rear_glass.hits == 0 and far_glass.hits == 0, "Power strike breaks one object in reach, not behind or beyond")
		_expect(behind.total == 0.0 and near_side.total == 0.0 and distant.total == 0.0, "Power strike rejects rear, wide near-body and out-of-reach targets")
		_expect(hit.push == (4.0 if level == 1 else 5.0) and hit.stun == (1.5 if level == 3 else 0.0), "Power strike exact push/stun")
		b.free()

func _test_auras() -> void:
	for entry in [["active_claws", 2.5, 3.0, 125.0], ["active_claws_2", 3.5, 4.0, 210.0], ["active_claws_3", 4.5, 5.0, 315.0], ["storm_pulse", 6.0, 4.0, 240.0]]:
		var b := _fixture()
		var hit := _victim(b, Vector3.RIGHT * float(entry[2]))
		var outside := _victim(b, Vector3.LEFT * (float(entry[2]) + 0.01))
		var effects := ACTIVE.new(b)
		effects.cast(entry[0])
		for frame in 80:
			effects.tick(0.1)
		_expect(is_equal_approx(hit.total, float(entry[3])) and outside.total == 0.0, "Aura has exact integrated DPS/duration/radius: " + entry[0])
		_expect(effects.running.is_empty(), "Aura expires and does not repeat damage")
		if entry[0] == "storm_pulse":
			_expect(hit.stun == 2.0, "Storm refreshes a two-second stun")
		b.free()

func _test_dash() -> void:
	var b := _fixture()
	var hit := _victim(b, Vector3(0.8, 0, -1))
	var effects := ACTIVE.new(b)
	effects.cast("predator_dash")
	effects.tick(0.1)
	effects.tick(0.1)
	_expect(hit.total == 50.0 and hit.push == 2.0 and hit.pushes == 1, "Dash damages/pushes each victim once, even if blocked in place")
	effects.tick(1.0)
	_expect(effects.running.is_empty(), "Dash damage window is finite")
	b.free()

func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
