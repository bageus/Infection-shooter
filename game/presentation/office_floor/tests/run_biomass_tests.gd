extends SceneTree
## Runtime checks for ADR-0061: volumetric biomass decals, the fusion of
## touching pieces into one mass.

const ATLAS := preload("res://game/presentation/office_floor/biomass_atlas.gd")
const FUSION := preload("res://game/presentation/office_floor/biomass_fusion.gd")
const CLIP := preload("res://game/presentation/office_floor/biomass_clip.gd")
const DECAL := preload("res://game/presentation/office_floor/public/props/blood_decal.tscn")

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_atlas()
	_check_fusion()
	await _check_pieces()
	await _check_impact_audio()
	await _check_edges()
	await _check_inner_corner()
	await _check_object_faces()
	await _check_settling()
	await _check_hidden_group()
	await _check_floor_fit()
	await _check_support()
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
	# A degenerate transform must give "nothing to draw", not a failed huge allocation.
	var broken := Transform2D(Vector2(NAN, 0.0), Vector2(0.0, 1.0), Vector2.ZERO)
	_expect(FUSION.fuse([{"cell": 1, "xform": broken}], albedo, relief, 300.0).is_empty(), "A NaN transform fuses to nothing.")
	var stretched := Transform2D(Vector2(1e30, 0.0), Vector2(0.0, 1.0), Vector2.ZERO)
	var huge: Dictionary = FUSION.fuse([{"cell": 1, "xform": stretched}], albedo, relief, 300.0)
	_expect(huge.is_empty() or (huge["albedo"] as Image).get_width() <= 897, "An extreme transform keeps the buffers bounded.")


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
	await _wait_until(func() -> bool: return not (b.get_node("BloodQuad") as MeshInstance3D).visible, 900)
	_expect(visual.visible and not (b.get_node("BloodQuad") as MeshInstance3D).visible, "Touching pieces become one mass: first draws, second hides.")
	_expect(far.get_node("BloodQuad").visible, "A distant piece keeps its own relief.")
	var fused_rect := (visual.mesh as ArrayMesh).custom_aabb
	_expect(fused_rect.size.x > 1.0, "The fused mesh spans both pieces (%.2f m)." % fused_rect.size.x)
	b.position = Vector3(5, 0, 5)
	await process_frame
	await process_frame
	_expect((b.get_node("BloodQuad") as MeshInstance3D).visible, "A moved piece shows its own relief at once.")
	await _wait_until(func() -> bool: return (visual.mesh as ArrayMesh).custom_aabb.size.x < 1.0, 900)
	_expect((visual.mesh as ArrayMesh).custom_aabb.size.x < 1.0, "The first piece reverts to its own cell once nothing touches it.")
	b.position = Vector3(0.5, 0, 0.35)
	await _wait_until(func() -> bool: return not (b.get_node("BloodQuad") as MeshInstance3D).visible, 900)
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


