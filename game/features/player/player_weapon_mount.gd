extends Node

var skeleton: Skeleton3D
var socket: Node3D
var _remote: RemoteTransform3D


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
	_remote = RemoteTransform3D.new()
	_remote.name = "ActiveWeaponTransform"
	_remote.update_scale = false
	_remote.use_global_coordinates = true
	socket.add_child(_remote)


func select_weapon(weapon: Node3D) -> void:
	if socket == null or _remote == null:
		return
	_remote.remote_path = _remote.get_path_to(weapon)
	_remote.force_update_cache()
	sync_weapon(weapon)


func sync_weapon(weapon: Node3D) -> void:
	if socket == null:
		return
	# Also synchronize at the firing boundary, before pending transform notifications.
	var original_scale := weapon.scale
	weapon.global_transform = Transform3D(socket.global_basis.orthonormalized(), socket.global_position)
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
