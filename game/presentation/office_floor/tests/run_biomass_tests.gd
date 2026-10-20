extends SceneTree
## Runtime checks for ADR-0061: volumetric biomass decals, the fusion of
## touching pieces into one mass.

const ATLAS := preload("res://game/presentation/office_floor/biomass_atlas.gd")
const FUSION := preload("res://game/presentation/office_floor/biomass_fusion.gd")
const DECAL := preload("res://game/presentation/office_floor/public/props/blood_decal.tscn")

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_atlas()
	_check_fusion()
	await _check_pieces()
	print("biomass tests: %d failures" % failures)
	quit(1 if failures > 0 else 0)


func _check_atlas() -> void:
	_expect(ATLAS.ids().size() == 6, "The atlas offers six biomass cells.")
	_expect(ATLAS.cell_of("biomass_03") == 2 and ATLAS.cell_of("biomass_99") == 5, "Cell index follows the texture id and stays in range.")
	var albedo := ATLAS.albedo_texture()
	var relief := ATLAS.relief_texture()
	_expect(albedo != null and relief != null, "Biomass albedo and relief textures load.")
	_expect(albedo.get_size() == Vector2(ATLAS.ATLAS) and relief.get_size() == Vector2(ATLAS.ATLAS), "Both maps match the padded atlas size.")
	_expect(ATLAS.albedo_bytes().size() == ATLAS.ATLAS.x * ATLAS.ATLAS.y * 4, "Albedo bytes are readable RGBA8.")
	_expect(ATLAS.relief_bytes().size() == ATLAS.ATLAS.x * ATLAS.ATLAS.y * 3, "Relief bytes are readable RGB8.")


func _alpha_at(image: Image, rect: Rect2, ppu: float, point: Vector2) -> float:
	var x := int((point.x - rect.position.x) * ppu)
	var y := int((rect.end.y - point.y) * ppu)
	return image.get_pixel(clampi(x, 0, image.get_width() - 1), clampi(y, 0, image.get_height() - 1)).a


func _check_fusion() -> void:
	var albedo := ATLAS.albedo_bytes()
	var relief := ATLAS.relief_bytes()
	var started := Time.get_ticks_msec()
	var solo: Dictionary = FUSION.fuse([{"cell": 1, "xform": Transform2D.IDENTITY}], albedo, relief, 300.0)
	var pair: Dictionary = FUSION.fuse([
		{"cell": 1, "xform": Transform2D.IDENTITY},
		{"cell": 4, "xform": Transform2D(0.6, Vector2(0.45, 0.4))},
	], albedo, relief, 300.0)
	print("biomass fuse: ", Time.get_ticks_msec() - started, " ms for a single and a pair")
	_expect(not solo.is_empty() and not pair.is_empty(), "Fusion returns images.")
	var solo_rect: Rect2 = solo["rect"]
	var pair_rect: Rect2 = pair["rect"]
	_expect(pair_rect.size.x > solo_rect.size.x, "The fused image grows to hold both pieces.")
	var image: Image = pair["albedo"]
	_expect(image.get_size() == (pair["relief"] as Image).get_size(), "Albedo and relief share a size.")
	var covered := 0
	var tall := 0.0
	var relief_image: Image = pair["relief"]
	for y in range(0, image.get_height(), 3):
		for x in range(0, image.get_width(), 3):
			if image.get_pixel(x, y).a > 0.5:
				covered += 1
			tall = maxf(tall, relief_image.get_pixel(x, y).b)
	_expect(covered > 500, "The fused mass has substance (%d samples)." % covered)
	_expect(tall > 0.5, "The fused relief keeps its height (%.2f)." % tall)
	var flat := relief_image.get_pixel(0, 0)
	_expect(absf(flat.r - 0.5) < 0.02 and absf(flat.g - 0.5) < 0.02 and flat.b < 0.02, "Empty space stays flat.")
	# Two cells overlapped exactly must never be darker or emptier than one.
	var self_pair: Dictionary = FUSION.fuse([{"cell": 2, "xform": Transform2D.IDENTITY}, {"cell": 2, "xform": Transform2D.IDENTITY}], albedo, relief, 300.0)
	var self_solo: Dictionary = FUSION.fuse([{"cell": 2, "xform": Transform2D.IDENTITY}], albedo, relief, 300.0)
	var a: Image = self_pair["albedo"]
	var b: Image = self_solo["albedo"]
	var offset := Vector2i((a.get_width() - b.get_width()) / 2, (a.get_height() - b.get_height()) / 2)
	var mismatch := 0
	for y in range(0, b.get_height(), 5):
		for x in range(0, b.get_width(), 5):
			if absf(a.get_pixel(x + offset.x, y + offset.y).a - b.get_pixel(x, y).a) > 0.3:
				mismatch += 1
	_expect(mismatch < 400, "A piece fused with itself keeps its silhouette (%d differing samples)." % mismatch)


func _stage_piece(stage: Node3D, texture: String, position: Vector3, yaw := 0.0) -> Node3D:
	var piece := DECAL.instantiate() as Node3D
	piece.call("configure_blood", texture, "floor")
	stage.add_child(piece)
	piece.position = position
	piece.rotation.y = yaw
	return piece


func _check_pieces() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	current_scene = stage
	var a := _stage_piece(stage, "biomass_02", Vector3.ZERO)
	var b := _stage_piece(stage, "biomass_05", Vector3(0.5, 0, 0.35), 0.8)
	var far := _stage_piece(stage, "biomass_01", Vector3(6, 0, 0))
	await process_frame
	var visual := a.get_node("BloodQuad") as MeshInstance3D
	_expect(visual.mesh is ArrayMesh and visual.mesh.surface_get_material(0) is ShaderMaterial, "A biomass piece is a relief mesh with the biomass shader.")
	_expect(visual.mesh.get_aabb().size.z > 0.0 or visual.mesh.custom_aabb.size.z > 0.0, "The relief mesh has height.")
	_expect(a.has_method("biomass_cell") and a.call("biomass_cell") == 1, "Biomass_02 uses the second cell.")
	_expect(a.call("get_blood_config")["texture"] == "biomass_02", "Biomass saves through the blood config.")
	await _wait_until(func() -> bool: return not (b.get_node("BloodQuad") as MeshInstance3D).visible, 120)
	_expect(visual.visible and not (b.get_node("BloodQuad") as MeshInstance3D).visible, "Touching pieces become one mass: first draws, second hides.")
	_expect(far.get_node("BloodQuad").visible, "A distant piece keeps its own relief.")
	var fused_rect := (visual.mesh as ArrayMesh).custom_aabb
	_expect(fused_rect.size.x > 1.0, "The fused mesh spans both pieces (%.2f m)." % fused_rect.size.x)
	b.position = Vector3(5, 0, 5)
	await process_frame
	await process_frame
	_expect((b.get_node("BloodQuad") as MeshInstance3D).visible, "A moved piece shows its own relief at once.")
	await _wait_until(func() -> bool: return (visual.mesh as ArrayMesh).custom_aabb.size.x < 1.0, 120)
	_expect((visual.mesh as ArrayMesh).custom_aabb.size.x < 1.0, "The first piece reverts to its own cell once nothing touches it.")
	b.position = Vector3(0.5, 0, 0.35)
	await _wait_until(func() -> bool: return not (b.get_node("BloodQuad") as MeshInstance3D).visible, 120)
	_expect(not (b.get_node("BloodQuad") as MeshInstance3D).visible, "Moving it back fuses it again.")
	a.queue_free()
	await process_frame
	await process_frame
	_expect((b.get_node("BloodQuad") as MeshInstance3D).visible, "Removing the first piece releases the second.")
	var plain := _stage_piece(stage, "splatter_01", Vector3(-6, 0, 0))
	_expect(not plain.has_meta("biomass_piece") and plain.get_node_or_null("BiomassFit") == null, "Ordinary blood is untouched by biomass fitting.")
	plain.call("configure_blood", "biomass_03", "floor")
	_expect(plain.has_meta("biomass_piece"), "A decal can be switched to biomass.")
	stage.queue_free()


func _wait_until(condition: Callable, frames: int) -> void:
	for _i in frames:
		if condition.call():
			return
		await process_frame
		OS.delay_msec(10)


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failures += 1
		print("FAIL: ", message)
