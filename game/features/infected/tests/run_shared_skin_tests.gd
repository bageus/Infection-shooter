extends SceneTree
## Real bodies share skin resources, but never mutable wound layers. Also checks
## page boundaries, lease reuse and frozen cut snapshots after the source dies.
const SKINS := preload("res://game/features/infected/body_skin_materials.gd")
const BAKE := preload("res://game/features/infected/body_blood_bake.gd")
const SCENES := [
	preload("res://game/features/infected/public/infected_hunger.tscn"),
	preload("res://game/features/infected/public/infected_brute.tscn"),
	preload("res://game/features/infected/public/infected_colossus.tscn"),
	preload("res://game/features/infected/public/infected_horde.tscn"),
	preload("res://game/features/infected/public/infected_revenant.tscn"),
	preload("res://game/features/infected/public/infected_titan.tscn"),
	preload("res://game/features/infected/public/mutant_level2.tscn"),
]
# This fixture measures skin state, not playback lifetime on the audio thread.
class SilentAudio extends "res://game/features/infected/infected_audio.gd":
	func severed(_position: Vector3) -> void:
		pass
	func died() -> void:
		pass

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	for scene: PackedScene in SCENES:
		await _bodies(stage, scene)
	_page_boundary()
	stage.queue_free()
	# Drain renderer readbacks and deferred resource destruction before shutdown.
	for frame in 3:
		await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		await process_frame
	print("Shared skin tests: %d failures" % failures)
	quit(failures)

func _bodies(stage: Node3D, scene: PackedScene) -> void:
	var a := scene.instantiate() as CharacterBody3D
	var b := scene.instantiate() as CharacterBody3D
	stage.add_child(a)
	stage.add_child(b)
	a.set_physics_process(false)
	b.set_physics_process(false)
	for actor in [a, b]:
		actor.audio.free()
		actor.audio = SilentAudio.new()
		actor.add_child(actor.audio)
	var parts_a: Node = a._parts
	var parts_b: Node = b._parts
	_expect(parts_a != null and parts_b != null, scene.resource_path + " has body parts")
	if parts_a == null or parts_b == null:
		a.free()
		b.free()
		return
	var ea: Dictionary = parts_a._entries[0]
	var eb: Dictionary = parts_b._entries[0]
	_expect(ea.materials == eb.materials, "Same type/surfaces share materials")
	_expect(ea.lease.layer != eb.lease.layer, "Same page has independent actor layers")
	var vertex: Vector3 = ea.data.surfaces[0].vertices[0]
	parts_a.add_rest_wound(vertex, 0.25)
	_expect(not eb.has("masks"), "Wounding A does not create CPU masks on B")
	_expect(float(eb.instance.get_instance_shader_parameter(&"blood_layer")) == -1.0, "B keeps its clean instance selector")
	_expect(ea.materials == eb.materials, "Wounding keeps the same shared materials")
	a.status_fx.poisoned(1.0)
	a.status_fx._process(0.8)
	_expect(float(ea.instance.get_instance_shader_parameter(&"blood_layer")) == ea.lease.layer, "Poison fade does not overwrite the wound selector")
	_expect(eb.instance.material_overlay == null, "Poison remains local to A")
	a.status_fx.clear()
	var a_bytes: PackedByteArray = ea.masks[0].image.get_data()
	_expect(a_bytes.has(255), "A has a visible baked wound")
	parts_b.add_rest_wound(vertex + Vector3(0, 10, 0), 0.01)
	_expect(not eb.masks[0].image.get_data().has(255), "B's off-body wound stays clean")
	_expect(ea.masks[0].image.get_data() == a_bytes, "Painting B does not change A")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		_expect(ea.lease.page.textures[0].get_layer_data(ea.lease.layer).get_data() == a_bytes, "A GPU layer matches baked pixels")
		_expect(ea.lease.page.textures[0].get_layer_data(eb.lease.layer).get_data() == eb.masks[0].image.get_data(), "B GPU layer is independent")
	var piece: RigidBody3D = parts_a.sever(parts_a.severable_parts()[0], Vector3.RIGHT)
	_expect(piece != null, "A cut creates a piece")
	if piece != null:
		var meshes := piece.find_children("*", "MeshInstance3D", false, false)
		var visual := meshes[0] as MeshInstance3D
		var lease: RefCounted = visual.get_meta("body_skin_lease")
		_expect(lease.layer != ea.lease.layer, "Piece owns a frozen layer")
		_expect(visual.mesh.surface_get_material(0) == ea.materials[0], "Piece shares the skin material")
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			var snapshot: PackedByteArray = lease.page.textures[0].get_layer_data(lease.layer).get_data()
			parts_a.add_rest_wound(vertex, 2.0)
			await RenderingServer.frame_post_draw
			_expect(lease.page.textures[0].get_layer_data(lease.layer).get_data() == snapshot, "Later body wounds do not alter the piece")
		a.free()
		_expect(is_instance_valid(lease.page.materials[0]), "Piece outlives its source")
		piece.free()
	else:
		a.free()
	b.free()
	await process_frame

func _page_boundary() -> void:
	var pool := SKINS.new([StandardMaterial3D.new(), StandardMaterial3D.new()])
	var leases: Array = []
	for i in SKINS.PAGE_LAYERS + 1:
		leases.append(pool.acquire())
	_expect(leases[0].page == leases[SKINS.PAGE_LAYERS - 1].page, "128 bodies share a page")
	_expect(leases[0].page != leases[SKINS.PAGE_LAYERS].page, "Overflow receives a separate page")
	var page: RefCounted = leases[0].page
	_expect(page.materials[0].get_shader_parameter("blood_masks") != null, "Clean material has a valid array sampler")
	var red := BAKE.create_mask()
	red.fill(Color(1, 0, 0))
	leases[0].upload([red, BAKE.create_mask()])
	_expect(page.textures.size() == 2 and page.textures[0] != page.textures[1], "Surfaces use separate mask arrays with the same actor selector")
	var layer: int = leases[0].layer
	leases[0] = null
	var reused: RefCounted = pool.acquire()
	_expect(reused.page == page and reused.layer == layer, "Freed layers are reused")
	var mesh := MeshInstance3D.new()
	reused.bind(mesh)
	_expect(float(mesh.get_instance_shader_parameter(&"blood_layer")) == -1.0, "Reused clean layer never shows old blood")
	mesh.free()
	leases.clear()

func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
