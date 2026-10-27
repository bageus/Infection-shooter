extends SceneTree
## Wall base shadow: a solid wall gets a floor strip on each side that shows only
## while real shadows are off, including for walls created after the switch.

const WALL_BASE_SHADOW := preload("res://game/presentation/office_floor/public/wall_base_shadow.gd")
const WALL := preload("res://game/presentation/office_floor/public/structural/wall_straight.tscn")

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var wall := WALL.instantiate() as Node3D
	stage.add_child(wall)
	await process_frame
	var strips := _strips(wall)
	_expect(strips.size() == 2, "A wall gets one strip per side (%d)." % strips.size())
	_expect(not _any_visible(strips), "With shadows on the strips stay hidden.")
	WALL_BASE_SHADOW.set_shadows_allowed(self, false)
	_expect(_all_visible(strips), "Turning shadows off shows the strips.")
	if strips.size() == 2:
		var near := strips[0].global_position.z
		var far := strips[1].global_position.z
		_expect(near > 0.15 and far < -0.15, "The strips sit on opposite faces of the wall (%.2f, %.2f)." % [near, far])
		_expect(absf(strips[0].global_position.y - 0.0165) < 0.001, "The strips lie on the floor.")
	var late := WALL.instantiate() as Node3D
	late.position = Vector3(4, 0, 0)
	stage.add_child(late)
	await process_frame
	_expect(_all_visible(_strips(late)), "A wall built while shadows are off starts with strips.")
	WALL_BASE_SHADOW.set_shadows_allowed(self, true)
	_expect(not _any_visible(strips) and not _any_visible(_strips(late)), "Turning shadows on hides every strip.")
	stage.queue_free()
	await process_frame
	print("Wall base shadow tests: %d failure(s)." % failures)
	quit(failures)


func _strips(wall: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	for node in wall.get_node("BaseShadow").get_children():
		found.append(node as MeshInstance3D)
	return found


func _any_visible(strips: Array[MeshInstance3D]) -> bool:
	return strips.any(func(strip: MeshInstance3D) -> bool: return strip.visible)


func _all_visible(strips: Array[MeshInstance3D]) -> bool:
	return not strips.is_empty() and strips.all(func(strip: MeshInstance3D) -> bool: return strip.visible)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
