extends "res://game/presentation/office_floor/physical_prop.gd"

@export var leg_health := 28.0
@export var leg_hit_height := 0.48
@export var leg_edge_ratio := 0.30
@export var broken_leg_tilt_impulse := 4.5
@export var max_broken_legs := 4

var _broken_legs: Dictionary = {}
var _support_loss := 0.0

func _ready() -> void:
	super._ready()
	add_to_group("physical_tables")

func take_projectile_hit(damage: float, hit_position: Vector3, hit_normal: Vector3, direction: Vector3, weapon_name: String) -> bool:
	var local_hit := to_local(hit_position)
	if local_hit.y <= leg_hit_height:
		_damage_leg(local_hit, damage, direction, weapon_name)
	return super.take_projectile_hit(damage * 0.35, hit_position, hit_normal, direction, weapon_name)

func take_melee_hit(damage: float, hit_position: Vector3, direction: Vector3) -> void:
	var local_hit := to_local(hit_position)
	if local_hit.y <= leg_hit_height:
		_damage_leg(local_hit, damage * 1.25, direction, "MELEE")
	super.take_melee_hit(damage * 0.25, hit_position, direction)

func _damage_leg(local_hit: Vector3, damage: float, direction: Vector3, weapon_name: String) -> void:
	var leg_id := _leg_id(local_hit)
	if _broken_legs.has(leg_id):
		return
	var key := "leg_hp_" + leg_id
	var hp := float(get_meta(key, leg_health))
	var multiplier := 1.55 if weapon_name == "SHOTGUN" else 1.0
	hp -= maxf(damage, 0.0) * multiplier
	set_meta(key, hp)
	if hp <= 0.0:
		_break_leg(leg_id, local_hit, direction)

func _leg_id(local_hit: Vector3) -> String:
	var x := "R" if local_hit.x >= 0.0 else "L"
	var z := "B" if local_hit.z >= 0.0 else "F"
	return x + z

func _break_leg(leg_id: String, local_hit: Vector3, direction: Vector3) -> void:
	if _broken_legs.size() >= max_broken_legs:
		return
	_broken_legs[leg_id] = true
	sleeping = false
	var away := Vector3(local_hit.x, 0.0, local_hit.z)
	if away.length_squared() < 0.001:
		away = direction
	away.y = -0.35
	apply_impulse(away.normalized() * broken_leg_tilt_impulse, local_hit)
	_hide_nearest_leg_visual(local_hit)
	set_meta("broken_legs", _broken_legs.size())
	_support_loss = minf(1.0, float(_broken_legs.size()) / maxf(float(max_broken_legs), 1.0))
	angular_damp = lerpf(4.0, 1.2, _support_loss)
	linear_damp = lerpf(3.0, 2.0, _support_loss)
	if _broken_legs.size() >= 2:
		var torque_axis := Vector3(-local_hit.z, 0.0, local_hit.x).normalized()
		apply_torque_impulse(torque_axis * broken_leg_tilt_impulse * 0.65)

func _hide_nearest_leg_visual(local_hit: Vector3) -> void:
	var root := get_parent().get_node_or_null("Visual")
	if root == null:
		return
	var candidates: Array[MeshInstance3D] = []
	_collect_leg_meshes(root, candidates)
	if candidates.is_empty():
		return
	var best: MeshInstance3D
	var best_distance := INF
	for mesh in candidates:
		var p := to_local(mesh.global_position)
		var distance := Vector2(p.x - local_hit.x, p.z - local_hit.z).length_squared()
		if distance < best_distance:
			best_distance = distance
			best = mesh
	if best != null:
		best.visible = false

func _collect_leg_meshes(node: Node, result: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		var lower := node.name.to_lower()
		if "leg" in lower or "foot" in lower or "support" in lower:
			result.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_leg_meshes(child, result)
