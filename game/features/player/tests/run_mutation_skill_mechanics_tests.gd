extends SceneTree
const EFFECTS := preload("res://game/features/player/mutation_skill_effects.gd")
var failures := 0


class Host extends CharacterBody3D:
	var max_health := 100.0
	var health := 100.0
	var _roll_direction := Vector3.ZERO
	var _aim_point := Vector3.ZERO

	func heal(amount: float) -> float:
		var gained := minf(amount, max_health - health)
		health += gained
		return gained

	func mutation_dash() -> void:
		_roll_direction = Vector3.FORWARD


class Runtime extends Node:
	signal skill_cast(skill_id: String)
	@warning_ignore("unused_signal")
	signal tree_changed
	@warning_ignore("unused_signal")
	signal mutation_changed(amount: float, threshold: float)
	var skills: Dictionary = {}

	func skill_requirements(_id: String) -> Dictionary:
		return {"level": 1}

	func has_skill(skill_id: String) -> bool:
		return skills.has(skill_id)


class Enemy extends Node3D:
	var max_health := 100.0
	var health := 100.0
	var damage_taken := 0.0
	var stunned := 0.0

	func take_damage(amount: float) -> void:
		damage_taken += amount
		health -= amount

	func apply_blast_stun(duration: float, intensity: float) -> void:
		stunned = duration * intensity

	func apply_skill_push(_direction: Vector3, _distance: float) -> void:
		pass

	func apply_mutation_poison(_duration: float, _dps: float) -> void:
		pass


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var host := Host.new()
	root.add_child(host)
	var runtime := Runtime.new()
	host.add_child(runtime)
	var effects := EFFECTS.new()
	host.add_child(effects)
	effects.set_process(false)
	var guns: Array[Node3D] = []
	effects.configure(host, runtime, guns)
	_dash(effects, runtime)
	_retaliation(effects, runtime)
	_second_heart(effects, runtime, host)
	await _acid_on_floor(effects, host, runtime)
	_discharge_chain(effects, runtime)
	_claw_kill_adrenaline(effects, runtime)
	await _walls_stop_skills(effects, host)
	_retire(host)
	await process_frame
	print("Mutation skill mechanics tests: %d failures" % failures)
	quit(failures)


# A static wall hides enemies behind it from area skills; open ground still counts.
func _walls_stop_skills(effects: Node, host: Node3D) -> void:
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	(shape.shape as BoxShape3D).size = Vector3(0.2, 2.0, 4.0)
	wall.add_child(shape)
	root.add_child(wall)
	wall.global_position = Vector3(1.0, 1.0, 0.0)
	host.global_position = Vector3.ZERO
	var behind := _enemy(Vector3(2.0, 0.0, 0.0))
	var open := _enemy(Vector3(0.0, 0.0, -2.0))
	await physics_frame
	var near: Array = effects._enemies_near(host.global_position, 4.0)
	_check(near.has(open), "An enemy on open ground is in skill reach.")
	_check(not near.has(behind), "A wall hides an enemy from area skills.")
	_retire(behind)
	_retire(open)
	wall.queue_free()


# Freed enemies leave the group at once so later tests never meet them.
func _retire(node: Node) -> void:
	node.remove_from_group("infected")
	node.remove_from_group("infected_alive")
	node.queue_free()


func _enemy(at: Vector3) -> Enemy:
	var enemy := Enemy.new()
	enemy.add_to_group("infected")
	enemy.add_to_group("infected_alive")
	root.add_child(enemy)
	enemy.global_position = at
	return enemy


func _dash(effects: Node, runtime: Runtime) -> void:
	var behind := _enemy(Vector3(0, 0, 2.0))
	var ahead := _enemy(Vector3(0, 0, -4.0))
	runtime.skills["predator_dash"] = true
	runtime.skill_cast.emit("predator_dash")
	_check(behind.damage_taken == 0.0, "Predator Dash does not hit enemies behind the start point")
	_check(ahead.damage_taken == 0.0, "A distant enemy is not hit before the dash reaches it")
	# The host stands in for the dash's motion along its path.
	effects.player.global_position = Vector3(0, 0, -3.0)
	effects.call("_process", 0.1)
	effects.call("_process", 0.1)
	_check(is_equal_approx(ahead.damage_taken, 50.0), "Predator Dash hits an enemy on its path exactly once")
	effects.call("_process", 0.3)
	effects.player.global_position = Vector3(0, 0, -4.5)
	effects.call("_process", 0.1)
	_check(is_equal_approx(ahead.damage_taken, 50.0), "The strike window ends with the dash")
	effects.player.global_position = Vector3.ZERO
	_retire(behind)
	_retire(ahead)
	runtime.skills.erase("predator_dash")


func _retaliation(effects: Node, runtime: Runtime) -> void:
	var near := _enemy(Vector3(1.0, 0, 0))
	runtime.skills["retaliation"] = true
	for hit in 3:
		effects.call("on_player_hit", 15.0)
		effects.call("_process", 0.5)
	_check(near.stunned == 0.0, "Retaliation waits for a burst of damage")
	effects.call("on_player_hit", 15.0)
	_check(near.stunned == 4.0, "Several light hits release a four-second stun")
	near.stunned = 0.0
	effects.call("on_player_hit", 15.0)
	_check(near.stunned == 0.0, "The pulse resets the damage window")
	effects.call("_process", 3.5)
	for hit in 3:
		effects.call("on_player_hit", 15.0)
		effects.call("_process", 1.6)
	_check(near.stunned == 0.0, "Spread-out damage does not trigger Retaliation")
	effects.call("_process", 15.0)
	effects.call("on_player_hit", 50.0)
	_check(near.stunned == 4.0, "Retaliation rearms after fifteen seconds")
	near.stunned = 0.0
	effects.call("on_player_hit", 50.0)
	_check(near.stunned == 0.0, "Damage cannot bypass Retaliation recovery")
	_retire(near)
	runtime.skills.erase("retaliation")


