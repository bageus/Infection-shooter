extends Area3D

enum PickupType { MEDKIT, AMMO_PISTOL, AMMO_UZI, AMMO_SHOTGUN, ANTIDOTE, DNA, AMMO_WEAPONS }

## Single size for every supply, placed in planning or dropped by infected.
const VISUAL_SCALE := 0.5
## Bounding volume of the regular ammo box (pistol, UZI, shotgun) at VISUAL_SCALE, in m³.
const SUPPLY_BOX_VOLUME := 0.0501

@export var pickup_type: PickupType = PickupType.MEDKIT
@export var amount: int = 20
## AMMO_WEAPONS only: the first listed weapon that takes the ammo receives it.
@export var weapon_names: PackedStringArray = PackedStringArray()
@export_flags_3d_physics var floor_mask := 129
@export_range(0.001, 0.05) var floor_clearance := 0.018
var _consumed := false
var _recheck := 0.0

func _ready() -> void:
	set_physics_process(false)
	set_process(false)
	var visual := get_node_or_null("Visual") as Node3D
	if visual != null:
		visual.scale *= VISUAL_SCALE
		if pickup_type == PickupType.AMMO_WEAPONS:
			visual.scale *= _supply_box_fit(visual)
	body_entered.connect(_on_body_entered)


## Removes an uncollected drop after `seconds`.
func expire_after(seconds: float) -> void:
	get_tree().create_timer(seconds, false).timeout.connect(func() -> void:
		if not _consumed:
			queue_free())


# A pickup refused on entry (full health/ammo) is offered again while the
# collector still stands on it, e.g. after taking damage.
func _process(delta: float) -> void:
	_recheck -= delta
	if _recheck > 0.0:
		return
	_recheck = 0.5
	var standing := false
	for body in get_overlapping_bodies():
		if body.has_method("heal") or body.has_method("add_ammo_for_weapon"):
			standing = true
			_on_body_entered(body)
	if not standing or _consumed:
		set_process(false)


# Called after the drop's world position is assigned. Queries run in physics.
func settle_on_floor() -> void:
	set_physics_process(true)


func _physics_process(_delta: float) -> void:
	set_physics_process(false)
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.5, global_position + Vector3.DOWN * 32.0, floor_mask)
	query.collide_with_areas = false
	var skipped: Array[RID] = [get_rid()]
	query.exclude = skipped
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
		# The property hands back a copy, so appending to it excluded nothing.
		skipped.append(receiver.get_rid())
		query.exclude = skipped
	queue_free()


# Larger weapon ammo models shrink uniformly to the regular box's volume, keeping their shape.
func _supply_box_fit(visual: Node3D) -> float:
	var bounds := AABB()
	var found := false
	for child in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		if mesh.mesh == null:
			continue
		var local := visual.global_transform.affine_inverse() * (mesh.global_transform * mesh.get_aabb())
		bounds = bounds.merge(local) if found else local
		found = true
	var volume := bounds.get_volume() * visual.scale.x * visual.scale.y * visual.scale.z
	return pow(SUPPLY_BOX_VOLUME / volume, 1.0 / 3.0) if found and volume > 0.0 else 1.0


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
				accepted = float(body.call("heal", float(amount), &"medkit")) > 0.0
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
		PickupType.DNA:
			var runtime: Object = body.get("infection_runtime")
			if runtime != null and runtime.has_method("add_control_ampule"):
				runtime.call("add_control_ampule")
				accepted = true
		PickupType.AMMO_WEAPONS:
			if body.has_method("add_ammo_for_weapon"):
				for weapon_name in weapon_names:
					if int(body.call("add_ammo_for_weapon", weapon_name, amount)) > 0:
						accepted = true
						break
	if accepted:
		_consumed = true
		_play_pickup_sound(body)
		queue_free()
	elif not is_processing():
		set_process(true)


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
		PickupType.DNA:
			body.call("play_item_sound", &"dna_pickup")
		_:
			body.call("play_item_sound", &"ammo_pickup")
