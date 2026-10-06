extends Node

# Host-side effects. The infection runtime owns selection and cooldown state.
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

var effects_root: Node3D


func configure_world(container: Node3D) -> void:
	effects_root = container


func configure(host: CharacterBody3D, infection: Node, guns: Array[Node3D]) -> void:
	player = host
	runtime = infection
	weapons = guns
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


func _refresh_stats() -> void:
	var next_max := 125.0 if enabled("hypertrophy") else 100.0
	player.set("max_health", next_max)
	player.set("health", minf(float(player.get("health")), next_max))
	_update_weapons()


func enabled(skill_id: String) -> bool:
	return bool(runtime.call("has_skill", skill_id))


func _process(delta: float) -> void:
	heart_cooldown = maxf(0.0, heart_cooldown - delta)
	melee_cooldown = maxf(0.0, melee_cooldown - delta)
	kill_timer = maxf(0.0, kill_timer - delta)
	if kill_timer == 0.0:
		kill_streak = 0
	for key in buffs.keys():
		var previous := float(buffs[key])
		buffs[key] = maxf(0.0, previous - delta)
		if previous > 0.0 and float(buffs[key]) == 0.0 and key in WEAPON_BUFFS:
			_weapons_dirty = true
	if enabled("regeneration") and Time.get_ticks_msec() * 0.001 - last_hit_time > 5.0:
		player.call("heal", 1.4 * delta)
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
	if enabled("retaliation") and amount >= 20.0:
		for enemy in _enemies_near(player.global_position, 3.0):
			enemy.call("apply_blast_stun", 1.2, 0.6)
	return amount * (1.0 - minf(0.75, reduction))


func survive_lethal() -> bool:
	if not enabled("second_heart") or heart_cooldown > 0.0:
		return false
	heart_cooldown = 110.0
	last_hit_time = -100.0
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
		enemy.call("take_damage", 36.0 if enabled("claws") else 17.0)
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
			_indicator(player.global_position, Color(0.7, 0.04, 0.15, 0.45), 0.4, 4.0)
			for enemy in _enemies_near(player.global_position, 4.0):
				enemy.call("take_damage", 22.0)
				enemy.call("apply_player_push", (enemy.global_position - player.global_position).normalized(), 5.0)
		"parasite":
			var targets := _enemies_near(player.global_position, 12.0, true)
			if not targets.is_empty(): targets[0].call("apply_mutation_poison", 6.0, 6.0, true)
		"living_harvest", "overload", "storm_pulse", "bone_blades", "berserk":
			_start_buff(skill_id, 6.0 if skill_id != "berserk" else 8.0)
		"discharge":
			_indicator(player.global_position, Color(0.12, 0.73, 1.0, 0.55), 0.35, 3.0)
			var count := 0
			for enemy in _enemies_near(player.global_position, 9.0, true):
				enemy.call("take_damage", 25.0)
				enemy.call("apply_blast_stun", 1.0, 0.8)
				count += 1
				if count == 4: break
		"acid_spit":
			acid_pools.append({"position": player.get("_aim_point"), "remaining": 6.0})
			_indicator(player.get("_aim_point"), Color(0.25, 0.94, 0.04, 0.45), 6.0, 2.1)
		"spore_cocoon":
			var location: Vector3 = player.get("_aim_point")
			_indicator(location, Color(0.71, 0.77, 0.12, 0.45), 3.0, 2.6)
			get_tree().create_timer(2.0).timeout.connect(_release_spores.bind(location))
		"epidemic":
			for enemy in _enemies_near(player.global_position, 15.0):
				if float(enemy.get("mutation_poison_remaining")) > 0.0:
					for neighbor in _enemies_near(enemy.global_position, 3.5): neighbor.call("apply_mutation_poison", 3.0, 4.0)
		"predator_dash":
			player.call("mutation_dash")
			for enemy in _enemies_near(player.global_position, 2.5): enemy.call("take_damage", 30.0)


func _indicator(location: Vector3, tint: Color, duration: float, diameter: float) -> void:
	if not is_instance_valid(effects_root):
		return
	var ring := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = diameter * 0.5
	disc.bottom_radius = diameter * 0.5
	disc.height = 0.02
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	disc.material = material
	ring.mesh = disc
	effects_root.add_child(ring)
	ring.global_position = location + Vector3.UP * 0.06
	ring.create_tween().tween_callback(ring.queue_free).set_delay(duration)


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
