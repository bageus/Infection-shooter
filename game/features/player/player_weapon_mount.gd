extends Node

const EQUIPMENT_POSE := preload("res://game/features/player/player_equipment_pose.gd")
var equipment_pose: SkeletonModifier3D
var skeleton: Skeleton3D
var socket: Node3D
var _remote: RemoteTransform3D
var _aim_target := Vector3.INF
var _active: Node3D
var _aim_modifying := false
var _hand := -1
var _socket_offset := Transform3D.IDENTITY


func _ready() -> void:
	var model := get_parent().get_node("Body")
	skeleton = _find_skeleton(model)
	if skeleton == null or skeleton.find_bone("RightHand") < 0:
		push_error("Player weapon mount requires Skeleton3D/RightHand")
		return
	socket = _find_socket(skeleton)
	if socket == null:
		var attachment := BoneAttachment3D.new()
		attachment.name = "RightHandWeaponAttachment"
		attachment.bone_name = "RightHand"
		skeleton.add_child(attachment)
		socket = Node3D.new()
		socket.name = "WeaponSocket_R"
		attachment.add_child(socket)
		push_warning("Character has no authored WeaponSocket_R; using hand origin")
	_hand = skeleton.find_bone("RightHand")
	var attachment_root := socket.get_parent()
	while attachment_root != null and not attachment_root is BoneAttachment3D:
		attachment_root = attachment_root.get_parent()
	if attachment_root is BoneAttachment3D:
		_socket_offset = (attachment_root as Node3D).global_transform.affine_inverse() * socket.global_transform
	equipment_pose = EQUIPMENT_POSE.new()
	equipment_pose.name = "EquipmentPose"
	equipment_pose.mount = self
	skeleton.add_child(equipment_pose)
	var aim := preload("res://game/features/player/player_body_aim.gd").new()
	aim.name = "BodyAim"
	aim.mount = self
	skeleton.add_child(aim)
	skeleton.skeleton_updated.connect(_sync_active)
	_remote = RemoteTransform3D.new()
	_remote.name = "ActiveWeaponTransform"
	_remote.update_scale = false
	_remote.update_rotation = false
	_remote.use_global_coordinates = true
	socket.add_child(_remote)


func select_weapon(weapon: Node3D) -> void:
	if socket == null or _remote == null:
		return
	_active = weapon
	_remote.remote_path = _remote.get_path_to(weapon)
	_remote.force_update_cache()
	sync_weapon(weapon)


func sync_weapon(weapon: Node3D) -> void:
	if not is_instance_valid(socket) or not socket.is_inside_tree() or not weapon.is_inside_tree():
		return
	# Also synchronize at the firing boundary, before pending transform notifications.
	if socket.get_parent() is BoneAttachment3D:
		_socket_offset = socket.transform
	var original_scale := weapon.scale
	var hand := skeleton.global_transform * skeleton.get_bone_global_pose(_hand) * _socket_offset if _aim_modifying else socket.global_transform
	weapon.global_transform = Transform3D(hand.basis.orthonormalized(), hand.origin)
	weapon.scale = original_scale


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


func _find_socket(node: Node) -> Node3D:
	if node.name == "WeaponSocket_R" and node is Node3D:
		return node as Node3D
	for child in node.get_children():
		var found := _find_socket(child)
		if found != null:
			return found
	return null


func aim_at(target: Vector3) -> void:
	_aim_target = target
	if is_instance_valid(_active):
		sync_weapon(_active)


func _sync_active() -> void:
	if is_instance_valid(_active):
		sync_weapon(_active)


func _exit_tree() -> void:
	if is_instance_valid(skeleton) and skeleton.skeleton_updated.is_connected(_sync_active):
		skeleton.skeleton_updated.disconnect(_sync_active)
