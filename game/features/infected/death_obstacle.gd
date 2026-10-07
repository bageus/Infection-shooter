extends RefCounted
## A killed infected that falls against a wall or furniture takes it into
## account (ADR-0034 addition). Before the fall, a wall close in front turns
## the fall to the nearest free side, and a body boxed in on every side
## collapses where it stands. During the fall, once the body reaches a table
## top or another ledge the death clip stops there and the corpse stays lying
## across it; against a wall further away the feet slip back so the body ends
## at the foot of the wall. Light movable props in the way are shoved aside.
## Presentation only; it never changes gameplay.

const DEATH_FALL := preload("res://game/features/infected/death_fall.gd")
const WORLD_MASK := 1
## Room a standard-size body needs to fall full length, in metres.
const FALL_LENGTH := 1.6
## An obstacle closer than this share of FALL_LENGTH turns the fall aside
## (leaning upright against a near wall reads as standing, not fallen).
const CRAMPED_SHARE := 0.75
## Side turns tried in order, closest to the original fall first.
const SIDE_TURNS := [PI / 3.0, -PI / 3.0, 2.0 * PI / 3.0, -2.0 * PI / 3.0, PI]
## Props lighter than this (physical mass) are shoved, not leaned against.
const SHOVE_MAX_MASS := 12.0
const SHOVE_SPEED := 1.4
## Hits this close above the feet are the floor, not an obstacle.
const FLOOR_CLEARANCE := 0.14
## The head reaches this far past its bone, per metre of body height.
const HEAD_REACH := 0.1
## Surfaces steeper than this (|normal.y| below it) count as walls.
const WALL_NORMAL_Y := 0.5

var _body: CharacterBody3D
var _skeleton: Skeleton3D
var _player: AnimationPlayer
var _visual: Node3D
var _bones := {}
var _floor_y := 0.0
var _remaining := 0.0
var _excluded: Array[RID] = []
var _direction := Vector3.ZERO
var _reach := 0.0
var _chest_height := 0.0
var frozen := false


## Turns a fall that would hit a wall straight away; returns the fall result
## of DEATH_FALL.resolve() with state, turn and slide adjusted.
static func adjust(body: CharacterBody3D, parts: Node, fall: Dictionary, size: float) -> Dictionary:
	var slide: Vector3 = fall["slide"]
	var skeleton := _skeleton_of(parts)
	var bones := _humanoid_bones(skeleton)
	if fall["state"] == DEATH_FALL.DEATH or slide.is_zero_approx() or bones.is_empty() or not body.is_inside_tree():
		return fall
	var need := FALL_LENGTH * size
	var direction := slide.normalized()
	if _clearance(body, skeleton, bones, direction, need) >= need * CRAMPED_SHARE:
		return fall
	for turn: float in SIDE_TURNS:
		var side := direction.rotated(Vector3.UP, turn)
		if _clearance(body, skeleton, bones, side, need) >= need:
			return {"state": fall["state"], "turn": float(fall["turn"]) + turn, "slide": slide.rotated(Vector3.UP, turn)}
	return {"state": DEATH_FALL.DEATH, "turn": 0.0, "slide": Vector3.ZERO}


## Starts watching the falling body; false when it cannot be tracked.
func start(body: CharacterBody3D, parts: Node, animation: Node, fall: Dictionary, length: float) -> bool:
	_skeleton = _skeleton_of(parts)
	_bones = _humanoid_bones(_skeleton)
	_player = animation.get("animation_player") as AnimationPlayer if animation != null else null
	if _bones.is_empty() or _player == null or length <= 0.0 or not body.is_inside_tree():
		return false
	_body = body
	_visual = body.get("body_visual") as Node3D
	if _visual == null:
		return false
	_remaining = length
	_excluded = [body.get_rid()]
	_direction = (fall["slide"] as Vector3).normalized()
	_floor_y = minf(_point(_skeleton, _bones["foot_l"]).y, _point(_skeleton, _bones["foot_r"]).y) - 0.05
	_reach = HEAD_REACH * maxf(_point(_skeleton, _bones["head"]).y - _floor_y, 0.5)
	_chest_height = _point(_skeleton, _bones["chest"]).y - _floor_y
	return true


