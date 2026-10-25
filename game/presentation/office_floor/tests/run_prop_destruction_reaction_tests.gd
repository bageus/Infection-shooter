extends SceneTree
## Bullets drop authored parts locally; explosions scatter; small props leave only baked marks.
const PROP := preload("res://game/presentation/office_floor/public/props/environment_prop.tscn")
const PAPER := preload("res://game/presentation/office_floor/public/props/paper_prop.tscn")
const GLASS := preload("res://game/presentation/office_floor/public/structural/glass_wall_full.tscn")
const TABLE := preload("res://game/presentation/office_floor/public/props/07_table.tscn")
const FLOOR := preload("res://game/presentation/office_floor/public/base_floor_renderer.gd")
const DAMAGE := preload("res://game/presentation/office_floor/environment_damage.gd")
const BREAKUP := preload("res://game/presentation/office_floor/environment_prop_breakup.gd")
const GEOMETRY := preload("res://game/presentation/office_floor/environment_prop_geometry.gd")
const PUSH := preload("res://game/presentation/office_floor/bullet_push.gd")
var failures := 0
var stage: Node3D
var effects: Node3D
var floor_view: Node3D

class Host extends RigidBody3D:
	var effects_root: Node3D
	var model_path := "test_table.glb"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	effects = Node3D.new()
	stage.add_child(effects)
	floor_view = FLOOR.new()
	floor_view.floor_size = Vector2(32, 32)
	stage.add_child(floor_view)
	await _small_items()
	await _impulses()
	await _moved_stage()
	await _authored_stages()
	await _legacy_table()
	await _glass_reaction()
	stage.free()
	await process_frame
	print("Prop destruction reaction tests: %d failure(s)." % failures)
	quit(failures)

func _small_items() -> void:
	var models := ["09/09_fruit_apple.glb", "09/09_fruit_plate_2.glb", "09/09_glass.glb", "09/09_mug.glb",
		"09/09_pen_1.glb", "09/09_pencil.glb", "05/05_computer_mouse.glb", "05/05_keyboard.glb",
		"09/09_book_small.glb", "09/09_books.glb", "09/09_file_binder.glb", "09/09_office_files_a.glb", "09/09_paper_stray.glb"]
	for model: String in models:
		for weapon: String in ["SHOTGUN", "AK", "GRENADE"]:
			floor_view.clear_glass_debris()
			var prop := (PAPER if "paper_stray" in model else PROP).instantiate() as RigidBody3D
			prop.model_path = "res://models/objects/enviroments/" + model
			stage.add_child(prop)
			prop.freeze = true
			prop.configure_world(effects, null)
			prop.configure_glass_debris(floor_view)
			prop.take_projectile_hit(5, Vector3(0, .1, 0), Vector3.UP, Vector3.FORWARD, weapon)
			await process_frame
			var label := model + " " + weapon
			_check(not is_instance_valid(prop) or (prop.collision_layer == 0 and not prop.get_node("Visual").visible), label + " disappears on damaging hit")
			_check(effects.get_children().all(func(node: Node) -> bool: return not node is RigidBody3D and not node is VisualInstance3D), label + " leaves no physical/render fragments")
			var bake: RefCounted = floor_view.get("_glass")
			_check(not bake.queue.is_empty() or not bake.tiles.is_empty(), label + " leaves actual floor marks")
			if is_instance_valid(prop): prop.queue_free()
			for child in effects.get_children(): child.queue_free()
			await process_frame

