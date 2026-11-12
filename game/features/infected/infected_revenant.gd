extends "res://game/features/infected/infected_capsule.gd"
## Revenant with a rare berserk state: after a few enemies die close by it may
## rage, running faster and hitting harder until it dies.

const BERSERK_RADIUS := 7.0
const BERSERK_KILLS := Vector2i(3, 4)
var berserk_chance := 0.4 # Test-settable: 0 and 1 make the roll deterministic.
const BERSERK_SPEED := 1.5
const BERSERK_DAMAGE := 1.5
const WATCH_INTERVAL := 0.25
const RAGE_SHADER := preload("res://game/features/infected/berserk_rage.gdshader")

var berserk := false
var _kills_needed := 0
var _kills_seen := 0
var _watch_left := 0.0
# Enemies seen within BERSERK_RADIUS, keyed by instance id, until they die or leave.
var _known := {}


func _ready() -> void:
	super._ready()
	_roll_kills_needed()


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if berserk or _dead:
		return
	_watch_left -= delta
	if _watch_left > 0.0:
		return
	_watch_left = WATCH_INTERVAL
	_scan_kills()


# Enemies die out of the alive group, so the ones seen nearby are remembered until they are seen dead.
func _scan_kills() -> void:
	for enemy: Node3D in get_tree().get_nodes_in_group(ALIVE_GROUP):
		if enemy != self and enemy.global_position.distance_to(global_position) <= BERSERK_RADIUS:
			_known[enemy.get_instance_id()] = enemy
	for id: int in _known.keys():
		var enemy: Node3D = _known[id]
		if not is_instance_valid(enemy) or enemy.global_position.distance_to(global_position) > BERSERK_RADIUS:
			_known.erase(id)
		elif enemy.call("is_dead"):
			_known.erase(id)
			_count_kill()


func _count_kill() -> void:
	_kills_seen += 1
	if _kills_seen < _kills_needed:
		return
	if randf() < berserk_chance:
		_start_berserk()
	else:
		_kills_seen = 0
		_roll_kills_needed()


func _roll_kills_needed() -> void:
	_kills_needed = randi_range(BERSERK_KILLS.x, BERSERK_KILLS.y)


func _start_berserk() -> void:
	berserk = true
	move_speed *= BERSERK_SPEED
	attack_damage *= BERSERK_DAMAGE
	var rage := ShaderMaterial.new()
	rage.shader = RAGE_SHADER
	for mesh: Node in body_visual.find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).material_overlay = rage
