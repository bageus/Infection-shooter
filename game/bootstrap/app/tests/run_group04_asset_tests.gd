extends SceneTree
## Check real imported stages, shared GPU resources and crate/cardboard breakage.
const PROP := preload("res://game/presentation/office_floor/public/props/environment_prop.tscn")
const CATALOG := preload("res://game/bootstrap/app/planning_catalog.gd")
const GROUP := "res://models/objects/enviroments/04/"
const MAPS := GROUP + "textures/unified/"
const COUNTS := {
	"04_cardboard_archive_box.glb": [37, 0],
	"04_cardboard_box_closed.glb": [29, 0],
	"04_cardboard_box_open.glb": [44, 0],
	"04_cardboard_boxes.glb": [11, 0],
	"04_cardboard_boxes_1.glb": [23, 0],
	"04_crate_large_broken.glb": [25, 117],
	"04_crate_small_broken.glb": [25, 109],
}
var failures := 0
var shared: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var catalog := CATALOG.new()
	catalog.call("_build_environment_catalogs")
	var entries: Array = catalog.group_catalogs["04"]
	_check(entries.size() == 7, "Seven group-04 palette entries remain")
	for entry: Dictionary in entries:
		_check(ResourceLoader.exists(str(entry.path)), "Palette path loads")
	for filename: String in COUNTS:
		var packed := load(GROUP + filename) as PackedScene
		_check(packed != null, "Model imports: " + filename)
		if packed == null:
			continue
		var model := packed.instantiate() as Node3D
		_check_stages(model, filename)
		_check_materials(model, filename)
		model.free()
	_check(shared.size() == 2, "All surfaces allocate only two shared materials")
	_check_budget()
	await _check_breakage("04_cardboard_box_closed.glb", false)
	await _check_breakage("04_crate_small_broken.glb", true)
	print("Group 04 asset tests: %d failures" % failures)
	quit(0 if failures == 0 else 1)


func _check_stages(model: Node3D, filename: String) -> void:
	_check(int(model.get_meta(&"staged_glb_version", 0)) >= 1, "Staged importer retained")
	var intact := model.get_node_or_null("Intact") as Node3D
	var parts := model.get_node_or_null("LargeParts") as Node3D
	_check(intact != null and intact.scale == Vector3.ONE, "Intact stage visible")
	_check(parts != null and parts.scale == Vector3.ZERO, "Large parts hidden initially")
	if parts != null:
		_check(parts.get_child_count() == COUNTS[filename][0], "Authored large parts retained: " + filename)
	var fragments := model.get_node_or_null("SmallFragments") as Node3D
	if COUNTS[filename][1] > 0:
		_check(fragments != null and fragments.scale == Vector3.ZERO, "Small fragments hidden initially")
		if fragments != null:
			_check(fragments.get_child_count() == COUNTS[filename][1], "Authored small fragments retained")


func _check_materials(model: Node3D, filename: String) -> void:
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		_check(mesh.mesh.get_surface_count() == 1, "One compatible surface per mesh")
		var material := mesh.get_active_material(0) as ORMMaterial3D
		_check(material != null, "Shared ORM material: " + filename)
		if material == null:
			continue
		_check(material.resource_path.begins_with(GROUP + "materials/"), "External material assigned")
		if shared.has(material.resource_path):
			_check(shared[material.resource_path] == material, "Material allocation shared across stages/models")
		shared[material.resource_path] = material
		_check(material.albedo_texture == load(MAPS + "group04_albedo.png"), "Shared albedo allocation")
		_check(material.normal_enabled and material.normal_texture == load(MAPS + "group04_normal.png"), "Shared normal allocation")
		_check(material.orm_texture == load(MAPS + "group04_orm.png"), "Shared ORM allocation")
		if filename.begins_with("04_crate") or filename == "04_cardboard_boxes.glb":
			_check(material.cull_mode == BaseMaterial3D.CULL_DISABLED, "Authored two-sided surfaces retained")


func _check_budget() -> void:
	var bytes := 0
	for kind: String in ["albedo", "normal", "orm"]:
		var texture := load(MAPS + "group04_" + kind + ".png") as Texture2D
		_check(texture != null, "Atlas imports: " + kind)
		if texture == null:
			continue
		_check(texture.get_size() == Vector2.ONE * (1024 if kind == "albedo" else 512), "Explicit texture size budget")
		var image := texture.get_image()
		_check(image.is_compressed() and image.has_mipmaps(), "VRAM compression and mipmaps")
		bytes += image.get_data_size()
	_check(bytes <= 1250 * 1024, "Atlas GPU payload fits 1.22 MiB")
	print("Group 04 atlas GPU payload: %.3f MiB" % (float(bytes) / (1024 * 1024)))


func _check_breakage(filename: String, secondary: bool) -> void:
	var world := Node3D.new()
	root.add_child(world)
	var effects := Node3D.new()
	world.add_child(effects)
	var prop := PROP.instantiate() as RigidBody3D
	prop.set("model_path", GROUP + filename)
	world.add_child(prop)
	prop.freeze = true
	prop.call("configure_world", effects, null)
	await physics_frame
	for i in 80:
		if bool(prop.get("_broken")):
			break
		prop.call("take_projectile_hit", 400.0, Vector3(0, .5, 0), Vector3.UP, Vector3.FORWARD, "GRENADE")
		await create_timer(.1).timeout
	_check(bool(prop.get("_broken")), "Prop breaks: " + filename)
	var part: RigidBody3D
	for child: Node in effects.get_children():
		if child is RigidBody3D and str(child.name).begins_with("Fragment_"):
			part = child as RigidBody3D
			break
	_check(part != null, "Primary debris spawned: " + filename)
	if part != null and secondary:
		var prefix := "Fragment_" + str(part.get("piece_name")) + "_Fragment_"
		prop.call("hit_environment_fragment", part, part.global_position, Vector3.FORWARD)
		await process_frame
		var found := false
		for child: Node in effects.get_children():
			found = found or str(child.name).begins_with(prefix)
		_check(found, "Crate part splits into authored small fragments")
	world.queue_free()
	await process_frame


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
