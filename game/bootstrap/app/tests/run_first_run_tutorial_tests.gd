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
	_check(TARGET.kind_of(table) == "object", "Any other object can be a target too")
	TARGET.configure(bottle, true)
	TARGET.configure(crate, true)
	TARGET.configure(table, true)
	_check(TARGET.is_target(table), "Any object takes the flag")
	_check(bottle.get_node_or_null(TARGET.MARKER_NAME) != null and bottle.is_in_group(TARGET.GROUP), "A flagged bottle gets its marker")
	_check(TARGET.standing(self, "bottle").size() == 1, "A flagged bottle stands until broken")

	var director := DIRECTOR.new()
	root.add_child(director)
	director.call("configure", actor, hud, tree_ui, PROGRESS.new(SAVE))
	var overlay: Node = director.get("overlay")
	director.set("_since_start", 3.0)
	await process_frame
	await process_frame
	_check(director.get("current") == "", "Nothing starts by itself any more")
	director.call("play", "move")
	await process_frame
	_check(director.get("current") == "move" and bool(overlay.get("active")), "The first lesson is movement")
	_check(overlay.get("step").has("keys") and overlay.get("keys").visible, "Movement shows animated key caps")
	_check(paused, "The first screen pauses the game")
	await _advance(overlay)
	_check(not paused and not str(overlay.get("step").get("objective")).is_empty(), "Then the task moves to the objective and the game runs")
	_check((hud.get_node("Objective").get_child(0) as Label).text == str(overlay.get("step").get("objective")), "The HUD banner shows the task")
	_check(PROGRESS.new(SAVE).is_done("move"), "The lesson is remembered as soon as it starts")
	await _walk(actor, 0.0, 5.0)
	_check(director.get("current") == "", "Without a door target five steps finish the movement lesson")
	director.call("play", "shoot")
	_check(director.get("current") == "shoot", "A quest starts the shooting lesson")
	await _advance(overlay)
	_check(bottle.get_meta(&"planning_tutorial_revealed", false) == true and bottle.get_node(TARGET.MARKER_NAME).visible, "The shooting stage reveals the bottle marker")
	_check(crate.get_meta(&"planning_tutorial_revealed", false) != true, "The crate marker stays hidden until its own stage")
	var gone: Variant = bottle.get("_damage")
	gone.glass_broken = true
	await process_frame
	await process_frame
	_check(director.get("current") == "", "Breaking the bottle completes the lesson")
	_check(not bottle.get_node(TARGET.MARKER_NAME).visible, "A broken bottle loses its marker")
	_check(TARGET.standing(self, "bottle").is_empty(), "No bottle target stands any more")
	director.call("play", "look")
	_check(director.get("current") == "look", "Then the camera lesson")
	await _advance(overlay)
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
	await _armor_lesson(director, overlay, hud, actor)
	TARGET.configure(crate, false)
	_check(not TARGET.is_target(crate) and crate.get_node_or_null(TARGET.MARKER_NAME) == null, "The flag can be removed")
	_baked_scene()
	var saved := _prop("res://models/objects/enviroments/09/09_fire_extinguisher.glb", Vector3(20, 0, 0))
	PROPERTIES.restore(saved, {"tutorial_target": true})
	_check(TARGET.kind_of(saved) == "extinguisher" and TARGET.is_target(saved), "A saved map record restores the target flag")
	if failures == 0:
		print("First-run tutorial tests passed.")
	else:
		push_error("First-run tutorial tests failed: %d failure(s)." % failures)
	director.free()
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


func _armor_lesson(director: Node, overlay: Node, hud: Node, actor: Node) -> void:
	actor.set("armor", 60.0)
	await process_frame
	_check(director.get("current") == "", "Getting armor starts nothing by itself")
	director.call("play", "armor")
	await process_frame
	_check(director.get("current") == "armor" and bool(overlay.get("picture").visible), "Getting armor for the first time shows the armor bar")
	_check(is_equal_approx(float(overlay.get("picture").get("armor")), 0.6), "The picture shows the armor held")
	_check(not hud.call("tutorial_rect", "armor").size.is_zero_approx(), "The HUD armor bar is spotlighted")


func _baked_scene() -> void:
	# A baked (packed) map keeps the flag and its marker; an old bake with only the meta is re-flagged.
	var holder := Node3D.new()
	var baked := PROP.instantiate() as Node3D
	baked.set("model_path", "res://models/objects/enviroments/09/09_plastic_water_bottle_blue_500ml.glb")
	holder.add_child(baked)
	baked.owner = holder
	TARGET.configure(baked, true)
	var packed := PackedScene.new()
	packed.pack(holder)
	var loaded: Node = packed.instantiate()
	root.add_child(loaded)
	var again := loaded.get_child(0)
	_check(again.is_in_group(TARGET.GROUP) and again.get_node_or_null(TARGET.MARKER_NAME) != null, "A baked scene keeps the target flag and marker")
	again.remove_from_group(TARGET.GROUP)
	again.get_node(TARGET.MARKER_NAME).free()
	TARGET.adopt_baked(self)
	_check(again.is_in_group(TARGET.GROUP) and again.get_node_or_null(TARGET.MARKER_NAME) != null, "A map baked without the group is re-flagged from its meta")
	loaded.free()
	holder.free()
	packed = null


func _advance(overlay: Node) -> void:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 400:
		await process_frame
	var press := InputEventKey.new()
	press.keycode = KEY_SPACE
	press.pressed = true
	overlay.call("_input", press)
	await process_frame


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
	else:
		print("ok: ", message)