func _check_impact_audio() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var floor_view := preload("res://game/presentation/office_floor/public/base_floor_renderer.gd").new()
	stage.add_child(floor_view)
	var pool := preload("res://game/features/combat/public/impact_effects.gd").new()
	stage.add_child(pool)
	pool.surface_hit = Callable(floor_view, "bake_surface_hit")
	var wall := StaticBody3D.new()
	stage.add_child(wall)
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	mesh.mesh.size = Vector3(6, 4, 0.2)
	wall.add_child(mesh)
	pool.register_surface(wall, mesh)
	var piece := DECAL.instantiate() as Node3D
	piece.call("configure_blood", "biomass_01", "wall")
	stage.add_child(piece)
	piece.position.z = 0.1
	piece.call("configure_projection", mesh)
	piece.get_node("BiomassFit").set_process(false)
	var bullet := preload("res://game/features/combat/public/prototype_bullet.tscn").instantiate()
	stage.add_child(bullet)
	bullet.call("configure_world", stage, pool)
	bullet.call("setup_projectile", Vector3.FORWARD, null, 26, 36, 34, "PISTOL", Vector3(0, 0, 2))
	bullet.set_physics_process(false)
	var pixels := ATLAS.albedo_bytes()
	var opaque := Vector2.ZERO
	var empty := Vector2.ZERO
	var origin := ATLAS.cell_origin(0)
	for y in range(0, ATLAS.CELL.y, 10):
		for x in range(0, ATLAS.CELL.x, 10):
			var at := origin + Vector2i(x, y)
			var alpha := pixels[(at.y * ATLAS.ATLAS.x + at.x) * 4 + 3]
			var uv := Vector2(x + 0.5, y + 0.5) / Vector2(ATLAS.CELL)
			if alpha > 220: opaque = uv
			if alpha < 10: empty = uv
	var visual := piece.get("_visual") as MeshInstance3D
	var hit := visual.to_global(Vector3((opaque.x - 0.5) * ATLAS.FOOTPRINT.x, 0.5 - opaque.y, 0))
	bullet.call("_handle_hit", wall, hit, Vector3.BACK)
	var voices := floor_view.find_children("Sfx_hit_biomass", "AudioStreamPlayer3D", true, false)
	_expect(voices.size() == 1, "Real bullet dispatch plays biomass impact on an opaque wall patch")
	if not voices.is_empty():
		var voice := voices[0] as AudioStreamPlayer3D
		_expect(voice.stream is AudioStreamOggVorbis and voice.stream.resource_path.ends_with("biomass/Thudding_impact_of_b.ogg"), "Biomass uses the owner Vorbis recording")
		_expect(voice.global_position.distance_to(hit) < 0.03, "Biomass impact sounds at the actual hit")
	for voice in voices: voice.free()
	var hole := visual.to_global(Vector3((empty.x - 0.5) * ATLAS.FOOTPRINT.x, 0.5 - empty.y, 0))
	bullet.call("_handle_hit", wall, hole, Vector3.BACK)
	bullet.call("_handle_hit", wall, Vector3(2, 0, 0.1), Vector3.BACK)
	_expect(floor_view.find_children("Sfx_hit_biomass", "AudioStreamPlayer3D", true, false).is_empty(), "Transparent pixels and bare wall stay free of biomass sounds")
	piece.position.x += 1.5
	bullet.call("_handle_hit", wall, hit, Vector3.BACK)
	_expect(floor_view.find_children("Sfx_hit_biomass", "AudioStreamPlayer3D", true, false).is_empty(), "Moving a patch moves its audible coverage immediately")
	var fused_image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	fused_image.fill(Color.TRANSPARENT)
	for y in 4:
		for x in 2: fused_image.set_pixel(x, y, Color.RED)
	var fused_material := preload("res://game/presentation/office_floor/biomass_mesh.gd").material(ImageTexture.create_from_image(fused_image), ATLAS.relief_texture(), Rect2(0, 0, 1, 1))
	var fused_mesh := preload("res://game/presentation/office_floor/biomass_mesh.gd").grid(Rect2(-1, -0.5, 2, 1), fused_material, 0.05)
	piece.call("biomass_show_fused", fused_mesh)
	var fused_hit := visual.to_global(Vector3(-0.8, 0, 0))
	bullet.call("_handle_hit", wall, fused_hit, Vector3.BACK)
	voices = floor_view.find_children("Sfx_hit_biomass", "AudioStreamPlayer3D", true, false)
	_expect(voices.size() == 1, "A fused bridge outside the original cell uses its current silhouette")
	for voice in voices: voice.free()
	bullet.call("_handle_hit", wall, visual.to_global(Vector3(0.8, 0, 0)), Vector3.BACK)
	piece.call("biomass_hide")
	bullet.call("_handle_hit", wall, fused_hit, Vector3.BACK)
	_expect(floor_view.find_children("Sfx_hit_biomass", "AudioStreamPlayer3D", true, false).is_empty(), "Fused transparent pixels and hidden members do not sound")
	piece.free()
	_expect(not mesh.has_meta(&"biomass_impact_audio"), "Deleting a patch unregisters the receiver")
	stage.queue_free()
	await process_frame


func _wall_piece(stage: Node3D, wall: MeshInstance3D, at: Vector3, anchor_name := "wall_a") -> Node3D:
	var piece := DECAL.instantiate() as Node3D
	piece.call("configure_blood", "biomass_01", "wall")
	stage.add_child(piece)
	piece.position = at
	piece.get_node("BiomassFit").set_process(false)
	piece.call("attach_blood", wall, anchor_name)
	return piece


func _wall(stage: Node3D, size: Vector3, at: Vector3, label := "Wall") -> MeshInstance3D:
	var wall := MeshInstance3D.new()
	wall.name = label
	wall.mesh = BoxMesh.new()
	wall.mesh.size = size
	wall.position = at
	stage.add_child(wall)
	return wall


