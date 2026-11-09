extends RefCounted
## Player-owned idle bleeding: a wounded player standing below half health
## keeps dripping blood onto the floor, faster as health falls.

const THRESHOLD := 0.5
var _timer := 0.0


func tick(player: Node, delta: float) -> void:
	var share: float = player.health / maxf(player.max_health, 1.0)
	if player.health <= 0.0 or share >= THRESHOLD or not player.is_wounded():
		_timer = 0.0
		return
	# A moving player already leaves a trail of drops, so only drip when standing.
	var velocity: Vector3 = player.velocity
	if Vector2(velocity.x, velocity.z).length() > 0.5:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	# Every 4 s at the threshold, every 0.8 s when health is almost gone.
	var severity := clampf(1.0 - share / THRESHOLD, 0.0, 1.0)
	_timer = lerpf(4.0, 0.8, severity) * randf_range(0.8, 1.2)
	var excluded: Array[RID] = [player.get_rid()]
	player.emit_signal("blood_wounded", player.global_position, excluded)
