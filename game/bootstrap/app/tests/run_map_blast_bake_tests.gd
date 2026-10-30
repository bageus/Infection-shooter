extends SceneTree
## Grenades fired at real map props (cardboard boxes, a tall locker, a crate): after the debris
## expires, no big piece that is still standing may have been baked into the floor as a fake frame.
const MAP := preload("res://game/presentation/office_floor/public/base_office_layout.tscn")
const EXPLOSION := preload("res://game/features/combat/public/grenade_explosion.gd")
const WORLD_BINDINGS := preload("res://game/bootstrap/app/world_bindings.gd")
const QUALITY := preload("res://game/core/vfx/public/destruction_quality.gd")
const TARGETS := ["cardboard_box", "locker", "crate"]
const PIECE_GROUP := "fallen_environment_fragment"
const SETTLE_FRAMES := 300

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _props(node: Node, out: Array) -> void:
	if node is RigidBody3D and node.has_method("take_projectile_hit") and "model_path" in node:
		out.append(node)
	for child in node.get_children():
		_props(child, out)


func _run() -> void:
	QUALITY.set_level(QUALITY.LOW)
	var stage := Node3D.new()
	root.add_child(stage)
	var effects := Node3D.new()
	stage.add_child(effects)
	var map := MAP.instantiate()
	stage.add_child(map)
	# The mission's own wiring gives every prop its effects container, as in the live game.
	var bindings := WORLD_BINDINGS.new(effects, null, null, Callable())
	bindings.bind_scene(map)
	for i in 10:
		await physics_frame
	var props: Array = []
	_props(map, props)
	var chosen: Array = []
	for token: String in TARGETS:
		for prop: Node3D in props:
			if token in str(prop.get("model_path")).get_file():
				chosen.append(prop)
				break
	_check(chosen.size() == TARGETS.size(), "The map has a cardboard box, a locker and a crate (%d found)" % chosen.size())
	for prop: Node3D in chosen:
		var name := str(prop.get("model_path")).get_file()
		var holder := Node3D.new()
		stage.add_child(holder)
		EXPLOSION.explode(holder, prop.global_position + Vector3(0.0, 0.5, 0.8), Vector3.UP, null, stage, null)
		for i in SETTLE_FRAMES:
			await physics_frame
		var standing := 0
		var big := 0
		for piece in get_nodes_in_group(PIECE_GROUP):
			if not is_instance_valid(piece) or piece.is_queued_for_deletion():
				continue
			if piece.call("_is_standing_big"):
				standing += 1
			big += 1
			piece.call("expire")
		var baked := 0
		for runtime in root.find_children("FragmentRuntime", "Node", true, false):
			baked += int(runtime.get("_baked").call("count"))
		print("%s: pieces=%d standing_big=%d baked_after_expire=%d" % [name, big, standing, baked])
		_check(big > 0, name + " broke into pieces")
		# A standing piece may stay a body or fade out when the budget is full; only a frozen piece that is not fading would be a floor frame.
		for piece in get_nodes_in_group(PIECE_GROUP):
			if is_instance_valid(piece) and not piece.is_queued_for_deletion() and piece.call("_is_standing_big"):
				_check(not (piece.freeze and not piece.has_meta("debris_fading")), name + ": a standing big piece is frozen into the floor as a fake frame")
	stage.queue_free()
	await process_frame
	print("Map blast bake tests: %d failure(s)." % failures)
	quit(failures)


func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + label)
	print(("PASS: " if ok else "FAIL: ") + label)
