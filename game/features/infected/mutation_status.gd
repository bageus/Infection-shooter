extends RefCounted
const B := preload("res://game/features/infection/public/mutation_balance.gd")
## Mutation poison and collision-limited displacement in metres.
var destination := Vector3.ZERO
var moving := false
var infectious := false


func poison(host: CharacterBody3D, duration: float, dps: float, parasite: bool) -> void:
	host.mutation_poison_remaining = maxf(host.mutation_poison_remaining, duration)
	host._mutation_poison_damage = maxf(host._mutation_poison_damage, dps)
	if not host._dead and host.status_fx != null:
		host.status_fx.poisoned(host.mutation_poison_remaining)
	if parasite:
		host.set_meta("mutation_parasite", true)


func push(host: CharacterBody3D, direction: Vector3, distance: float) -> void:
	if host._dead or distance <= 0.0:
		return
	direction.y = 0.0
	if direction.is_zero_approx():
		return
	destination = host.global_position + direction.normalized() * distance
	moving = true
	host._pending_hit = -1.0
	host._push_velocity = Vector3.ZERO
	host._set_death_push(direction.normalized() * 12.0)


func step(host: CharacterBody3D, delta: float) -> bool:
	if host.mutation_poison_remaining > 0.0 and not host._dead:
		var elapsed := minf(delta, host.mutation_poison_remaining)
		host.mutation_poison_remaining = maxf(0.0, host.mutation_poison_remaining - delta)
		var damage: float = host._mutation_poison_damage * elapsed
		var fatal: bool = infectious and damage >= host.health
		if fatal:
			host.set_meta("mutation_infection_death", true)
		host.take_damage(damage)
		if fatal and host._dead:
			for enemy in host.get_tree().get_nodes_in_group("infected_alive"):
				if enemy is Node3D and enemy.global_position.distance_squared_to(host.global_position) <= pow(B.value("blood_infection", "explosion_radius"), 2.0):
					enemy.take_damage(B.value("blood_infection", "explosion"))
		if host.mutation_poison_remaining <= 0.0:
			host._mutation_poison_damage = 0.0
			infectious = false
	if host._dead or not moving:
		return false
	var offset := destination - host.global_position
	offset.y = 0.0
	var motion := offset.limit_length(12.0 * delta)
	var collision := host.move_and_collide(motion)
	moving = collision == null and offset.length() > motion.length() + 0.001
	host.velocity = Vector3.ZERO
	return true


func stun(host: CharacterBody3D, duration: float, intensity: float) -> void:
	host._blast_stun_remaining = maxf(host._blast_stun_remaining, duration * maxf(intensity, 0.25))
	if not host._dead and host.status_fx != null:
		host.status_fx.stunned(host._blast_stun_remaining)


func scented_damage(target: Node, wounded: bool, amount: float) -> float:
	if wounded and is_instance_valid(target) and target.has_method("get_infection_skill") and bool(target.call("get_infection_skill", "blood_scent")):
		return amount * (1.0 + B.value("blood_scent", "percent") / 100.0)
	return amount
