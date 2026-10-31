extends SceneTree
## Ambient prop sounds: only intact tagged props near the player sound, rarely, and the
## reception line plays once.

const AMBIENT := preload("res://game/presentation/office_floor/public/ambient_prop_sounds.gd")

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var player := Node3D.new()
	stage.add_child(player)
	var ambient := AMBIENT.new()
	ambient.player = player
	stage.add_child(ambient)
	var phone := Node3D.new()
	stage.add_child(phone)
	AMBIENT.tag(phone, "res://models/objects/enviroments/05/05_desk_phone.glb")
	var other := Node3D.new()
	stage.add_child(other)
	AMBIENT.tag(other, "res://models/objects/enviroments/05/05_chair.glb")
	_expect(phone.is_in_group(AMBIENT.GROUP) and not other.is_in_group(AMBIENT.GROUP), "Only listed models become sound sources.")
	phone.position = Vector3(50, 0, 0)
	_expect(_plays(ambient, &"phone_ring") == 0, "A distant phone stays silent.")
	phone.position = Vector3(2, 0, 0)
	var rang := 0
	for attempt in 40:
		ambient._next_allowed.clear()
		rang += _plays(ambient, &"phone_ring")
		await process_frame
	_expect(rang > 0 and rang < 40, "A near phone rings now and then (%d of 40)." % rang)
	# A ring is a burst of beeps one period apart, never a single long tone.
	ambient._ring(phone.global_position, 2)
	_expect(_voices(&"phone_ring") == 1, "A ring starts with its first beep.")
	await create_timer(1.3).timeout
	_expect(_voices(&"phone_ring") == 0, "The first beep ends before the next one.")
	await create_timer(0.6).timeout
	_expect(_voices(&"phone_ring") == 1, "The second beep follows after a pause.")
	var reception := Node3D.new()
	stage.add_child(reception)
	AMBIENT.tag(reception, "res://models/objects/enviroments/07/07_reception_counter_two_heights.glb")
	reception.position = Vector3(1, 0, 0)
	var spoke := 0
	for attempt in 3:
		spoke += _plays(ambient, &"vectrion_is_the_future")
		await process_frame
	_expect(spoke == 1, "The reception line plays once per level (%d)." % spoke)
	print("Ambient prop sound tests: %d failures" % failures)
	quit(failures)


# Runs one scan and returns how many voices of `event` it started.
func _plays(ambient: Node, event: StringName) -> int:
	var group := StringName("sfx_" + String(event))
	var before := root.get_tree().get_nodes_in_group(group).size()
	ambient.set("_wait", 0.0)
	ambient._process(0.0)
	return root.get_tree().get_nodes_in_group(group).size() - before


func _voices(event: StringName) -> int:
	return root.get_tree().get_nodes_in_group(StringName("sfx_" + String(event))).size()


func _expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
