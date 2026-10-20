extends RefCounted
## Flat grid for one biomass patch. The mesh lies in the local XY plane facing
## +Z; the shader lifts it by the relief height.

const ATLAS := preload("res://game/presentation/office_floor/biomass_atlas.gd")
const SHADER := preload("res://game/presentation/office_floor/biomass_surface.gdshader")
## Highest relief lift in local units (a one metre patch rises 5 cm).
const DEPTH := 0.05
const CELLS_PER_UNIT := 48.0
const MAX_CELLS := 160
const MIN_CELLS := 6


## rect: the patch in local units. UV runs 0..1 over the rect, v downward.
static func grid(rect: Rect2, material: Material, lift: float) -> ArrayMesh:
	var columns := clampi(ceili(rect.size.x * CELLS_PER_UNIT), MIN_CELLS, MAX_CELLS)
	var rows := clampi(ceili(rect.size.y * CELLS_PER_UNIT), MIN_CELLS, MAX_CELLS)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for row in rows + 1:
		var v := float(row) / rows
		for column in columns + 1:
			var u := float(column) / columns
			vertices.append(Vector3(rect.position.x + u * rect.size.x, rect.end.y - v * rect.size.y, 0.0))
			normals.append(Vector3.BACK)
			uvs.append(Vector2(u, v))
	for row in rows:
		for column in columns:
			var a := row * (columns + 1) + column
			var b := a + 1
			var c := a + columns + 1
			var d := c + 1
			indices.append_array([a, c, b, b, c, d])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	# The shader lifts vertices after the AABB is computed.
	mesh.custom_aabb = AABB(Vector3(rect.position.x, rect.position.y, -0.01), Vector3(rect.size.x, rect.size.y, lift + 0.02))
	return mesh


static func material(albedo: Texture2D, relief: Texture2D, uv_rect: Rect2) -> ShaderMaterial:
	var result := ShaderMaterial.new()
	result.shader = SHADER
	result.set_shader_parameter("albedo_texture", albedo)
	result.set_shader_parameter("relief_texture", relief)
	result.set_shader_parameter("uv_rect", Vector4(uv_rect.position.x, uv_rect.position.y, uv_rect.size.x, uv_rect.size.y))
	result.set_shader_parameter("depth", DEPTH)
	return result


static var _cells := {}


## One untouched atlas cell, shared by every piece that shows it.
static func cell_patch(cell: int) -> ArrayMesh:
	if not _cells.has(cell):
		_cells[cell] = _build_cell(cell)
	return _cells[cell]


static func _build_cell(cell: int) -> ArrayMesh:
	var foot := ATLAS.FOOTPRINT
	var patch_material := material(ATLAS.albedo_texture(), ATLAS.relief_texture(), ATLAS.uv_rect(cell))
	return grid(Rect2(-foot * 0.5, foot), patch_material, DEPTH)


## A fused patch built from fusion images over rect (local units).
static func fused_patch(fused: Dictionary) -> ArrayMesh:
	var patch_material := material(ImageTexture.create_from_image(fused["albedo"]), ImageTexture.create_from_image(fused["relief"]), Rect2(0, 0, 1, 1))
	return grid(fused["rect"], patch_material, DEPTH)
