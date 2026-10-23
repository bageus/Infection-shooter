extends SceneTree
## Regression coverage for the owner-approved issue7 mechanics and card data.
const EFFECTS := preload("res://game/features/player/mutation_skill_effects.gd")
const PISTOL := preload("res://game/features/combat/public/pistol.tscn")
const CONSUMABLES := preload("res://game/features/player/player_consumables.gd")
var failures := 0
var host: Host
var effects: Node
var runtime: Runtime
var gun: Node3D

class Host extends CharacterBody3D:
	signal healed(amount: float, source: StringName)
	var health := 100.0
	var max_health := 100.0
	var armor := 25.0
	var _wound := 0.0
	var mutation_effects: Node
	var weapons: Array[Node3D] = []
	func get_current_weapon() -> Node3D:
		return weapons[0]
	func heal(amount: float) -> float:
		return CONSUMABLES.heal(self, amount)

class Runtime extends Node:
	signal skill_cast(id: String)
	@warning_ignore("unused_signal")
	signal tree_changed
	@warning_ignore("unused_signal")
	signal mutation_changed(amount: float, threshold: float)
	var skills: Dictionary = {}
	var recovery := 0.0
	func has_skill(id: String) -> bool:
		return skills.has(id)
	func reduce_skill_cooldowns(delta: float) -> void:
		recovery += delta

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	host = Host.new()
	root.add_child(host)
	runtime = Runtime.new()
	host.add_child(runtime)
	gun = PISTOL.instantiate()
	host.add_child(gun)
	gun.set_process(false)
	host.weapons = [gun]
	effects = EFFECTS.new()
	host.add_child(effects)
	effects.set_process(false)
	effects.configure(host, runtime, host.weapons)
	host.mutation_effects = effects
	_passive_values()
	_ammunition()
	_devourer()
	_hyperactive()
	_resistance()
	_consumables()
	host.queue_free()
	await process_frame
	print("Issue7 passive tests: %d failures" % failures)
	quit(failures)

func _reset(ids: Array) -> void:
	runtime.skills.clear()
	for id in ids:
		runtime.skills[id] = true
	effects.buffs.clear()
	effects.battle_stacks = 0
	effects.hybrids.hyper_left = -1.0
	effects.hybrids.hyper_cooldown = 0.0
	effects.hybrids.organic_cooldown = 0.0
	effects.hybrids.absorption = 0.0
	host.health = 100.0
	runtime.tree_changed.emit()

func _passive_values() -> void:
	_reset(["hypertrophy", "synapses", "blood_scent", "regeneration"])
	_check(is_equal_approx(host.max_health, 115.0), "Hypertrophy adds fifteen percent")
	_check(is_equal_approx(effects.movement_multiplier(), 1.2), "Synapses adds twenty percent")
	var enemy := Host.new()
	enemy.health = 99.0
	_check(is_equal_approx(effects._scented(enemy, 10.0), 13.0), "Even slightly wounded targets take thirty percent more")
	enemy.free()
	effects.last_hit_time = effects._clock
	effects._process(4.0)
	_check(host.health == 100.0, "No regeneration before the four-second delay")
	effects._process(1.0)
	_check(host.health == 103.0, "Regeneration restores three health per second")

func _ammunition() -> void:
	_reset(["killer_instinct"])
	gun.set("_magazine_ammo", 0)
	gun.get("_reserve").amount = 3
	var victim := Node3D.new()
	effects.on_enemy_killed(victim)
	_check(gun.get_magazine_ammo() == 3 and gun.get_reserve_ammo() == 0, "Any kill transfers only available reserves")
	_check(effects.active_buff("killer_instinct"), "Any-distance kill doubles weapon damage")
	victim.free()
	_reset(["organic_ammo"])
	gun.set("_magazine_ammo", 0)
	host.health = 20.0
	effects._process(0.0)
	_check(host.health == 18.0 and gun.get_magazine_ammo() == gun.magazine_size, "At exactly twenty percent Organic Ammo costs two health")
	gun.set("_magazine_ammo", 0)
	effects._process(4.9)
	_check(gun.get_magazine_ammo() == 0, "Organic Ammo waits five seconds")
	effects._process(0.1)
	_check(host.health == 18.0 and gun.get_magazine_ammo() == gun.magazine_size, "Below twenty percent refill is free")
	_check(gun.get_reserve_ammo() == 0, "Organic Ammo never changes reserves")

func _devourer() -> void:
	_reset(["devourer", "assimilation"])
	host.health = 90.0
	effects.hybrids.cloud(1.0)
	_check(host.health == 92.0, "Cloud heals two HP/s without Assimilation multiplying it")
	host.health = host.max_health
	effects.hybrids.cloud(1.0)
	effects.hybrids.cloud(1.0)
	_check(effects.hybrids.absorption == 50.0 and host.armor == 25.0, "Cloud refresh caps absorption at fifty, separately from normal armor")
	_check(effects.on_player_hit(60.0) == 10.0, "Devourer absorbs up to fifty damage")
	effects.hybrids.cloud(0.1)
	effects._process(5.0)
	_check(effects.on_player_hit(10.0) == 10.0, "Devourer protection expires after five seconds")

func _hyperactive() -> void:
	_reset(["hyperactive"])
	var victim := Node3D.new()
	effects.on_enemy_killed(victim)
	_check(is_equal_approx(effects.movement_multiplier(), 1.2), "First kill enables Hyperactive")
	runtime.recovery = 0.0
	effects._process(1.0)
	_check(is_equal_approx(runtime.recovery, 1.0), "Recovery gains one extra second per second")
	effects.on_enemy_killed(victim)
	effects._process(0.5)
	_check(effects.hybrids.hyperactive(), "A kill at exactly one second maintains the series")
	effects._process(0.6)
	effects.on_enemy_killed(victim)
	_check(not effects.hybrids.hyperactive(), "A gap over one second starts an unskippable cooldown")
	effects._process(10.0)
	effects.on_enemy_killed(victim)
	_check(effects.hybrids.hyperactive(), "A new series can start after recovery")
	victim.free()

func _resistance() -> void:
	_reset(["bone_armor"])
	_check(is_equal_approx(effects.on_player_hit(130.0), 100.0), "Bone Armor divides damage by1.3 without rounding")
	_reset(["pain_block"])
	host.health = 20.0
	_check(effects.on_player_hit(10.0) == 10.0, "Pain Block is inactive at exactly twenty percent")
	host.health = 19.9
	_check(is_equal_approx(effects.on_player_hit(10.0), 6.0), "Pain Block reduces damage forty percent below threshold")
	_reset(["reactive_evolution"])
	effects._adapt_damage.clear()
	effects.on_player_hit(100.0, "fire")
	_check(not effects.active_buff("adapted_fire"), "Evolution never grants elemental resistance")
	effects.on_player_hit(50.0)
	_check(is_equal_approx(effects.on_player_hit(10.0), 7.0), "Fifty physical damage enables thirty-percent protection")
	effects._process(15.0)
	_check(effects.on_player_hit(10.0) == 10.0, "Evolution protection expires after fifteen seconds")

func _consumables() -> void:
	_reset(["assimilation"])
	host.health = 40.0
	_check(CONSUMABLES.heal(host, 20.0, &"medkit") == 30.0, "Medkits are fifty percent more effective")
	_check(CONSUMABLES.heal(host, 2.0) == 2.0, "Passive healing is unaffected")
	gun.get("_reserve").amount = 0
	_check(CONSUMABLES.add_ammo_for_weapon(host, "PISTOL", 10) == 15, "Ammo consumables gain fifty percent")

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