func _check_edges() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var wall := _wall(stage, Vector3(6, 4, 0.2), Vector3(0, 2, 0))
	var piece := _wall_piece(stage, wall, Vector3(0, 3.8, 0.1))
	await process_frame
	var visual := piece.get_node("BloodQuad") as MeshInstance3D
	var half: Vector4 = CLIP.value(visual, "clip_b")
	var area: Vector4 = CLIP.value(visual, "clip_a")
	var limit: Vector4 = CLIP.value(visual, "clip_limit")
	_expect(is_equal_approx(half.x, 3.0) and is_equal_approx(half.y, 2.0), "A wall patch is fitted to the real wall face (%s)." % half)
	var top_edge: Vector3 = visual.to_global(Vector3(0, area.y + half.y, 0))
	_expect(absf(top_edge.y - 4.0) < 0.01, "The clip's upper edge is the wall top, not the patch (y=%.2f)." % top_edge.y)
	var patch_top := visual.to_global(Vector3(0, 0.5, 0)).y
	_expect(patch_top > 4.0, "The patch itself reaches past the wall top (%.2f), so the edge is what cuts it." % patch_top)
	_expect(is_equal_approx(limit.z, 0.2) and is_equal_approx(limit.x, 0.2) and is_equal_approx(limit.y, 0.2), "Mass wraps round the wall top and ends over the wall's thickness (limits %s)." % limit)
	_expect(limit.w < 0.0, "The wall foot meets the floor, so mass folds onto the floor there.")
	piece.position.y = 1.0
	await process_frame
	await process_frame
	var lowered: Vector4 = CLIP.value(visual, "clip_a")
	_expect(absf(visual.to_global(Vector3(0, lowered.y + half.y, 0)).y - 4.0) < 0.01, "The fit follows a moved patch.")
	# Outer corner: mass on the wall wraps its end face, where the next wall continues.
	piece.position = Vector3(2.9, 1.0, 0.1)
	await process_frame
	await process_frame
	var corner_limit: Vector4 = CLIP.value(visual, "clip_limit")
	var corner_area: Vector4 = CLIP.value(visual, "clip_a")
	var right_edge := visual.to_global(Vector3(corner_area.x + half.x, 0, 0))
	_expect(absf(right_edge.x - 3.0) < 0.01 and is_equal_approx(corner_limit.x, 0.2), "At a wall corner the mass continues round the end onto the next face (edge x=%.2f)." % right_edge.x)
	# A second wall behind the end continues the end face: the mass follows it.
	var neighbour := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	(shape.shape as BoxShape3D).size = Vector3(0.2, 4, 5)
	neighbour.add_child(shape)
	stage.add_child(neighbour)
	neighbour.position = Vector3(2.9, 2, -2.6)
	await physics_frame
	await physics_frame
	piece.set("_clip_stamp", [])
	piece.call("_clip_biomass")
	var run: Vector4 = CLIP.value(visual, "clip_limit")
	_expect(run.x > 4.0, "Round an outer corner the mass runs on along the neighbouring wall (%.2f)." % run.x)
	var slanted := _wall(stage, Vector3(6, 4, 0.2), Vector3(0, 2, -5))
	slanted.rotation.y = 1.0
	var tilted := _wall_piece(stage, slanted, Vector3(0, 2, -4.9))
	await process_frame
	_expect(CLIP.value(tilted.get_node("BloodQuad") as MeshInstance3D, "clip_b") == Vector4(), "A patch off its receiver's face is not clipped.")
	stage.queue_free()
	await process_frame


