extends SceneTree

# Renders the world badges over the real mission at 1280x720 for visual review:
# the pick-up key cap over a weapon (rest and mid-press) and the locked-door
# icon over an emergency door. Output: /tmp/hud_previews/*.png

const MAIN := preload("res://game/bootstrap/app/main.tscn")
const WEAPON := preload("res://game/bootstrap/app/weapon_pickup.gd")
const EMERGENCY_DOOR := preload("res://game/presentation/office_floor/public/structural/wall_emergency_door.tscn")
const OUT := "/tmp/hud_previews/"


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(OUT)
	var game := MAIN.instantiate()
	root.add_child(game)
	current_scene = game
	for i in 20:
		await process_frame
	var player := game.get_node("Gameplay/Player") as Node3D
	var pickup := WEAPON.new()
	pickup.weapon_index = 2
	(player.get_parent() as Node3D).add_child(pickup)
	pickup.global_position = player.global_position + Vector3(1.4, 0.0, -0.6)
	for i in 10:
		await process_frame
	var badge := pickup.get_node("WorldBadge")
	await _shot("weapon_key_rest.png", badge, WEAPON.BADGE.PRESS_PERIOD * 0.7)
	await _shot("weapon_key_pressed.png", badge, WEAPON.BADGE.PRESS_TIME * 0.5)
	pickup.queue_free()
	var door := _locked_door(game)
	if door == null:
		# The mission layout lives in the planner save; stage one door for review.
		var wall := EMERGENCY_DOOR.instantiate() as Node3D
		(player.get_parent() as Node3D).add_child(wall)
		wall.global_position = player.global_position + Vector3(0, -1.0, -3.0)
		door = wall.get_node("DoorController") as Node3D
		door.call("configure_player", player)
	if door != null:
		var away := -signf(float(door.get("one_way_allowed_side")))
		player.global_position = door.global_position + door.global_transform.basis.z.normalized() * away * 2.2
		player.global_position.y = 1.0
		for i in 20:
			await process_frame
		await _shot("locked_door.png")
	game.free()
	await process_frame
	quit()


func _locked_door(game: Node) -> Node3D:
	for door in game.get_tree().get_nodes_in_group("interactive_doors"):
		if bool(door.get("requires_emergency_key")):
			return door as Node3D
	return null


func _shot(file: String, badge: Node = null, at := 0.0) -> void:
	if badge != null:
		# Hold the key cap at one moment of its press cycle for the shot.
		badge.set_process(false)
		badge.set("_time", 0.0)
		badge.call("_process", at)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + file)