func _second_heart(effects: Node, runtime: Runtime, host: Host) -> void:
	runtime.skills["second_heart"] = true
	host.health = 0.0
	_check(bool(effects.call("survive_lethal")), "Second Heart prevents death")
	host.health = 1.0
	for frame in 10:
		effects.call("_process", 0.25)
	_check(is_equal_approx(host.health, 26.0), "Second Heart regenerates 10 HP per second after the save")
	for frame in 20:
		effects.call("_process", 0.25)
	var healed := host.health
	_check(healed > 45.0 and healed <= 51.0, "Second Heart restores about 50 HP over five seconds")
	effects.call("_process", 1.0)
	_check(is_equal_approx(host.health, healed), "Second Heart regeneration stops after five seconds")
	_check(not bool(effects.call("survive_lethal")), "Second Heart keeps its cooldown")
	runtime.skills.erase("second_heart")


func _discharge_chain(effects: Node, runtime: Runtime) -> void:
	var first := _enemy(Vector3(0, 0, 1.0))
	var second := _enemy(Vector3(0, 0, 4.0))
	var third := _enemy(Vector3(0, 0, 7.0))
	runtime.skills["discharge"] = true
	effects.call("_cast", "discharge")
	_check(is_equal_approx(first.damage_taken, 30.0), "Nearest pair receives repeated fixed-damage links")
	_check(is_equal_approx(second.damage_taken, 30.0), "Second target alternates with the first")
	_check(is_equal_approx(third.damage_taken, 0.0), "Nearest eligible neighbour wins each link")
	_retire(first)
	_retire(second)
	_retire(third)
	runtime.skills.erase("discharge")


func _claw_kill_adrenaline(effects: Node, runtime: Runtime) -> void:
	var victim := _enemy(Vector3(1.0, 0, 0))
	runtime.skills["claws"] = true
	runtime.skills["adrenaline"] = true
	victim.set("health", 10.0)
	# The claw pulse fires on the first frame; the mock reports the death the way the enemy does.
	effects.call("_process", 0.0)
	if float(victim.get("health")) <= 0.0:
		effects.call("on_enemy_killed", victim)
	_check(is_equal_approx(float(effects.call("movement_multiplier")), 1.5), "Claws kills start Adrenaline's speed boost")
	effects.call("_process", 4.1)
	_check(is_equal_approx(float(effects.call("movement_multiplier")), 1.0), "Adrenaline expires after four seconds")
	_retire(victim)
	runtime.skills.erase("claws")
	runtime.skills.erase("adrenaline")


# Acid Spit always lands on the floor: an aim on a wall face comes back to
# the floor short of the wall, an aim on a desk top drops to the floor.
func _acid_on_floor(effects: Node, host: Host, runtime: Runtime) -> void:
	var scenery := Node3D.new()
	root.add_child(scenery)
	_box(scenery, Vector3(0, -0.5, 0), Vector3(20, 1, 20))
	_box(scenery, Vector3(4.1, 1.5, 0), Vector3(0.2, 3, 6))
	_box(scenery, Vector3(-3, 0.375, 0), Vector3(1.2, 0.75, 0.8))
	host.global_position = Vector3(0, 0.9, 0)
	await physics_frame
	await physics_frame
	var on_wall: Vector3 = effects.call("acid_floor_point", Vector3(4.0, 1.4, 0.3))
	_check(absf(on_wall.y) < 0.05, "Acid aimed at a wall lands on the floor (y %.2f)." % on_wall.y)
	_check(on_wall.x < 3.8 and on_wall.x > 3.0, "Acid aimed at a wall stops just short of it (x %.2f)." % on_wall.x)
	var on_desk: Vector3 = effects.call("acid_floor_point", Vector3(-3.0, 0.75, 0.1))
	_check(absf(on_desk.y) < 0.05 and absf(on_desk.x + 3.0) < 0.05, "Acid aimed at a desk top lands on the floor below it.")
	var on_floor: Vector3 = effects.call("acid_floor_point", Vector3(1.5, 0.0, -2.0))
	_check(on_floor.distance_to(Vector3(1.5, 0.0, -2.0)) < 0.05, "Acid aimed at open floor lands where aimed.")
	# Spore Cocoon uses the same floor point: aimed at the wall face (1.4 m up),
	# the burst lands on the floor short of the wall and still reaches an enemy there.
	var near_floor := _enemy(Vector3(1.0, 0.0, 0.3))
	host._aim_point = Vector3(4.0, 1.4, 0.3)
	runtime.skills["spore_cocoon"] = true
	runtime.skill_cast.emit("spore_cocoon")
	await create_timer(EFFECTS.SPORE_DELAY + 0.3).timeout
	_check(is_zero_approx(near_floor.damage_taken), "Retired Spore Cocoon no longer applies active damage")
	_retire(near_floor)
	scenery.queue_free()


func _box(parent: Node3D, center: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	parent.add_child(body)
	body.global_position = center


func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