func _solid(stage: Node3D, size: Vector3, at: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	(shape.shape as BoxShape3D).size = size
	body.add_child(shape)
	stage.add_child(body)
	body.position = at


func _check_inner_corner() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	# Wall A (x -3..3.2) ends in wall B (x 3..3.2, standing out in front of A).
	var wall := _wall(stage, Vector3(6.2, 4, 0.2), Vector3(0.1, 2, 0))
	_solid(stage, Vector3(0.2, 4, 3), Vector3(3.1, 2, 1.5))
	await physics_frame
	await physics_frame
	var piece := _wall_piece(stage, wall, Vector3(2.8, 2, 0.1))
	await process_frame
	var visual := piece.get_node("BloodQuad") as MeshInstance3D
	var half: Vector4 = CLIP.value(visual, "clip_b")
	var area: Vector4 = CLIP.value(visual, "clip_a")
	var limit: Vector4 = CLIP.value(visual, "clip_limit")
	_expect(limit.x < 0.0 and limit.x >= -4.0, "At an inner corner the mass folds onto the other wall (limit %s)." % limit)
	var corner := visual.to_global(Vector3(area.x + half.x, area.y, 0)).x
	_expect(absf(corner - 3.0) < 0.01, "The fold starts on the corner line, the face of the other wall (x=%.3f)." % corner)
	_expect(limit.y > 0.0, "The open end of the wall still wraps as a convex edge (limit %s)." % limit)
	stage.queue_free()
	await process_frame


func _check_object_faces() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	# A crate on a shelf, 1 x 0.8 x 0.6, free on every side.
	var crate := _wall(stage, Vector3(1.0, 0.8, 0.6), Vector3(0, 1.4, 0), "Crate")
	_solid(stage, Vector3(1.0, 0.8, 0.6), Vector3(0, 1.4, 0))
	await physics_frame
	await physics_frame
	var piece := _wall_piece(stage, crate, Vector3(0.4, 1.4, 0.3), "crate_a")
	await process_frame
	var visual := piece.get_node("BloodQuad") as MeshInstance3D
	var half: Vector4 = CLIP.value(visual, "clip_b")
	var limit: Vector4 = CLIP.value(visual, "clip_limit")
	_expect(is_equal_approx(half.x, 0.5) and is_equal_approx(half.y, 0.4), "A patch on a crate is fitted to the crate's face (%s)." % half)
	_expect(absf(limit.x - 0.6) < 0.01 and absf(limit.z - 0.6) < 0.01 and absf(limit.w - 0.6) < 0.01, "It wraps onto the adjacent faces up to the crate's depth (limits %s)." % limit)
	stage.queue_free()
	await process_frame


func _check_settling() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var wall := _wall(stage, Vector3(6, 4, 0.2), Vector3(0, 2, 0))
	var piece := _wall_piece(stage, wall, Vector3(0.5, 2.5, 0.1))
	await process_frame
	await process_frame
	wall.queue_free()
	await _wait_until(func() -> bool: return piece.has_meta("biomass_settled") and absf(piece.global_position.y - 0.0135) < 0.001, 600)
	var visual := piece.get("_visual") as MeshInstance3D
	_expect(piece.get_blood_config()["surface"] == "floor" and piece.get_blood_attachment()["owner"] == "", "A patch whose object was destroyed is no longer on the wall.")
	_expect(absf(piece.global_position.y - 0.0135) < 0.001 and piece.global_basis.y.dot(Vector3.UP) > 0.99, "It settles onto the floor, lying flat (y=%.3f)." % piece.global_position.y)
	_expect(piece.get_meta("biomass_settled") == "baked" and is_equal_approx(float(CLIP.value(visual, "depth_scale")), 0.25), "It is pressed into the floor as shallow relief.")
	_expect(CLIP.value(visual, "clip_b") == Vector4(), "Settled mass carries no wall clip.")
	piece.get_node("BiomassFit").set_process(true)
	var friend := DECAL.instantiate() as Node3D
	friend.call("configure_blood", "biomass_03", "floor")
	stage.add_child(friend)
	friend.position = piece.global_position + Vector3(0.4, 0, 0)
	await _wait_until(func() -> bool: return (friend.get("_visual") as MeshInstance3D).visible != (piece.get("_visual") as MeshInstance3D).visible, 900)
	_expect((friend.get("_visual") as MeshInstance3D).visible != (piece.get("_visual") as MeshInstance3D).visible, "Settled mass fuses with floor biomass next to it.")
	# Glass: the pane is hidden, the patch drops and stays a loose heap.
	var pane := _wall(stage, Vector3(3, 2, 0.05), Vector3(-6, 1.2, 0), "GlassPane")
	var drop := _wall_piece(stage, pane, Vector3(-6, 1.2, 0.03), "glass_a")
	await process_frame
	await process_frame
	pane.visible = false
	await _wait_until(func() -> bool: return drop.has_meta("biomass_settled") and absf(drop.global_position.y - 0.0135) < 0.001, 600)
	_expect(drop.get_meta("biomass_settled", "") == "fallen" and absf(drop.global_position.y - 0.0135) < 0.001, "A patch on broken glass falls to the floor.")
	_expect(is_equal_approx(float(CLIP.value(drop.get("_visual") as MeshInstance3D, "depth_scale")), 1.0), "Fallen glass mass is not baked flat.")
	Engine.set_meta("planning_active", true)
	var held_wall := _wall(stage, Vector3(2, 2, 0.2), Vector3(0, 1, -8))
	var held := _wall_piece(stage, held_wall, Vector3(0, 1, -7.9))
	await process_frame
	await process_frame
	held_wall.visible = false
	await process_frame
	await process_frame
	_expect(not held.has_meta("biomass_settled") and held.get_blood_config()["surface"] == "wall", "Nothing settles while the planner is open.")
	Engine.set_meta("planning_active", false)
	stage.queue_free()
	await process_frame


# The object is broken up by hiding the group that holds its mesh (props hide
# their intact model, not the mesh): the mass must still come down.
func _check_hidden_group() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var group := Node3D.new()
	stage.add_child(group)
	var wall := _wall(group, Vector3(6, 4, 0.2), Vector3(0, 2, 0))
	var piece := _wall_piece(stage, wall, Vector3(0.5, 2.5, 0.1))
	await process_frame
	await process_frame
	group.visible = false
	await _wait_until(func() -> bool: return piece.has_meta("biomass_settled") and absf(piece.global_position.y - 0.0135) < 0.001, 600)
	_expect(piece.has_meta("biomass_settled") and piece.get_blood_config()["surface"] == "floor", "Mass settles when the group holding its mesh is hidden, not only the mesh.")
	stage.queue_free()
	await process_frame


func _floor_piece(stage: Node3D, floor_view: Node3D, at: Vector3) -> Node3D:
	var piece := DECAL.instantiate() as Node3D
	piece.call("configure_blood", "biomass_01", "floor")
	stage.add_child(piece)
	piece.call("configure_floor_debris", floor_view)
	piece.position = at
	piece.scale = Vector3.ONE
	return piece


# Floor mass keeps inside the level and climbs the walls beside it.
func _check_floor_fit() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var source := GDScript.new()
	source.source_code = "extends Node3D\nvar floor_size := Vector2(10.0, 8.0)\n"
	source.reload()
	var floor_view := Node3D.new()
	floor_view.set_script(source)
	stage.add_child(floor_view)
	_solid(stage, Vector3(0.2, 3.0, 6.0), Vector3(1.0, 1.5, 0.0))
	await physics_frame
	await physics_frame
	var beside := _floor_piece(stage, floor_view, Vector3(0.5, 0.0135, 0.0))
	var corner := _floor_piece(stage, floor_view, Vector3(4.8, 0.0135, 3.8))
	await process_frame
	await process_frame
	var near_visual := beside.get("_visual") as MeshInstance3D
	var wall := CLIP.value(near_visual, "wall_p0") as Vector4
	_expect(wall.w > 0.0 and absf(Vector2(wall.x, wall.y).length() - 1.0) < 0.01, "Floor mass beside a wall finds it and climbs it (%s)." % wall)
	var reach := CLIP.value(near_visual, "wall_r0") as Vector4
	_expect(reach.y > reach.x and reach.x < 0.0 and reach.y > 0.0, "The wall counts along the stretch that stands there (%s)." % reach)
	_expect(CLIP.value(near_visual, "world_clip") == Vector4(-5.0, -4.0, 5.0, 4.0), "Floor mass is bounded by the level edge.")
	var far_visual := corner.get("_visual") as MeshInstance3D
	_expect(CLIP.value(far_visual, "wall_p0") == Vector4(), "A patch in the open has no wall to climb.")
	_expect(CLIP.value(far_visual, "world_clip") == Vector4(-5.0, -4.0, 5.0, 4.0), "A patch at the level's corner is bounded too.")
	var shader: Shader = load("res://game/presentation/office_floor/biomass_surface.gdshader")
	_expect(not shader.code.contains("instance uniform"), "The biomass shader uses no instance uniforms (a small global buffer on some hardware).")
	stage.queue_free()
	await process_frame


# A frame whose box spans the whole opening, with collision only on the lower
# half: mass over the empty half must be cut, not left hanging.
func _check_support() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var frame := _wall(stage, Vector3(4, 4, 0.2), Vector3(0, 2, 0), "Frame")
	_solid(stage, Vector3(4, 2, 0.2), Vector3(0, 1, 0))
	await physics_frame
	await physics_frame
	var piece := _wall_piece(stage, frame, Vector3(0, 2.0, 0.1), "frame_a")
	await process_frame
	await process_frame
	var visual := piece.get("_visual") as MeshInstance3D
	var texture := CLIP.value(visual, "support_texture") as Texture2D
	_expect(texture != null and (CLIP.value(visual, "support_rect") as Vector4).z > 0.0, "A patch on a receiver with collision gets a support mask.")
	if texture != null:
		var image := texture.get_image()
		_expect(image.get_pixel(6, 2).r > 0.5 and image.get_pixel(6, 15).r < 0.5, "Mass over solid is kept and over empty space is cut.")
	var bare := _wall_piece(stage, _wall(stage, Vector3(4, 4, 0.2), Vector3(0, 2, -6)), Vector3(0, 2.0, -5.9), "bare_a")
	await process_frame
	await process_frame
	_expect(CLIP.value(bare.get("_visual") as MeshInstance3D, "support_texture") == null, "A receiver without collision gets no mask (the patch stays whole).")
	stage.queue_free()
	await process_frame
