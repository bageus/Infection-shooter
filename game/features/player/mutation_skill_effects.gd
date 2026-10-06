extends Node

# Host-side effects. The infection runtime owns selection and cooldown state.
const SKILL_VFX := preload("res://game/features/player/mutation_skill_vfx.gd")
const VFX_BUFFS := ["storm_pulse", "bone_blades", "berserk"]
var player: CharacterBody3D
var runtime: Node
var weapons: Array[Node3D] = []
var baselines: Array[Dictionary] = []
var buffs: Dictionary = {}
var last_hit_time := -100.0
var heart_cooldown := 0.0
var kill_streak := 0
var kill_timer := 0.0
## Seconds between melee strikes; reach is measured to the enemy's surface.
const MELEE_COOLDOWN := 0.5
const MELEE_REACH := 1.1
const WEAPON_BUFFS := ["overload", "combat_reflex", "battle_metabolism", "killer_instinct", "berserk", "reflex_arc"]
var _weapons_dirty := false
var _weapon_factors := Vector4.ZERO
var melee_cooldown := 0.0
var _melee_victim: WeakRef
var _melee_time := -100.0
var storm_tick := 0.0
var acid_pools: Array[Dictionary] = []
## Retaliation answers a burst of damage, not one heavy blow.
const RETALIATION_WINDOW := 3.0
const RETALIATION_DAMAGE := 50.0
var _clock := 0.0
var _recent_hits: Array[Vector2] = []
## Second Heart's emergency regeneration after a survived lethal hit.
const SECOND_HEART_HEAL := 10.0
const SECOND_HEART_DURATION := 5.0
## Predator Dash strikes everything it passes, once per dash.
const DASH_STRIKE_TIME := 0.45
const DASH_REACH := 1.6
const DASH_DAMAGE := 30.0
var _dash_struck: Dictionary = {}

var effects_root: Node3D
var vfx: SKILL_VFX


func configure_world(container: Node3D) -> void:
	effects_root = container
	if vfx != null:
		vfx.configure_world(container)


func configure(host: CharacterBody3D, infection: Node, guns: Array[Node3D]) -> void:
	player = host
	runtime = infection
	weapons = guns
	vfx = SKILL_VFX.new()
	add_child(vfx)
	vfx.setup(host)
	vfx.configure_world(effects_root)
	for gun in guns:
		baselines.append({"reload_time": gun.get("reload_time"), "spread_degrees": gun.get("spread_degrees"), "shots_per_second": gun.get("shots_per_second"), "bullet_damage": gun.get("bullet_damage")})
	runtime.connect("skill_cast", _cast)
	runtime.connect("tree_changed", _refresh_stats)
	runtime.connect("mutation_changed", _on_mutation_changed)
	_refresh_stats()


func _on_mutation_changed(_amount: float, _threshold: float) -> void:
	_refresh_stats()


func _release_spores(location: Vector3) -> void:
	if not is_instance_valid(player) or player.is_queued_for_deletion():
		return
	for enemy in _enemies_near(location, 3.0):
		enemy.call("apply_mutation_poison", 5.0, 5.0)


# Blood Scent: wounded enemies take extra damage from melee as well as bullets.
func _scented(enemy: Node3D, amount: float) -> float:
	if enabled("blood_scent") and float(enemy.get("health")) < float(enemy.get("max_health")) * 0.7:
		return amount * 1.22
	return amount


func _refresh_stats() -> void:
	var next_max := 125.0 if enabled("hypertrophy") else 100.0
	player.set("max_health", next_max)
	player.set("health", minf(float(player.get("health")), next_max))
	vfx.set_passives(enabled("bone_armor"), enabled("hardened"))
	_update_weapons()


func enabled(skill_id: String) -> bool:
	return bool(runtime.call("has_skill", skill_id))


