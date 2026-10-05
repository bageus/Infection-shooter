extends Node

const MEDKIT := preload("res://game/features/pickups/public/medkit_pickup.tscn")
const PISTOL := preload("res://game/features/pickups/public/ammo_pistol_pickup.tscn")
const UZI := preload("res://game/features/pickups/public/ammo_uzi_pickup.tscn")
const SHOTGUN := preload("res://game/features/pickups/public/ammo_shotgun_pickup.tscn")
const ANTIDOTE := preload("res://game/features/pickups/public/antidote_pickup.tscn")

const DROP_LIFETIME := 75.0
const MAX_DROPS := 40
const DROP_GROUP := &"enemy_drops"

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
	var item := scene.instantiate()
	world.add_child(item)
	item.global_position = at
	item.call("settle_on_floor")
	# Drops do not pile up forever: they fade after a while, oldest first.
	item.call("expire_after", DROP_LIFETIME)
	item.add_to_group(DROP_GROUP)
	var drops := world.get_tree().get_nodes_in_group(DROP_GROUP)
	if drops.size() > MAX_DROPS:
		(drops[0] as Node).queue_free()
