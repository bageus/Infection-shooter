extends RefCounted
## Owns the imported prop geometry, ordered damage groups and their collision shapes.
## The scene root supplies the body; no gameplay durability or effects live here.

const DAMAGE := preload("res://game/presentation/office_floor/environment_damage.gd")
var visual: Node3D
var intact: Node3D
var stages: Array[Node3D] = []
var variants: Array[Node3D] = []
var shapes: Array[CollisionShape3D] = []
var meshes: Array[MeshInstance3D] = []


func load_visual(body: RigidBody3D, model_path: String) -> bool:
	var packed := load(model_path) as PackedScene
	if packed == null:
		push_error("Environment model unavailable: " + model_path)
		return false
	visual = packed.instantiate() as Node3D
	if visual == null:
		return false
	visual.name = "Visual"
	if "wall_TV" in model_path.get_file():
		# Authored televisions lie in XZ; wall placement expects a +Z front.
		visual.rotation.x = PI / 2.0
	body.add_child(visual)
	return true


func prepare_stages(model_path: String) -> void:
	discover_stages()
	if model_path.get_file() == "06_conference_chair.glb":
		# Only the baked chair may affect its initial height or collision.
		for stage in stages:
			stage.hide()
		for variant in variants:
			variant.hide()
	_add_missing_bookcase_shelves(model_path)
	# This GLB exports the complete table alongside a visible Primary debris group.
	if model_path.get_file() == "07_table_square.glb":
		var primary := DAMAGE.find_named(visual, "Primary")
		if primary != null:
			primary.hide()


func rebuild(body: RigidBody3D) -> void:
	for shape in shapes:
		shape.set_deferred("disabled", true)
		shape.queue_free()
	shapes.clear()
	meshes.clear()
	add_shapes(body, visual)


func add_shapes(body: RigidBody3D, node: Node) -> float:
	var volume := 0.0
	if node is MeshInstance3D:
		var mesh := node as MeshInstance3D
		if mesh.mesh != null and _locally_visible(mesh) and absf(mesh.global_basis.determinant()) > 0.000000000001:
			var box := BoxShape3D.new()
			var bounds := mesh.get_aabb()
			box.size = Vector3(maxf(bounds.size.x, 0.02), maxf(bounds.size.y, 0.02), maxf(bounds.size.z, 0.02))
			var shape := CollisionShape3D.new()
			shape.name = mesh.name
			shape.shape = box
			body.add_child(shape)
			shapes.append(shape)
			meshes.append(mesh)
			var local := body.global_transform.affine_inverse() * mesh.global_transform
			shape.transform = local
			shape.position += local.basis * bounds.get_center()
			volume += box.size.x * box.size.y * box.size.z * absf(local.basis.determinant())
	for child in node.get_children():
		volume += add_shapes(body, child)
	return volume


func _locally_visible(node: Node) -> bool:
	# A hidden mission must not remove authored intact geometry from physics.
	while node != null:
		if node is Node3D and not (node as Node3D).visible:
			return false
		if node == visual:
			return true
		node = node.get_parent()
	return false


func discover_stages() -> void:
	intact = DAMAGE.find_named(visual, "Intact")
	for name_part in ["Hit_01", "Dent_01", "Dent_02", "Dent_03", "Power_Off"]:
		var variant: Node3D = DAMAGE.find_named(visual, name_part)
		if variant != null:
			variants.append(variant)
	# Staged GLBs (addons/staged_glb_import) add LargeParts → Small/JaggedFragments,
	# PlantDestroyed → PotFragments and the in-place DamageReady facade.
	for name_part in ["Modular", "Door_Off", "LargeParts", "SmallFragments", "JaggedFragments", "PlantDestroyed", "PotFragments", "Broken_7", "Fragments", "Primary", "Panels", "Medium", "Fine", "TopSecondary", "DamageReady"]:
		var stage: Node3D = DAMAGE.find_named(visual, name_part)
		if stage != null:
			stages.append(stage)


func _add_missing_bookcase_shelves(model_path: String) -> void:
	if model_path.get_file() not in ["03_book_case.glb", "03_book_case_with_back.glb"] or intact == null:
		return
	var baked := intact.find_child("Intact*", true, false) as MeshInstance3D
	if baked == null:
		return # Re-exported staged bookcases already contain their shelves.
	var material: Material = baked.get_active_material(0)
	if material == null:
		var wood := StandardMaterial3D.new()
		wood.albedo_color = Color(0.45, 0.27, 0.16)
		material = wood
	for shelf_height in [0.50, 0.95, 1.40, 1.85, 2.30]:
		var shelf := MeshInstance3D.new()
		shelf.name = "VisibleShelf"
		var mesh := BoxMesh.new()
		mesh.size = Vector3(1.94, 0.035, 0.46)
		mesh.material = material
		shelf.mesh = mesh
		intact.add_child(shelf)
		shelf.position.y = shelf_height


static func is_glass_mesh(mesh: MeshInstance3D) -> bool:
	if mesh == null or mesh.mesh == null:
		return false
	var lower := mesh.name.to_lower()
	if "glass" in lower or "mirror" in lower:
		return true
	for surface in mesh.mesh.get_surface_count():
		var material := mesh.get_active_material(surface)
		if material != null and ("glass" in material.resource_name.to_lower() or "mirror" in material.resource_name.to_lower()):
			return true
	return false