func _impulses() -> void:
	var host := Host.new()
	host.effects_root = effects
	stage.add_child(host)
	host.freeze = true
	var mesh := _mesh(host, "Panel", Vector3(1.6, 1.2, .04), Vector3(0, 5, 0))
	mesh.rotation.y = .7
	var bullet := DAMAGE.spawn_piece(host, mesh, null, 0, 0, Vector3.FORWARD, mesh.global_position)
	var blast := DAMAGE.spawn_piece(host, mesh, null, 0, 1, Vector3.FORWARD, mesh.global_position, true)
	bullet.collision_mask = 0
	blast.collision_mask = 0
	await physics_frame
	await physics_frame
	_check(Vector2(bullet.linear_velocity.x, bullet.linear_velocity.z).length() < .25, "Bullet breakup has no explosive translation")
	_check(bullet.angular_velocity.length() < .5, "Bullet breakup has no artificial tumble/topple kick")
	_check(Vector2(blast.linear_velocity.x, blast.linear_velocity.z).length() > .5, "Grenade keeps strong fragment scatter")
	var box: BoxShape3D = bullet.get_child(0).shape
	_check(box.size.x < 1.65 and box.size.z < .06, "Rotated panel collision fits the authored panel, not its world AABB")
	bullet.queue_free()
	blast.queue_free()
	host.queue_free()
	await process_frame
	var body := RigidBody3D.new()
	stage.add_child(body)
	body.gravity_scale = 0
	for shot in 8: PUSH.apply(body, .3, "SHOTGUN", Vector3.FORWARD, body.global_position)
	await physics_frame
	await physics_frame
	_check(body.linear_velocity.length() <= .36, "A pellet volley cannot accumulate explosive prop velocity")
	_check(absf(body.linear_velocity.y) < .001, "Bullets do not add an upward hop")
	for shot in 20:
		PUSH.apply(body, .3, "AK", Vector3.FORWARD, body.global_position)
		await physics_frame
	_check(body.linear_velocity.length() <= .36, "Automatic fire across successive frames cannot accumulate launch speed")
	body.queue_free()
	await process_frame

func _moved_stage() -> void:
	var host := Host.new()
	host.effects_root = effects
	stage.add_child(host)
	host.freeze = true
	var geometry := GEOMETRY.new()
	geometry.visual = Node3D.new()
	host.add_child(geometry.visual)
	for label: String in ["LargeParts", "SmallFragments"]:
		var group := Node3D.new()
		group.name = label
		geometry.visual.add_child(group)
		geometry.stages.append(group)
	_mesh(geometry.stages[0], "Top.001", Vector3(1, .1, 1), Vector3(0, 1, 0))
	_mesh(geometry.stages[1], "Top_fragment_1", Vector3(.5, .1, 1), Vector3(-.25, 1, 0))
	_mesh(geometry.stages[1], "Top_fragment_2", Vector3(.5, .1, 1), Vector3(.25, 1, 0))
	BREAKUP.spawn_stage(host, geometry, 0, "", Vector3.ZERO, Vector3.FORWARD)
	var source: RigidBody3D
	for child in effects.get_children():
		if child is RigidBody3D: source = child
	source.global_transform = Transform3D(Basis(Vector3.UP, .6), Vector3(8, 2, 3))
	var current := source.global_transform
	BREAKUP.hit_fragment(host, geometry, source, current.origin, Vector3.FORWARD)
	_check(source.is_queued_for_deletion(), "Blender numeric suffix does not block the finer authored stage")
	var replacements := 0
	for child in effects.get_children():
		if child is RigidBody3D and child != source:
			replacements += 1
			var side := -.25 if str(child.get("piece_name")).ends_with("1") else .25
			_check(child.global_position.is_equal_approx(current * Vector3(side, 0, 0)), "Fine pieces retain the exact moved/rotated authored arrangement")
			_check(child.global_basis.is_equal_approx(current.basis), "Fine piece collision axes follow the rotated source")
	_check(replacements == 2, "Both authored fine pieces are spawned")
	for child in effects.get_children(): child.queue_free()
	host.queue_free()
	await process_frame

