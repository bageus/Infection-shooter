extends Area3D

enum PickupType { MEDKIT, AMMO_PISTOL, AMMO_UZI, AMMO_SHOTGUN, ANTIDOTE }

@export var pickup_type: PickupType = PickupType.MEDKIT
@export var amount: int = 20
@export_flags_3d_physics var floor_mask := 129
@export_range(0.001, 0.05) var floor_clearance := 0.018
var _consumed := false

func _ready() -> void:
	set_physics_process(false)
	body_entered.connect(_on_body_entered)


# Called after the drop's world position is assigned. Queries run in physics.
func settle_on_floor() -> void:
	set_physics_process(true)


func _physics_process(_delta: float) -> void:
	set_physics_process(false)
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.5, global_position + Vector3.DOWN * 32.0, floor_mask)
	query.collide_with_areas = false
	query.exclude = [get_rid()]
	for attempt in range(16):
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			# A drop above a floor opening must not remain floating in empty space.
			queue_free()
			return
		var receiver := hit.get("collider") as PhysicsBody3D
		if receiver != null and not receiver is CharacterBody3D and not receiver is RigidBody3D and (hit["normal"] as Vector3).y > 0.5:
			global_position.y = (hit["position"] as Vector3).y + floor_clearance - _visual_bottom_offset()
			return
		if receiver == null:
			break
		query.exclude.append(receiver.get_rid())
	queue_free()


func _visual_bottom_offset() -> float:
	var lowest := INF
	for child in find_children("*", "MeshInstance3D", true, false):
		var visual := child as MeshInstance3D
		if visual.mesh == null or not visual.is_visible_in_tree():
			continue
		var bounds := visual.get_aabb()
		for corner in range(8):
			var point := visual.global_transform * bounds.get_endpoint(corner)
			lowest = minf(lowest, point.y - global_position.y)
	return lowest if is_finite(lowest) else 0.0

func _on_body_entered(body: Node) -> void:
	if _consumed or body == null:
		return
	var accepted := false
	match pickup_type:
		PickupType.MEDKIT:
			if body.has_method("heal"):
				accepted = float(body.call("heal", float(amount))) > 0.0
		PickupType.AMMO_PISTOL:
			if body.has_method("add_ammo_for_weapon"):
				accepted = int(body.call("add_ammo_for_weapon", "PISTOL", amount)) > 0
		PickupType.AMMO_UZI:
			if body.has_method("add_ammo_for_weapon"):
				accepted = int(body.call("add_ammo_for_weapon", "UZI", amount)) > 0
		PickupType.AMMO_SHOTGUN:
			if body.has_method("add_ammo_for_weapon"):
				accepted = int(body.call("add_ammo_for_weapon", "SHOTGUN", amount)) > 0
		PickupType.ANTIDOTE:
			if body.has_method("add_antidote"):
				accepted = bool(body.call("add_antidote", amount))
	if accepted:
		_consumed = true
		_play_pickup_sound(body)
		queue_free()


# Sounds play on the collector, which outlives this pickup (ADR-0018).
func _play_pickup_sound(body: Node) -> void:
	if not body.has_method("play_item_sound"):
		return
	match pickup_type:
		PickupType.MEDKIT:
			body.call("play_item_sound", &"medkit_pickup")
			var collector: WeakRef = weakref(body)
			body.get_tree().create_timer(0.22).timeout.connect(func() -> void:
				var live := collector.get_ref() as Node
				if live != null:
					live.call("play_item_sound", &"medkit_use"))
		PickupType.ANTIDOTE:
			body.call("play_item_sound", &"antidote_pickup")
		_:
			body.call("play_item_sound", &"ammo_pickup")