func _process(delta: float) -> void:
	_clock += delta
	heart_cooldown = maxf(0.0, heart_cooldown - delta)
	melee_cooldown = maxf(0.0, melee_cooldown - delta)
	kill_timer = maxf(0.0, kill_timer - delta)
	if kill_timer == 0.0:
		kill_streak = 0
	for key in buffs.keys():
		var previous := float(buffs[key])
		buffs[key] = maxf(0.0, previous - delta)
		if previous > 0.0 and float(buffs[key]) == 0.0:
			if key in WEAPON_BUFFS:
				_weapons_dirty = true
			if key in VFX_BUFFS:
				vfx.buff_ended(key)
	if enabled("regeneration") and Time.get_ticks_msec() * 0.001 - last_hit_time > 5.0:
		player.call("heal", 1.4 * delta)
	if active_buff("second_heart"):
		player.call("heal", SECOND_HEART_HEAL * delta)
	if active_buff("predator_dash"):
		_dash_strike()
	storm_tick -= delta
	if storm_tick <= 0.0:
		storm_tick = 0.6
		if active_buff("storm_pulse"):
			for enemy in _enemies_near(player.global_position, 4.0):
				enemy.call("take_damage", 3.5)
				enemy.call("apply_blast_stun", 0.7, 0.4)
		if active_buff("bone_blades"):
			for enemy in _enemies_near(player.global_position, 1.7):
				enemy.call("take_damage", 18.0)
	for i in range(acid_pools.size() - 1, -1, -1):
		var pool := acid_pools[i]
		pool["remaining"] = float(pool["remaining"]) - delta
		if float(pool["remaining"]) <= 0.0:
			acid_pools.remove_at(i)
			continue
		for enemy in _enemies_near(pool["position"], 2.2):
			enemy.call("take_damage", 5.0 * delta)
	if _weapons_dirty:
		_update_weapons()


func active_buff(skill_id: String) -> bool:
	return float(buffs.get(skill_id, 0.0)) > 0.0


func on_player_hit(amount: float, damage_type: String = "physical") -> float:
	last_hit_time = Time.get_ticks_msec() * 0.001
	var reserve := float(buffs.get("temporary_armor", 0.0))
	var absorbed := minf(amount, reserve)
	buffs["temporary_armor"] = reserve - absorbed
	if absorbed > 0.0:
		vfx.energy_shield()
	amount -= absorbed
	var reduction := 0.14 if enabled("bone_armor") else 0.0
	if damage_type in ["acid", "fire", "electric"] and enabled("hardened"):
		reduction += 0.22
	if enabled("pain_block") and float(player.get("health")) < float(player.get("max_health")) * 0.3:
		reduction += 0.25
	if active_buff("berserk"):
		reduction += 0.2
	if enabled("reactive_evolution"):
		var key := "adaptation_" + damage_type
		reduction += minf(0.2, float(buffs.get(key, 0.0)) * 0.03)
		buffs[key] = minf(6.0, float(buffs.get(key, 0.0)) + 1.0)
	if enabled("retaliation") and _retaliation_due(amount):
		vfx.electric_pulse(player.global_position, 3.0)
		for enemy in _enemies_near(player.global_position, 3.0):
			enemy.call("apply_blast_stun", 1.2, 0.6)
	return amount * (1.0 - minf(0.75, reduction))


func _retaliation_due(amount: float) -> bool:
	_recent_hits.append(Vector2(_clock, amount))
	var total := 0.0
	for i in range(_recent_hits.size() - 1, -1, -1):
		if _clock - _recent_hits[i].x > RETALIATION_WINDOW:
			_recent_hits.remove_at(i)
		else:
			total += _recent_hits[i].y
	if total < RETALIATION_DAMAGE:
		return false
	_recent_hits.clear()
	return true


func survive_lethal() -> bool:
	if not enabled("second_heart") or heart_cooldown > 0.0:
		return false
	heart_cooldown = 110.0
	last_hit_time = -100.0
	vfx.heartbeat()
	buffs["second_heart"] = SECOND_HEART_DURATION
	return true


func on_enemy_killed(enemy: Node3D) -> void:
	var near := enemy.global_position.distance_to(player.global_position) < 4.0
	# Predator skills reward kills made with a melee strike, as described.
	var melee_kill: bool = _melee_victim != null and _melee_victim.get_ref() == enemy and Time.get_ticks_msec() / 1000.0 - _melee_time < 0.5
	kill_streak = mini(6, kill_streak + 1) if kill_timer > 0.0 else 1
	kill_timer = 5.0
	if enabled("combat_reflex"): _start_buff("combat_reflex", 4.0)
	if enabled("battle_metabolism"): _start_buff("battle_metabolism", 6.0)
	if enabled("hyperactive"):
		runtime.call("reduce_skill_cooldowns", 1.0 + kill_streak * 0.15)
	if near and enabled("adrenaline"): _start_buff("adrenaline", 5.0)
	if melee_kill and enabled("killer_instinct"):
		(player.call("get_current_weapon") as Node3D).call("add_magazine_ammo", 2)
		_start_buff("killer_instinct", 5.0)
	if melee_kill and enabled("devourer"):
		_heal_or_armor(8.0)
	if active_buff("living_harvest"):
		_heal_or_armor(14.0)
	if active_buff("berserk"): _start_buff("berserk", minf(13.0, float(buffs["berserk"]) + 2.0))
	if enemy.has_meta("mutation_parasite"):
		for other in _enemies_near(enemy.global_position, 3.0):
			if other != enemy: other.call("apply_mutation_poison", 4.0, 5.0, true)
	if enabled("recycling") and randf() < 0.35:
		player.call("add_ammo_to_current_weapon", 5)


func movement_multiplier() -> float:
	var speed := 1.0
	if enabled("synapses"): speed += 0.12
	if active_buff("adrenaline"): speed += 0.18
	if enabled("hyperactive") and kill_streak >= 3: speed += 0.12
	if active_buff("overload"): speed += 0.38
	if active_buff("berserk"): speed += 0.3
	return speed


func on_roll() -> void:
	if enabled("reflex_arc"):
		_start_buff("reflex_arc", 3.0)


func melee() -> bool:
	if melee_cooldown > 0.0:
		return false
	melee_cooldown = MELEE_COOLDOWN
	var forward := -(player.get_node("AimPivot") as Node3D).global_basis.z
	for enemy in _enemies_near(player.global_position, MELEE_REACH + 2.5, true):
		var offset := enemy.global_position - player.global_position
		offset.y = 0.0
		if offset.length() - _body_radius(enemy) > MELEE_REACH or offset.normalized().dot(forward) <= 0.0:
			continue
		_melee_victim = weakref(enemy)
		_melee_time = Time.get_ticks_msec() / 1000.0
		if enabled("claws"):
			vfx.claw_slash(enemy)
		enemy.call("take_damage", _scented(enemy, 36.0 if enabled("claws") else 17.0))
		return true
	return false


static func _body_radius(body: Node) -> float:
	var shape := body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape != null and shape.shape is CapsuleShape3D:
		return (shape.shape as CapsuleShape3D).radius * absf(shape.global_basis.get_scale().x)
	return 0.4




func _start_buff(skill_id: String, duration: float) -> void:
	buffs[skill_id] = duration
	if skill_id in WEAPON_BUFFS:
		_weapons_dirty = true
	if skill_id in VFX_BUFFS:
		vfx.buff_started(skill_id)


func _update_weapons() -> void:
	_weapons_dirty = false
	var reload_factor := (0.8 if enabled("muscle_memory") else 1.0) * (0.65 if active_buff("overload") else 1.0)
	var spread_factor := 0.7 if enabled("stabilizers") else 1.0
	var attack_speed := (1.22 if active_buff("combat_reflex") else 1.0) * (1.25 if active_buff("overload") else 1.0)
	if enabled("reflex_arc") and active_buff("reflex_arc"):
		attack_speed *= 1.2
	var damage := 1.0 + (0.18 if active_buff("battle_metabolism") else 0.0)
	if active_buff("killer_instinct"): damage += 0.15
	if active_buff("berserk"): damage += 0.3
	var factors := Vector4(reload_factor, spread_factor, attack_speed, damage)
	if factors.is_equal_approx(_weapon_factors):
		return
	_weapon_factors = factors
	for i in weapons.size():
		var gun := weapons[i]
		var base: Dictionary = baselines[i]
		gun.set("reload_time", float(base["reload_time"]) * factors.x)
		gun.set("spread_degrees", float(base["spread_degrees"]) * factors.y)
		gun.set("shots_per_second", float(base["shots_per_second"]) * factors.z)
		gun.set("bullet_damage", float(base["bullet_damage"]) * factors.w)


func _cast(skill_id: String) -> void:
	match skill_id:
		"blood_burst":
			vfx.spike_burst(player.global_position, 4.0)
			for enemy in _enemies_near(player.global_position, 4.0):
				enemy.call("take_damage", 22.0)
				enemy.call("apply_player_push", (enemy.global_position - player.global_position).normalized(), 5.0)
		"parasite":
			var targets := _enemies_near(player.global_position, 12.0, true)
			if not targets.is_empty(): targets[0].call("apply_mutation_poison", 6.0, 6.0, true)
		"living_harvest", "overload", "storm_pulse", "bone_blades", "berserk":
			_start_buff(skill_id, 6.0 if skill_id != "berserk" else 8.0)
		"discharge":
			var chain: Array[Vector3] = [player.global_position]
			for enemy in _enemies_near(player.global_position, 9.0, true):
				chain.append(enemy.global_position)
				enemy.call("take_damage", 25.0)
				enemy.call("apply_blast_stun", 1.0, 0.8)
				if chain.size() == 5: break
			vfx.chain_lightning(chain)
		"acid_spit":
			acid_pools.append({"position": player.get("_aim_point"), "remaining": 6.0})
			vfx.acid_pool(player.get("_aim_point"), 2.2, 6.0)
		"spore_cocoon":
			var location: Vector3 = player.get("_aim_point")
			vfx.spore_cocoon(location, 3.0, 2.0)
			get_tree().create_timer(2.0).timeout.connect(_release_spores.bind(location))
		"epidemic":
			for enemy in _enemies_near(player.global_position, 15.0):
				if float(enemy.get("mutation_poison_remaining")) > 0.0:
					for neighbor in _enemies_near(enemy.global_position, 3.5): neighbor.call("apply_mutation_poison", 3.0, 4.0)
		"predator_dash":
			player.call("mutation_dash")
			vfx.dash_trail(0.4)
			_dash_struck.clear()
			buffs["predator_dash"] = DASH_STRIKE_TIME
			_dash_strike()


# Hits enemies along the dash path instead of a ring around the start point.
func _dash_strike() -> void:
	var heading: Vector3 = player.get("_roll_direction")
	for enemy in _enemies_near(player.global_position, DASH_REACH + 0.6):
		var offset := enemy.global_position - player.global_position
		offset.y = 0.0
		if _dash_struck.has(enemy.get_instance_id()) or offset.length() - _body_radius(enemy) > DASH_REACH:
			continue
		if heading.length_squared() > 0.0 and offset.length() > 0.3 and offset.normalized().dot(heading) < -0.2:
			continue
		_dash_struck[enemy.get_instance_id()] = true
		enemy.call("take_damage", DASH_DAMAGE)


func _enemies_near(center: Vector3, radius: float, nearest_first: bool = false) -> Array[Node3D]:
	var result: Array[Node3D] = []
	for node in get_tree().get_nodes_in_group("infected"):
		if node is Node3D and (node as Node3D).global_position.distance_squared_to(center) <= radius * radius and float(node.get("health")) > 0.0:
			result.append(node as Node3D)
	if nearest_first:
		result.sort_custom(func(a: Node3D, b: Node3D) -> bool: return a.global_position.distance_squared_to(center) < b.global_position.distance_squared_to(center))
	return result


func _heal_or_armor(amount: float) -> void:
	var gained: float = player.call("heal", amount)
	if gained < amount:
		buffs["temporary_armor"] = minf(35.0, float(buffs.get("temporary_armor", 0.0)) + amount - gained)
		vfx.energy_shield()