func _authored_stages() -> void:
	for model: String in ["07/07_table_longest.glb", "08/08_office_desk_2.glb", "05/05_monitor_destructible.glb"]:
		var prop := PROP.instantiate() as RigidBody3D
		prop.set("model_path", "res://models/objects/enviroments/" + model)
		stage.add_child(prop)
		prop.freeze = true
		prop.call("configure_world", effects, null)
		var geometry: RefCounted = prop.get("_geometry")
		_check(geometry.stages.size() >= 2, model + " discovers authored coarse and fine stages")
		BREAKUP.spawn_stage(prop, geometry, 0, "", Vector3.ZERO, Vector3.FORWARD)
		var coarse := effects.get_children().filter(func(node: Node) -> bool: return node is RigidBody3D)
		var splits := 0
		for piece: RigidBody3D in coarse:
			piece.global_position += Vector3(8, 2, 3)
			var before := effects.get_child_count()
			var at := piece.global_position
			var radius := .2
			for visual in piece.get_children():
				if visual is MeshInstance3D: radius += (visual.global_transform * visual.get_aabb()).size.length() * .5
			BREAKUP.hit_fragment(prop, geometry, piece, at, Vector3.FORWARD)
			if not piece.is_queued_for_deletion(): continue
			splits += 1
			for child in effects.get_children().slice(before):
				if child is RigidBody3D:
					_check(child.global_position.distance_to(at) < radius, model + " splits at its current location")
		_check(splits > 0, model + " reaches its authored fine pieces")
		print("AUTHORED_FINE_STAGE ", model, " coarse=", coarse.size(), " split=", splits)
		for child in effects.get_children(): child.queue_free()
		prop.queue_free()
		await process_frame

func _legacy_table() -> void:
	for weapon: String in ["AK", "GRENADE"]:
		var table := TABLE.instantiate() as Node3D
		stage.add_child(table)
		table.call("take_projectile_hit", 400.0, Vector3(0, .8, 0), Vector3.UP, Vector3.FORWARD, "AK")
		table.call("hit_piece", "Top", Vector3(0, .8, 0), Vector3.FORWARD, 400.0, weapon)
		await process_frame
		await physics_frame
		await physics_frame
		var speed := 0.0
		var count := 0
		for child in stage.get_children():
			if child is RigidBody3D and child.get_script() == preload("res://game/presentation/office_floor/table_piece.gd"):
				count += 1
				speed = maxf(speed, Vector2(child.linear_velocity.x, child.linear_velocity.z).length())
		_check(count > 4, "Legacy table drops fine top pieces and remaining legs")
		_check(speed < .25 if weapon == "AK" else speed > .5, "Legacy table separates bullet collapse from grenade scatter: " + weapon)
		for child in stage.get_children():
			if child is RigidBody3D or child == table: child.queue_free()
		await process_frame

func _glass_reaction() -> void:
	for weapon: String in ["AK", "GRENADE"]:
		var wall := GLASS.instantiate() as Node3D
		stage.add_child(wall)
		var pane := wall.get_node("GlassBody") as StaticBody3D
		pane.call("configure_world", effects, null)
		pane.set("_cracks_needed", 0)
		var group := DAMAGE.find_named(wall.get_node("Visual"), "Glass_Shards")
		var shards := DAMAGE.reveal_meshes(group)
		var point := shards[0].global_transform * shards[0].get_aabb().get_center()
		pane.call("take_projectile_hit", 5.0, point, Vector3.BACK, Vector3.FORWARD, weapon)
		var pieces := effects.get_children().filter(func(node: Node) -> bool: return node is RigidBody3D)
		_check(not pieces.is_empty(), "Glass near the hit falls immediately")
		var scattered := pieces.any(func(node: Node) -> bool: return bool(node.get("blast_motion")))
		_check(scattered == (weapon == "GRENADE"), "Glass also reserves explosive motion for grenades: " + weapon)
		wall.queue_free()
		for child in effects.get_children(): child.queue_free()
		await process_frame

func _mesh(parent: Node3D, label: String, size: Vector3, at: Vector3) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = label
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	parent.add_child(mesh)
	mesh.position = at
	return mesh

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