## One physics step of the fall; false once there is nothing left to watch.
func step(delta: float) -> bool:
	_remaining -= delta
	if frozen or _remaining <= 0.0 or not is_instance_valid(_body) or not _body.is_inside_tree():
		return false
	var hips := _point(_skeleton, _bones["hips"])
	var chest := _point(_skeleton, _bones["chest"])
	var head := _point(_skeleton, _bones["head"])
	var feet := (_point(_skeleton, _bones["foot_l"]) + _point(_skeleton, _bones["foot_r"])) * 0.5
	feet.y = maxf(feet.y, _floor_y + FLOOR_CLEARANCE + 0.05)
	# The body as a chain from the feet to the top of the head: whichever
	# link meets an obstacle first stops the fall (rays never see a box they
	# start inside, so the hips alone could slip over a table top).
	var chain: Array[Vector3] = [feet, hips, chest, head + (head - chest).normalized() * _reach]
	for link in chain.size() - 1:
		var hit := _blocking_hit(chain[link], chain[link + 1])
		if hit.is_empty():
			continue
		var normal: Vector3 = hit["normal"]
		if absf(normal.y) < WALL_NORMAL_Y and not _is_low(hit):
			# A wall: the feet slip back so the body finishes its fall
			# lying at the foot of the wall instead of leaning on it upright.
			var away := Vector3(normal.x, 0.0, normal.z).normalized()
			_visual.global_position += away * (maxf(((hit["position"] as Vector3) - chain[link + 1]).dot(away), 0.0) + 0.03)
			return true
		# The body rests on a table or a ledge: the fall stops in this pose.
		_player.pause()
		frozen = true
		return false
	return true


# A face whose top is below the standing chest is a table, a counter or a
# couch the body can fall over, not a wall: a ray down just inside it finds
# the top (inside a wall it finds nothing).
func _is_low(hit: Dictionary) -> bool:
	var at: Vector3 = hit["position"]
	var normal: Vector3 = hit["normal"]
	var inside := at - Vector3(normal.x, 0.0, normal.z).normalized() * 0.06
	var query := PhysicsRayQueryParameters3D.create(Vector3(inside.x, _floor_y + _chest_height, inside.z), Vector3(inside.x, at.y, inside.z), WORLD_MASK, _excluded)
	return not _body.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _blocking_hit(from: Vector3, to: Vector3) -> Dictionary:
	var space := _body.get_world_3d().direct_space_state
	for attempt in 3:
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, WORLD_MASK, _excluded))
		if hit.is_empty() or (hit["position"] as Vector3).y < _floor_y + FLOOR_CLEARANCE:
			return {}
		var collider := hit["collider"] as Object
		if collider is CharacterBody3D:
			_excluded.append(hit["rid"])
			continue
		var prop := collider as RigidBody3D
		if prop != null and not prop.freeze and prop.mass < SHOVE_MAX_MASS:
			_shove(prop, hit["position"])
			continue
		return hit
	return {}


func _shove(prop: RigidBody3D, at: Vector3) -> void:
	_excluded.append(prop.get_rid())
	var away := _direction if not _direction.is_zero_approx() else Vector3(at.x - _body.global_position.x, 0.0, at.z - _body.global_position.z).normalized()
	prop.sleeping = false
	prop.apply_impulse((away + Vector3.UP * 0.2).normalized() * prop.mass * SHOVE_SPEED, at - prop.global_position)


# Free horizontal room in a direction at hip and chest height.
static func _clearance(body: CharacterBody3D, skeleton: Skeleton3D, bones: Dictionary, direction: Vector3, need: float) -> float:
	var space := body.get_world_3d().direct_space_state
	var free := need
	for bone in [bones["hips"], bones["chest"]]:
		var from := _point(skeleton, bone)
		var query := PhysicsRayQueryParameters3D.create(from, from + direction * need, WORLD_MASK, [body.get_rid()])
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			continue
		var collider := hit["collider"] as Object
		if collider is CharacterBody3D:
			continue
		var prop := collider as RigidBody3D
		if prop != null and not prop.freeze and prop.mass < SHOVE_MAX_MASS:
			continue
		free = minf(free, from.distance_to(hit["position"]))
	return free


static func _skeleton_of(parts: Node) -> Skeleton3D:
	return parts.get("skeleton") as Skeleton3D if parts != null else null


static func _humanoid_bones(skeleton: Skeleton3D) -> Dictionary:
	if skeleton == null:
		return {}
	var bones := {"hips": skeleton.find_bone("Hips"), "chest": skeleton.find_bone("Chest"), "head": skeleton.find_bone("Head"),
		"foot_l": skeleton.find_bone("L_Foot"), "foot_r": skeleton.find_bone("R_Foot")}
	for bone: int in bones.values():
		if bone < 0:
			return {}
	return bones


static func _point(skeleton: Skeleton3D, bone: int) -> Vector3:
	return skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin
