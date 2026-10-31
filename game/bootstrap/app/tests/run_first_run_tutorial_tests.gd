extends SceneTree
const PLAYER := preload("res://game/features/player/public/player.tscn")
const HUD_SCENE := preload("res://game/presentation/prototype_hud/public/prototype_hud.tscn")
const TREE_UI := preload("res://game/bootstrap/app/mutation_tree_ui.gd")
const DIRECTOR := preload("res://game/bootstrap/app/tutorial/tutorial_director.gd")
const PROGRESS := preload("res://game/bootstrap/app/tutorial/tutorial_progress.gd")
const TARGET := preload("res://game/presentation/office_floor/public/tutorial_target.gd")
const PROP := preload("res://game/presentation/office_floor/public/props/environment_prop.tscn")
const PROPERTIES := preload("res://game/bootstrap/app/planning_layout_properties.gd")
const LOCALIZATION := preload("res://game/core/localization/public/ui_translations.gd")
const SAVE := "user://first_run_tutorial_test.cfg"
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _prop(model: String, at: Vector3) -> Node3D:
	var node := PROP.instantiate() as Node3D
	node.set("model_path", model)
	root.add_child(node)
	node.global_position = at
	return node


func _run() -> void:
	root.size = Vector2i(1280, 720)
	LOCALIZATION.apply_language("en")
	DirAccess.remove_absolute(SAVE)
	var actor := PLAYER.instantiate()
	actor.name = "Player"
	root.add_child(actor)
	actor.set_physics_process(false)
	var runtime: Node = actor.get("infection_runtime")
	runtime.set_physics_process(false)
	var hud := HUD_SCENE.instantiate()
	hud.set("player_path", NodePath("../Player"))
	root.add_child(hud)
	var tree_ui := TREE_UI.new()
	root.add_child(tree_ui)
	tree_ui.call("configure", runtime)
	var bottle := _prop("res://models/objects/enviroments/09/09_glass_water_bottle_clear_250ml.glb", Vector3(3, 0, 0))
	var crate := _prop("res://models/objects/enviroments/02/02_crate_wood_large.glb", Vector3(6, 0, 0))
	var table := _prop("res://models/objects/enviroments/09/09_mug.glb", Vector3(9, 0, 0))
	_check(TARGET.kind_of(bottle) == "bottle" and TARGET.kind_of(crate) == "crate", "Bottles and crates can be targets")
	_check(TARGET.kind_of(table) == "", "A mug cannot be a target")
	TARGET.configure(bottle, true)
	TARGET.configure(crate, true)
	TARGET.configure(table, true)
	_check(not TARGET.is_target(table), "An unsupported object ignores the flag")
	_check(bottle.get_node_or_null(TARGET.MARKER_NAME) != null and bottle.is_in_group(TARGET.GROUP), "A flagged bottle gets its marker")
	_check(TARGET.standing(self, "bottle").size() == 1, "A flagged bottle stands until broken")

	var director := DIRECTOR.new()
	root.add_child(director)
	director.call("configure", actor, hud, tree_ui, PROGRESS.new(SAVE))
	var overlay: Node = director.get("overlay")
	await process_frame
	await process_frame
	_check(director.get("current") == "move" and bool(overlay.get("active")), "The first lesson is movement")
	_check(overlay.get("step").has("keys") and overlay.get("keys").visible, "Movement shows animated key caps")
	_check(not paused, "Movement does not pause the game")
	_check(PROGRESS.new(SAVE).is_done("move"), "The lesson is remembered as soon as it starts")
	await _walk(actor, 0.0, 5.0)
	_check(director.get("current") == "", "Without a door target five steps finish the movement lesson")
	await _walk(actor, 5.0, 8.0)
	_check(director.get("current") == "shoot", "A few steps later the shooting lesson starts")
	var gone: Variant = bottle.get("_damage")
	gone.glass_broken = true
	await process_frame
	await process_frame
	_check(director.get("current") == "", "Breaking the bottle completes the lesson")
	_check(not bottle.get_node(TARGET.MARKER_NAME).visible, "A broken bottle loses its marker")
	_check(TARGET.standing(self, "bottle").is_empty(), "No bottle target stands any more")
	await _walk(actor, 8.0, 14.0)
	_check(director.get("current") == "look", "Then the camera lesson")
	Input.action_press("camera_left")
	await process_frame
	_check(float(director.get("_look_seconds")) > 0.0, "Holding the camera key is counted")
	director.set("_look_seconds", 1.0) # headless frames are too short to add up in a test
	await process_frame
	await process_frame
	Input.action_release("camera_left")
	await process_frame
	_check(director.get("current") == "", "Turning the camera ends it")
	var seen := PROGRESS.new(SAVE)
	_check(seen.is_done("look") and seen.is_done("shoot"), "Every lesson is stored once")
	director.call("request", "move")
	director.call("request", "shoot")
	await process_frame
	_check(director.get("current") == "", "A seen lesson never starts again")
	TARGET.configure(crate, false)
	_check(not TARGET.is_target(crate) and crate.get_node_or_null(TARGET.MARKER_NAME) == null, "The flag can be removed")
	var saved := _prop("res://models/objects/enviroments/09/09_fire_extinguisher.glb", Vector3(20, 0, 0))
	PROPERTIES.restore(saved, {"tutorial_target": true})
	_check(TARGET.kind_of(saved) == "extinguisher" and TARGET.is_target(saved), "A saved map record restores the target flag")
	if failures == 0:
		print("First-run tutorial tests passed.")
	else:
		push_error("First-run tutorial tests failed: %d failure(s)." % failures)
	hud.queue_free()
	await process_frame
	DirAccess.remove_absolute(SAVE)
	quit(failures)


# Walks the player along x in short hops, the way real movement reaches the step counter.
func _walk(actor: Node3D, from: float, to: float) -> void:
	var x := from
	while x < to:
		x = minf(x + 1.0, to)
		actor.global_position = Vector3(x, 0, 0)
		await process_frame
	await process_frame
	await process_frame


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
	else:
		print("ok: ", message)
