extends Node
## Keeps a ragdoll physically sane (ADR-0041). Bones that start inside a wall,
## another body or the player can be thrown at hundreds of m/s and stretch like
## rubber while the whole body flies away. The guard clamps bone speeds, snaps
## the body back to its last healthy pose when a joint over-stretches, and
## freezes a body that keeps moving or keeps breaking. A resting body is only
## looked at twice a second.

const MAX_SPEED := 14.0
const MAX_SPIN := 24.0
## A joint may drift this far from its anatomical length before recovery.
const MAX_STRETCH := 0.3
const SNAPSHOT_SECONDS := 0.25
const QUIET_SPEED := 0.15
const QUIET_SECONDS := 0.5
## A body that never settles for this long is frozen where it lies.
const BUSY_LIMIT_SECONDS := 8.0
const MAX_STRIKES := 2
const BUSY_INTERVAL := 2
const QUIET_INTERVAL := 30

var bones: Array[PhysicalBone3D] = []
var _links: Array[Dictionary] = []
var _snapshot: Array[Transform3D] = []
var _snapshot_age := 0.0
var _busy := 0.0
var _quiet := 0.0
var _strikes := 0
var _since_check := 0
var frozen := false


func setup(volumes: Array[PhysicalBone3D], skeleton: Skeleton3D) -> void:
	bones = volumes
	_links.clear()
	_since_check = get_instance_id() % QUIET_INTERVAL
	var by_bone := {}
	for bone in bones:
		by_bone[bone.get_bone_id()] = bone
	for bone in bones:
		var parent: PhysicalBone3D = by_bone.get(skeleton.get_bone_parent(bone.get_bone_id()))
		if parent != null:
			_links.append({"child": bone, "parent": parent, "length": _joint(bone).distance_to(_joint(parent))})
	_take_snapshot()


func _physics_process(delta: float) -> void:
	_since_check += 1
	var interval := QUIET_INTERVAL if _quiet >= QUIET_SECONDS else BUSY_INTERVAL
	if _since_check < interval:
		return
	var step := delta * _since_check
	_since_check = 0
	var fastest := 0.0
	var broken := false
	for bone in bones:
		var velocity := bone.linear_velocity
		var spin := bone.angular_velocity
		if not (velocity.is_finite() and spin.is_finite() and bone.global_position.is_finite()):
			broken = true
			break
		fastest = maxf(fastest, velocity.length())
		if velocity.length_squared() > MAX_SPEED * MAX_SPEED:
			bone.linear_velocity = velocity.limit_length(MAX_SPEED)
		if spin.length_squared() > MAX_SPIN * MAX_SPIN:
			bone.angular_velocity = spin.limit_length(MAX_SPIN)
	if not broken:
		for link in _links:
			var stretch := absf(_joint(link["child"]).distance_to(_joint(link["parent"])) - float(link["length"]))
			if stretch > MAX_STRETCH:
				broken = true
				break
	if broken:
		_recover()
		return
	if fastest < QUIET_SPEED:
		_quiet += step
		if _quiet >= QUIET_SECONDS:
			_busy = 0.0
	else:
		_quiet = 0.0
		_busy += step
		if _busy > BUSY_LIMIT_SECONDS:
			freeze()
			return
	_snapshot_age += step
	if _snapshot_age >= SNAPSHOT_SECONDS:
		_take_snapshot()


func freeze() -> void:
	if frozen:
		return
	frozen = true
	set_physics_process(false)
	for bone in bones:
		if is_instance_valid(bone):
			bone.linear_velocity = Vector3.ZERO
			bone.angular_velocity = Vector3.ZERO
			bone.collision_mask = 0
			bone.gravity_scale = 0.0
			bone.linear_damp = 100.0
			bone.angular_damp = 100.0


func _recover() -> void:
	_strikes += 1
	for index in bones.size():
		bones[index].global_transform = _snapshot[index]
		bones[index].linear_velocity = Vector3.ZERO
		bones[index].angular_velocity = Vector3.ZERO
	_quiet = 0.0
	if _strikes >= MAX_STRIKES:
		freeze()


func _take_snapshot() -> void:
	_snapshot.clear()
	for bone in bones:
		_snapshot.append(bone.global_transform)
	_snapshot_age = 0.0


func _joint(bone: PhysicalBone3D) -> Vector3:
	return bone.global_transform * bone.body_offset.affine_inverse().origin
