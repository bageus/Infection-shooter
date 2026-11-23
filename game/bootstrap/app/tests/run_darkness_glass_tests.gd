extends SceneTree
## A broken glass pane or partition beside a dark room is a way in, the same as an open door; an intact one is not.
const ZONE := preload("res://game/presentation/office_floor/public/props/darkness_zone.tscn")
var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var player := Node3D.new()
	player.add_to_group("player")
	player.position = Vector3(50.0, 0.0, 50.0)
	root.add_child(player)
	var zone := ZONE.instantiate() as Node3D
	zone.set("permanent", false)
	zone.set("room_id", 7)
	zone.position = Vector3(0.0, 2.75, 0.0)
	root.add_child(zone)
	var body := StaticBody3D.new()
	body.add_to_group("infected_breakable_glass")
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	body.add_child(shape)
	root.add_child(body)
	body.global_position = zone.global_position
	await create_timer(0.6).timeout
	_expect(zone.overlay.visible, "Intact glass keeps the room dark")
	shape.set_deferred("disabled", true)
	await create_timer(0.6).timeout
	_expect(not zone.overlay.visible, "Broken glass opens the room")
	# A wooden partition opens its room only once it is broken.
	var wood_zone := ZONE.instantiate() as Node3D
	wood_zone.set("permanent", false)
	wood_zone.set("room_id", 8)
	wood_zone.position = Vector3(30.0, 2.75, 0.0)
	root.add_child(wood_zone)
	var partition := StaticBody3D.new()
	partition.add_to_group("darkness_opening")
	var wood_shape := CollisionShape3D.new()
	wood_shape.shape = BoxShape3D.new()
	partition.add_child(wood_shape)
	root.add_child(partition)
	partition.global_position = wood_zone.global_position
	await create_timer(0.6).timeout
	_expect(wood_zone.overlay.visible, "A standing partition keeps the room dark")
	wood_shape.set_deferred("disabled", true)
	await create_timer(0.6).timeout
	_expect(not wood_zone.overlay.visible, "A broken partition opens the room")
	print("Darkness glass tests: %d failure(s)." % failures)
	quit(1 if failures > 0 else 0)


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", message)
