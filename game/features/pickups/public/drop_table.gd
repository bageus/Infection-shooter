extends Node

const MEDKIT := preload("res://game/features/pickups/public/medkit_pickup.tscn")
const PISTOL := preload("res://game/features/pickups/public/ammo_pistol_pickup.tscn")
const UZI := preload("res://game/features/pickups/public/ammo_uzi_pickup.tscn")
const SHOTGUN := preload("res://game/features/pickups/public/ammo_shotgun_pickup.tscn")
const ANTIDOTE := preload("res://game/features/pickups/public/antidote_pickup.tscn")

const DROP_LIFETIME := 75.0
const MAX_DROPS := 40
const DROP_GROUP := &"enemy_drops"
## Dropped supplies are half the size of placed ones.
const DROP_SCALE := 0.5
## Centre-to-centre gap that keeps two half-size drops from overlapping.
const DROP_SPACING := 0.7
## Rings searched around the kill for a free spot, and spots per ring.
const SPOT_RINGS := 3
const SPOTS_PER_RING := 8
const WALL_MASK := 129

# 65% of infected drop something: common supplies are plentiful without making every kill a drop.
@export_range(0.0, 1.0) var any_drop_chance := 0.65
# Antidote is deliberately less common than health/ammo.
@export_range(0.0, 1.0) var antidote_weight := 0.35

func drop_for_enemy(world: Node, at: Vector3) -> void:
	if randf() > any_drop_chance:
		return
	var common := [MEDKIT, PISTOL, UZI, SHOTGUN]
	var scene: PackedScene
	# Common items have equal weight; antidote is 0.35 of one common item's weight.
	var roll := randf() * (4.0 + antidote_weight)
	if roll >= 4.0:
		scene = ANTIDOTE
	else:
		scene = common[mini(int(floor(roll)), 3)]
	var spot := free_spot(world, at)
	var item := scene.instantiate()
	world.add_child(item)
	var visual := item.get_node_or_null("Visual") as Node3D
	if visual != null:
		visual.scale *= DROP_SCALE
	item.global_position = spot
	item.call("settle_on_floor")
	# Drops do not pile up forever: they fade after a while, oldest first.
	item.call("expire_after", DROP_LIFETIME)
	item.add_to_group(DROP_GROUP)
	var drops := world.get_tree().get_nodes_in_group(DROP_GROUP)
	if drops.size() > MAX_DROPS:
		(drops[0] as Node).queue_free()


## The kill point, or the nearest spot around it that no other drop covers
## and that a wall does not separate from the kill.
static func free_spot(world: Node, at: Vector3) -> Vector3:
	var taken: Array[Vector3] = []
	for drop in world.get_tree().get_nodes_in_group(DROP_GROUP):
		if drop is Node3D and not (drop as Node).is_queued_for_deletion():
			taken.append((drop as Node3D).global_position)
	if _clear_of(taken, at):
		return at
	var space: PhysicsDirectSpaceState3D = null
	if world is Node3D and (world as Node3D).get_world_3d() != null:
		space = (world as Node3D).get_world_3d().direct_space_state
	var turn := randf() * TAU
	for ring in range(1, SPOT_RINGS + 1):
		for index in SPOTS_PER_RING:
			var angle := turn + TAU * float(index) / float(SPOTS_PER_RING)
			var spot := at + Vector3(cos(angle), 0.0, sin(angle)) * DROP_SPACING * float(ring)
			if _clear_of(taken, spot) and _reachable(space, at, spot):
				return spot
	return at


static func _clear_of(taken: Array[Vector3], spot: Vector3) -> bool:
	for other in taken:
		if Vector2(other.x - spot.x, other.z - spot.z).length() < DROP_SPACING and absf(other.y - spot.y) < 1.5:
			return false
	return true


static func _reachable(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> bool:
	if space == null:
		return true
	var lift := Vector3.UP * 0.3
	var query := PhysicsRayQueryParameters3D.create(from + lift, to + lift, WALL_MASK)
	var skipped: Array[RID] = []
	for attempt in 8:
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return true
		var body := hit.get("collider") as Object
		if not (body is CharacterBody3D or body is RigidBody3D):
			return false
		skipped.append(hit["rid"])
		query.exclude = skipped
	return false
