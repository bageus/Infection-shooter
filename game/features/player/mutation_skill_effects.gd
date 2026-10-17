extends Node

# Host-side effects. The infection runtime owns selection and cooldown state.
const SKILL_VFX := preload("res://game/features/player/mutation_skill_vfx.gd")
const VFX_BUFFS := ["storm_pulse", "bone_blades", "berserk"]
var _active_effects := preload("res://game/features/player/active_mutation_effects.gd").new(self)
var player: CharacterBody3D
var runtime: Node
var weapons: Array[Node3D] = []
var baselines: Array[Dictionary] = []
var buffs: Dictionary = {}
var last_hit_time := -100.0
var heart_cooldown := 0.0
var kill_streak := 0
var kill_timer := 0.0
var battle_stacks := 0
var _alive_cache: Array = []
var _alive_frame := -1
var _alive_count := -1
## Seconds between melee strikes; reach is measured to the enemy's surface.
const MELEE_COOLDOWN := 0.5
const MELEE_REACH := 1.1
const WEAPON_BUFFS := ["overload", "combat_reflex", "battle_metabolism", "killer_instinct", "berserk", "reflex_arc"]
var _weapons_dirty := false
var _weapon_factors := Vector4.ZERO
var melee_cooldown := 0.0
var _melee_victim: WeakRef
var _melee_time := -100.0
var acid_pools: Array[Dictionary] = []
## Acid Spit pool radius: 3.4 m across.
const ACID_POOL_RADIUS := 1.7
## Acid probes walls above desk height and stops this far short of them.
const ACID_WALL_PROBE_HEIGHT := 1.5
const ACID_WALL_GAP := 0.35
const ACID_SURFACE_MASK := 129
const ACID_TIME := 4.0
const ACID_DPS := 6.0
var _clock := 0.0
var _blade_tick := 0.0
var _storm_tick := 0.0
var _claw_timer := 0.0
## Enemies the Claws pulse is about to kill, by instance id, with the time.
var _claw_kills: Dictionary = {}
var _recent_hits: Array[Vector2] = []
var _dash_struck: Dictionary = {}
var _adapt_damage: Dictionary = {}
var _regenerating := false

## Retaliation answers a burst of damage, not one heavy blow.
const RETALIATION_WINDOW := 3.0
const RETALIATION_DAMAGE := 50.0
const RETALIATION_STUN_RADIUS := 6.0
## Second Heart's emergency regeneration after a survived lethal hit.
const SECOND_HEART_HEAL := 10.0
const SECOND_HEART_DURATION := 5.0
const REGENERATION_DELAY := 4.0
## Predator Dash strikes everything it passes, once per dash.
const DASH_STRIKE_TIME := 0.45
const DASH_REACH := 1.6
const DASH_DAMAGE := 20.0
## Blood Burst reach (was 4 m; cut by 40%).
const BLOOD_BURST_RADIUS := 2.4
const BLOOD_BURST_DAMAGE := 20.0
## Claws: a pulse around the body every few seconds.
const CLAW_INTERVAL := 3.0
const CLAW_RADIUS := 1.5
const CLAW_DAMAGE := 25.0
const CLAW_KILL_WINDOW := 0.5
## Reactive Evolution: damage of one type builds a block for a while.
const ADAPT_THRESHOLD := 50.0
const ADAPT_DURATION := 15.0
## Bone Blades: 40 damage per second in a short radius.
const BLADE_TICK := 0.2
const BLADE_DAMAGE := 8.0
const BLADE_RADIUS := 2.2
## Storm Pulse: periodic shock and stun around the body.
const STORM_INTERVAL := 1.2
const STORM_RADIUS := 3.0
const STORM_DAMAGE := 3.0
const STORM_STUN := 2.0
const STORM_STUN_INTENSITY := 0.5
const SPORE_DELAY := 1.2
const SPORE_RADIUS := 3.0
const SPORE_DAMAGE := 30.0
const PARASITE_DPS := 5.0
const PARASITE_EXPLOSION := 40.0
const PARASITE_EXPLOSION_RADIUS := 3.0
const DISCHARGE_RANGE := 9.0
const DISCHARGE_CHAIN_RANGE := 6.0
const DISCHARGE_JUMPS := 6
const DISCHARGE_STEP_DAMAGE := 10.0
## Living Harvest: healing per second for its duration; overflow becomes armour.
const HARVEST_HEAL_PER_SECOND := 5.0
const ARMOR_CAP := 35.0
## Devourer: full health on a kill grants a short armour block.
const DEVOURER_ARMOR := 50.0
const DEVOURER_ARMOR_TIME := 5.0

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


func _spore_burst(location: Vector3) -> void:
	if not is_instance_valid(player) or player.is_queued_for_deletion():
		return
	for enemy in _enemies_near(location, SPORE_RADIUS):
		enemy.call("take_damage", SPORE_DAMAGE)
		enemy.call("apply_mutation_poison", 5.0, 5.0)


# Blood Scent: wounded enemies take extra damage from melee as well as bullets.
func _scented(enemy: Node3D, amount: float) -> float:
	if enabled("blood_scent") and float(enemy.get("health")) < float(enemy.get("max_health")) * 0.7:
		return amount * 1.22
	return amount


func _refresh_stats() -> void:
	_active_effects.cancel_unavailable()
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
			if key == "battle_metabolism":
				battle_stacks = 0
			if key == "devourer_armor":
				buffs["temporary_armor"] = 0.0
			if key in VFX_BUFFS:
				vfx.buff_ended(key)
	var regenerating := enabled("regeneration") and _clock - last_hit_time > REGENERATION_DELAY
	if regenerating:
		player.call("heal", 1.4 * delta)
	regenerating = regenerating and float(player.get("health")) < float(player.get("max_health"))
	if regenerating and not _regenerating:
		_passive("regeneration")
	_regenerating = regenerating
	if active_buff("second_heart"):
		player.call("heal", SECOND_HEART_HEAL * delta)
	if active_buff("living_harvest"):
		_harvest_tick(delta)
	# Hyperactive: a kill every second for five seconds doubles ability recovery.
	if enabled("hyperactive") and kill_streak >= 5 and kill_timer > 0.0:
		runtime.call("reduce_skill_cooldowns", delta)
	if active_buff("predator_dash"):
		_dash_strike()
	_claw_tick(delta)
	_active_effects.tick(delta)
	for i in range(acid_pools.size() - 1, -1, -1):
		var pool := acid_pools[i]
		pool["remaining"] = float(pool["remaining"]) - delta
		if float(pool["remaining"]) <= 0.0:
			acid_pools.remove_at(i)
			continue
		for enemy in _enemies_near(pool["position"], ACID_POOL_RADIUS):
			enemy.call("take_damage", ACID_DPS * delta)
	if _weapons_dirty:
		_update_weapons()


func active_buff(skill_id: String) -> bool:
	return float(buffs.get(skill_id, 0.0)) > 0.0


func on_player_hit(amount: float, damage_type: String = "physical") -> float:
	last_hit_time = _clock
	var reserve := float(buffs.get("temporary_armor", 0.0))
	var absorbed := minf(amount, reserve)
	buffs["temporary_armor"] = reserve - absorbed
	if absorbed > 0.0:
		vfx.energy_shield()
	amount -= absorbed
	var reduction := 0.0
	if damage_type == "physical":
		if enabled("bone_armor"):
			reduction += 0.20
			_passive("bone_armor")
		if enabled("hardened"):
			reduction += 0.17
			_passive("hardened")
	elif damage_type in ["acid", "fire", "electric"] and enabled("hardened"):
		reduction += 0.25
		_passive("hardened")
	if enabled("pain_block") and float(player.get("health")) < float(player.get("max_health")) * 0.25:
		reduction += 0.35
		_passive("pain_block")
	if active_buff("berserk"):
		reduction += 0.33
	if enabled("reactive_evolution"):
		var key := "adapted_" + damage_type
		if active_buff(key):
			reduction += 0.30
			_passive("reactive_evolution")
		else:
			var gathered := float(_adapt_damage.get(damage_type, 0.0)) + amount
			_adapt_damage[damage_type] = gathered
			if gathered >= ADAPT_THRESHOLD:
				_start_buff(key, ADAPT_DURATION)
				_adapt_damage[damage_type] = 0.0
	if enabled("retaliation") and _retaliation_due(amount):
		_passive("retaliation")
		vfx.electric_pulse(player.global_position, RETALIATION_STUN_RADIUS)
		for enemy in _enemies_near(player.global_position, RETALIATION_STUN_RADIUS):
			enemy.call("apply_blast_stun", 3.0, 1.0)
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
	heart_cooldown = 60.0
	last_hit_time = -100.0
	vfx.heartbeat()
	_passive_buff("second_heart", SECOND_HEART_DURATION)
	return true


func on_enemy_killed(enemy: Node3D) -> void:
	var id := enemy.get_instance_id()
	var claw_kill := _claw_kills.has(id) and _clock - float(_claw_kills[id]) <= CLAW_KILL_WINDOW
	_claw_kills.erase(id)
	# Predator skills reward kills made with a melee strike, as described.
	var melee_kill: bool = _melee_victim != null and _melee_victim.get_ref() == enemy and Time.get_ticks_msec() / 1000.0 - _melee_time < 0.5
	kill_streak = kill_streak + 1 if kill_timer > 0.0 else 1
	kill_timer = 1.0
	if enabled("combat_reflex"): _passive_buff("combat_reflex", 3.0)
	if enabled("battle_metabolism"): _battle_kill()
	if claw_kill and enabled("adrenaline"):
		_passive_buff("adrenaline", 4.0)
	if melee_kill and enabled("killer_instinct"):
		(player.call("get_current_weapon") as Node3D).call("add_magazine_ammo", 9999)
		_passive_buff("killer_instinct", 2.0)
	if enabled("devourer") and float(player.get("health")) >= float(player.get("max_health")):
		buffs["temporary_armor"] = maxf(float(buffs.get("temporary_armor", 0.0)), DEVOURER_ARMOR)
		_passive_buff("devourer_armor", DEVOURER_ARMOR_TIME)
		_passive("devourer")
	if active_buff("berserk"): _start_buff("berserk", minf(12.0, float(buffs["berserk"]) + 1.0))
	if enemy.has_meta("mutation_infection_death"):
		vfx.spike_burst(enemy.global_position, 4.0)
	if enabled("recycling") and randf() < 0.35:
		player.call("add_ammo_to_current_weapon", 5)
		_passive("recycling")


func movement_multiplier() -> float:
	var speed := 1.0
	if enabled("synapses"): speed += 0.15
	if active_buff("adrenaline"): speed += 0.5
	if enabled("hyperactive") and kill_streak >= 5 and kill_timer > 0.0: speed += 0.2
	if active_buff("overload"): speed += 0.3
	if active_buff("berserk"): speed += 0.5
	return speed


func on_roll() -> void:
	if enabled("reflex_arc"):
		_passive_buff("reflex_arc", 3.0)


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
		enemy.call("take_damage", _scented(enemy, 17.0))
		return true
	return false


static func _body_radius(body: Node) -> float:
	var shape := body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape != null and shape.shape is CapsuleShape3D:
		return (shape.shape as CapsuleShape3D).radius * absf(shape.global_basis.get_scale().x)
	return 0.4


# Reports a passive firing so the HUD can show which one worked.
func _passive(skill_id: String, duration: float = 0.0) -> void:
	if runtime.has_method("report_passive"):
		runtime.call("report_passive", skill_id, duration)


func _passive_buff(skill_id: String, duration: float) -> void:
	_start_buff(skill_id, duration)
	_passive(skill_id, duration)


# Lasting active effects are reported so the HUD can show their remaining time.
func _skill_effect(skill_id: String, duration: float) -> void:
	if runtime.has_method("report_skill_effect"):
		runtime.call("report_skill_effect", skill_id, duration)


func _start_buff(skill_id: String, duration: float) -> void:
	buffs[skill_id] = duration
	_skill_effect(skill_id, duration)
	if skill_id in WEAPON_BUFFS:
		_weapons_dirty = true
	if skill_id in VFX_BUFFS:
		vfx.buff_started(skill_id)


# Battle Metabolism: each kill inside the window adds a stack and extends it.
func _battle_kill() -> void:
	if active_buff("battle_metabolism"):
		battle_stacks = mini(3, battle_stacks + 1)
		_passive_buff("battle_metabolism", float(buffs["battle_metabolism"]) + 3.0)
	else:
		battle_stacks = 1
		_passive_buff("battle_metabolism", 3.0)


func _update_weapons() -> void:
	_weapons_dirty = false
	var reload_factor := (0.7 if enabled("muscle_memory") else 1.0) * (1.0 / 1.3 if active_buff("overload") else 1.0)
	var spread_factor := 0.7 if enabled("stabilizers") else 1.0
	var attack_speed := (1.3 if active_buff("combat_reflex") else 1.0) * (1.3 if active_buff("overload") else 1.0)
	if enabled("reflex_arc") and active_buff("reflex_arc"):
		attack_speed *= 1.25
	var damage := 1.0 + 0.05 * float(battle_stacks)
	if active_buff("killer_instinct"): damage *= 2.0
	if active_buff("berserk"): damage *= 1.5
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
		# Grenade blasts do not read bullet damage: they take the same damage bonus.
		if "explosion_damage_multiplier" in gun:
			gun.set("explosion_damage_multiplier", factors.w)


func _claw_tick(delta: float) -> void:
	_claw_timer -= delta
	if _claw_timer > 0.0 or not enabled("claws"):
		return
	_claw_timer = CLAW_INTERVAL
	for id in _claw_kills.keys():
		if _clock - float(_claw_kills[id]) > CLAW_KILL_WINDOW:
			_claw_kills.erase(id)
	for enemy in _enemies_near(player.global_position, CLAW_RADIUS):
		vfx.claw_slash(enemy)
		# Marked before the hit: a lethal hit reports its kill synchronously.
		if float(enemy.get("health")) <= CLAW_DAMAGE:
			_claw_kills[enemy.get_instance_id()] = _clock
		enemy.call("take_damage", CLAW_DAMAGE)


