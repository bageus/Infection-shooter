extends RefCounted
## Which props an infected may smash on its way to the player, by class.
## Tier 0 never attacks props; 1 smashes small things (chairs, pots, boxes,
## glass and wooden partitions); 2 smashes anything destructible.

const SMALL_TOKENS: Array[String] = [
	"chair", "stool", "plant", "pot", "vase", "box", "crate", "bin", "bucket", "trash",
	"divider", "partition", "glass", "paper", "bottle", "cooler",
]
const IGNORED_SCRIPTS: Array[String] = ["severed_part", "body_part_hitbox", "environment_fragment", "settled_debris"]
const GLASS_GROUP := "infected_breakable_glass"
const STUCK_SECONDS := 0.6
const STUCK_DISTANCE := 0.25
const BREACH_SECONDS := 2.5
## A distant target never makes a swing at the wall in front of it: only a confirmed breach or a close target does.
const SMASH_NEAR_DISTANCE := 6.0
## More than this many infected within CROWD_RADIUS of a blocking object: all of them smash it, whatever their tier.
const CROWD_COUNT := 5
const CROWD_RADIUS := 2.5
## An enemy that swung this many times at a prop which never moved gives up on it and treats it as a wall.
const MAX_SWINGS := 3
const MOVED_DISTANCE := 0.1

var tier := 0
var breaching := false
var _breach_left := 0.0
var _stuck_time := 0.0
var _last_position := Vector3.INF
var _swings := {} # prop instance id -> [swings, position at the first swing]
var _given_up := {} # prop instance ids this enemy no longer swings at


# Tier an infected needs to hit this collider; 0 means it is not a target.
static var _tier_cache := {}

static func required_tier(collider: Object) -> int:
	if collider == null or not is_instance_valid(collider):
		return 0
	var id := collider.get_instance_id()
	if not _tier_cache.has(id):
		if _tier_cache.size() > 2000:
			_tier_cache.clear()
		_tier_cache[id] = _compute_tier(collider)
	return _tier_cache[id]

static func _compute_tier(collider: Object) -> int:
	if not (collider is Node) or not collider.has_method("take_melee_hit"):
		return 0
	var node := collider as Node
	if node is CharacterBody3D or node.is_in_group("infected") or node.is_in_group("player") or node.is_in_group("contactless_debris"):
		return 0
	var script: Script = node.get_script()
	if script != null:
		for token in IGNORED_SCRIPTS:
			if token in script.resource_path:
				return 0
	if node.get("unbreakable") == true: # bulletproof glass: no blow breaks it, so enemies do not swing at it
		return 0
	if node.is_in_group(GLASS_GROUP):
		return 1
	var label := String(node.name)
	var parent := node.get_parent()
	if parent != null:
		label += " " + String(parent.name)
	label = label.to_lower()
	for token in SMALL_TOKENS:
		if token in label:
			return 1
	return 2


func can_break(collider: Object) -> bool:
	var need := required_tier(collider)
	return need > 0 and tier >= need


# Called while chasing; flags breaching once the infected has stood still on a blocked route.
func track_progress(actor: Node3D, delta: float, route_blocked: bool) -> void:
	if tier <= 0:
		return
	if breaching:
		_breach_left -= delta
		if _breach_left <= 0.0:
			breaching = false
			_stuck_time = 0.0
		return
	if not route_blocked:
		_stuck_time = 0.0
		_last_position = Vector3.INF
		return
	_stuck_time += delta
	if _stuck_time < STUCK_SECONDS:
		return
	var here := actor.global_position
	if _last_position != Vector3.INF and here.distance_to(_last_position) < STUCK_DISTANCE:
		breaching = true
		_breach_left = BREACH_SECONDS
	_last_position = here
	_stuck_time = 0.0


# First slide collision the infected can smash while pressing toward `heading`.
# A crowded blocking object is smashed by every infected pressing on it ("crowd" true in the result).
func blocking_collider(actor: CharacterBody3D, heading: Vector3) -> Dictionary:
	if heading.is_zero_approx():
		return {}
	for i in actor.get_slide_collision_count():
		var collision := actor.get_slide_collision(i)
		var collider := collision.get_collider()
		if collider == null or required_tier(collider) == 0 or _given_up.has(collider.get_instance_id()):
			continue
		if not (breaching or -collision.get_normal().dot(heading) > 0.5):
			continue
		var crowd := not can_break(collider) and _crowd_size(actor, collision.get_position()) > CROWD_COUNT
		if can_break(collider) or crowd:
			return {"collider": collider, "position": collision.get_position(), "crowd": crowd}
	return {}


# Infected (the actor included) standing within CROWD_RADIUS of a point.
static func _crowd_size(actor: Node3D, point: Vector3) -> int:
	var count := 0
	for node in actor.get_tree().get_nodes_in_group("infected"):
		if node is Node3D and node.is_inside_tree() and (node as Node3D).global_position.distance_to(point) <= CROWD_RADIUS:
			count += 1
	return count


# Counts a swing; a prop still where it was after MAX_SWINGS is given up on.
func _count_swing(collider: Object) -> void:
	var node := collider as Node3D
	if node == null:
		return
	if _swings.size() > 64:
		_swings.clear()
	var entry: Array = _swings.get(node.get_instance_id(), [0, node.global_position])
	entry[0] += 1
	_swings[node.get_instance_id()] = entry
	if entry[0] >= MAX_SWINGS and node.global_position.distance_to(entry[1] as Vector3) < MOVED_DISTANCE:
		_given_up[node.get_instance_id()] = true


# Hits the prop in the way, if any; true when a blow landed.
func smash(actor: CharacterBody3D, target: Node3D) -> bool:
	var heading := target.global_position - actor.global_position
	heading.y = 0.0
	var block := blocking_collider(actor, heading.normalized())
	if block.is_empty():
		return false
	var near := actor.global_position.distance_to(target.global_position) <= SMASH_NEAR_DISTANCE
	if not (breaching or near or block["crowd"]):
		return false
	var collider: Object = block["collider"]
	_count_swing(collider)
	collider.call("take_melee_hit", float(actor.get("obstacle_damage")), block["position"], -actor.global_transform.basis.z)
	return true
