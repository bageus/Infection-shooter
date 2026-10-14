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

var tier := 0
var breaching := false
var _breach_left := 0.0
var _stuck_time := 0.0
var _last_position := Vector3.INF


# Tier an infected needs to hit this collider; 0 means it is not a target.
static func required_tier(collider: Object) -> int:
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
func blocking_collider(actor: CharacterBody3D, heading: Vector3) -> Dictionary:
	if tier <= 0 or heading.is_zero_approx():
		return {}
	for i in actor.get_slide_collision_count():
		var collision := actor.get_slide_collision(i)
		var collider := collision.get_collider()
		if collider == null or not can_break(collider):
			continue
		if breaching or -collision.get_normal().dot(heading) > 0.5:
			return {"collider": collider, "position": collision.get_position()}
	return {}


# Hits the prop in the way, if any; true when a blow landed.
func smash(actor: CharacterBody3D, target: Node3D) -> bool:
	var heading := target.global_position - actor.global_position
	heading.y = 0.0
	var block := blocking_collider(actor, heading.normalized())
	if block.is_empty():
		return false
	var collider: Object = block["collider"]
	collider.call("take_melee_hit", float(actor.get("obstacle_damage")), block["position"], -actor.global_transform.basis.z)
	return true