func _blade_and_storm_tick(delta: float) -> void:
	_blade_tick -= delta
	if _blade_tick <= 0.0:
		_blade_tick = BLADE_TICK
		if active_buff("bone_blades"):
			for enemy in _enemies_near(player.global_position, BLADE_RADIUS):
				enemy.call("take_damage", BLADE_DAMAGE)
	_storm_tick -= delta
	if _storm_tick <= 0.0:
		_storm_tick = STORM_INTERVAL
		if active_buff("storm_pulse"):
			for enemy in _enemies_near(player.global_position, STORM_RADIUS):
				enemy.call("take_damage", STORM_DAMAGE)
				enemy.call("apply_blast_stun", STORM_STUN, STORM_STUN_INTENSITY)


# Living Harvest heals per second; healing beyond full health becomes armour.
func _harvest_tick(delta: float) -> void:
	var amount := HARVEST_HEAL_PER_SECOND * delta
	var gained: float = player.call("heal", amount)
	var overflow := amount - gained
	if overflow > 0.0:
		buffs["temporary_armor"] = minf(ARMOR_CAP, float(buffs.get("temporary_armor", 0.0)) + overflow)
		vfx.energy_shield()


func _cast(skill_id: String) -> void:
	_active_effects.cast(skill_id)


func _dash_strike() -> void:
	_active_effects._dash()


## Where an Acid Spit aimed at `aim` lands: always on the floor the player
## stands on. An aim on a wall (or a body, or a desk top) is brought back to
## the floor in front of it, short of the wall.
func acid_floor_point(aim: Vector3) -> Vector3:
	var space := player.get_world_3d().direct_space_state
	var feet := player.global_position
	var ground := _environment_ray(space, feet, feet + Vector3.DOWN * 3.0)
	feet.y = (ground["position"] as Vector3).y if not ground.is_empty() else feet.y - 0.9
	var target := Vector3(aim.x, feet.y, aim.z)
	var lift := Vector3.UP * ACID_WALL_PROBE_HEIGHT
	# Reach a little past the aim so a point on a wall face still meets the wall.
	var past := (target - feet).normalized() * 0.2 if target.distance_squared_to(feet) > 0.0001 else Vector3.ZERO
	var hit := _environment_ray(space, feet + lift, target + past + lift)
	if not hit.is_empty():
		var wall := hit["position"] as Vector3
		wall.y = feet.y
		var back := feet - wall
		target = wall + back.normalized() * minf(ACID_WALL_GAP, back.length()) if back.length_squared() > 0.0001 else feet
	var down := _environment_ray(space, target + Vector3.UP * 0.6, target + Vector3.DOWN * 3.0)
	if not down.is_empty() and (down["normal"] as Vector3).y > 0.7 and absf((down["position"] as Vector3).y - feet.y) < 0.6:
		return down["position"]
	return target


# Static scenery only: the player, enemies and loose props never count.
func _environment_ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, ACID_SURFACE_MASK)
	var skipped: Array[RID] = [player.get_rid()]
	query.exclude = skipped
	for attempt in 8:
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return hit
		var body := hit.get("collider") as Object
		if not (body is CharacterBody3D or body is RigidBody3D):
			return hit
		skipped.append(hit["rid"])
		query.exclude = skipped
	return {}


# One group scan per frame: acid pools, dashes and epidemic all query it
# several times a frame. A spawn or removal rebuilds it; freed members are
# skipped when the list is read.
func _alive_enemies() -> Array:
	var frame := Engine.get_process_frames()
	var count := get_tree().get_node_count_in_group("infected_alive")
	if frame != _alive_frame or count != _alive_count:
		_alive_frame = frame
		_alive_count = count
		_alive_cache.clear()
		_alive_cache.assign(get_tree().get_nodes_in_group("infected_alive"))
	return _alive_cache


func _enemies_near(center: Vector3, radius: float, nearest_first: bool = false) -> Array[Node3D]:
	var result: Array[Node3D] = []
	var reach := radius * radius
	for node in _alive_enemies():
		if is_instance_valid(node) and node is Node3D and node.global_position.distance_squared_to(center) <= reach and float(node.get("health")) > 0.0:
			result.append(node as Node3D)
	if nearest_first:
		result.sort_custom(func(a: Node3D, b: Node3D) -> bool: return a.global_position.distance_squared_to(center) < b.global_position.distance_squared_to(center))
	return result
