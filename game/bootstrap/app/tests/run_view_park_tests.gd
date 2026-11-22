extends SceneTree
## Props out of the camera view park when the player is far away; the player's surroundings and moving bodies stay live.
const ROOM_CULL := preload("res://game/presentation/office_floor/public/room_cull.gd")
const CHAIR := "res://models/objects/enviroments/06/06_conference_chair.glb"
var failures := 0


func _init() -> void:
	call_deferred("_run")


func _prop(at: Vector3, moving := false) -> Node3D:
	var node: Node3D = RigidBody3D.new() if moving else Node3D.new()
	node.position = at
	root.add_child(node)
	ROOM_CULL.tag(node, {}, CHAIR)
	return node


func _parked(node: Node3D) -> bool:
	return node.process_mode == Node.PROCESS_MODE_DISABLED


func _run() -> void:
	var player := Node3D.new()
	player.add_to_group("player")
	root.add_child(player)
	var camera := Camera3D.new()
	root.add_child(camera)
	var ahead := _prop(Vector3(0, 0, -15))
	var behind := _prop(Vector3(0, 0, 15))
	var near := _prop(Vector3(0, 0, 5))
	var moving := _prop(Vector3(3, 0, 15), true)
	await process_frame
	ROOM_CULL.update_view(root.get_tree(), camera, player)
	_expect(not _parked(ahead), "A prop in view stays live")
	_expect(_parked(behind), "A far prop out of view parks")
	_expect(not _parked(near), "A prop near the player stays live even out of view")
	_expect(not _parked(moving), "A moving body is never parked by view")
	camera.look_at(Vector3(0, 0, 15), Vector3.UP)
	await process_frame
	ROOM_CULL.update_view(root.get_tree(), camera, player)
	_expect(not _parked(behind) and behind.get_meta(ROOM_CULL.REASONS, 0) == 0, "Turning to a parked prop brings it back")
	_expect(_parked(ahead), "The prop left behind parks")
	ROOM_CULL.enabled = false
	ROOM_CULL.update_view(root.get_tree(), camera, player)
	ROOM_CULL.restore_all(root.get_tree())
	_expect(not _parked(ahead) and not _parked(behind), "The setting off restores every prop")
	ROOM_CULL.enabled = true
	print("View park tests: %d failure(s)." % failures)
	quit(failures)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
