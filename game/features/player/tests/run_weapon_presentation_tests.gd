extends SceneTree

const PLAYER := preload("res://game/features/player/public/player.tscn")
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var player := PLAYER.instantiate()
	root.add_child(player)
	await process_frame
	var model: Node3D = player.get_node("Body")
	_dump(model, model)
	for name in ["Pistol", "Uzi", "Shotgun", "GrenadeLauncher"]:
		var weapon: Node = player.get_node("AimPivot/" + name)
		_dump(weapon, weapon)
	player.queue_free()
	await process_frame
	await process_frame
	print("Weapon presentation tests: %d failures" % failures)
	quit(1 if failures > 0 else 0)


func _dump(node: Node, boundary: Node) -> void:
	if node is Skeleton3D:
		var skeleton := node as Skeleton3D
		var hand := skeleton.find_bone("RightHand")
		print("ASSET Skeleton3D: ", boundary.get_path_to(node), " RightHand=", hand)
		if hand < 0:
			failures += 1
	elif node is AnimationPlayer:
		print("ASSET AnimationPlayer: ", boundary.get_path_to(node), " clips=", node.get_animation_list())
	elif node is Node3D and node.name in ["WeaponSocket_R", "WeaponRoot", "Grip_R", "Grip_L", "Muzzle"]:
		print("ASSET marker: ", boundary.get_path_to(node), " type=", node.get_class(), " local=", node.transform)
	for child in node.get_children():
		_dump(child, boundary)
