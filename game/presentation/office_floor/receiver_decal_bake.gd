extends RefCounted
## One packed texture pair per receiver, never a new object for each hit.
const SHADER := preload("res://game/presentation/office_floor/receiver_decal.gdshader")
const PIXELS := preload("res://game/presentation/office_floor/decal_pixels.gd")
const FACE := 128
const MAX_RECEIVERS := 12
const MAX_QUEUE := 32
const MAX_ARCHIVE := 24
var pages: Dictionary = {}
# Released pages keep their CPU layers (id -> {anchor, layers, density}) so decals return with the page.
# Bound: at most MAX_ARCHIVE anchors, oldest release dropped first; stored at half size (2 x 192x128 RGBA8, ~0.2 MB each), upscaled bilinear on restore.
var _archive: Dictionary = {}
var queue: Array[Dictionary] = []
var uploads := 0
var sources: RefCounted

func stamp(anchor: MeshInstance3D, point: Vector3, normal: Vector3, kind: String, frame: int, size: float, opacity: float, turns: int = 0, glass: bool = false, center: Vector2 = Vector2(0.5, 0.5)) -> bool:
	if not is_instance_valid(anchor) or anchor.mesh == null or not point.is_finite() or not normal.is_finite() or not is_finite(opacity) or opacity <= 0.0 or not is_finite(size) or size <= 0.0 or queue.size() >= MAX_QUEUE: return false
	if absf(anchor.global_basis.determinant()) < 1e-9 or not sources.sources.has(kind) or frame < 0 or frame >= sources.sources[kind].size(): return false
	queue.append({"anchor": weakref(anchor), "point": anchor.to_local(point), "normal": (anchor.global_basis.transposed() * normal).normalized(),
		"kind": kind, "frame": frame, "size": minf(size, 4.0), "opacity": opacity, "turns": turns, "glass": glass, "center": center})
	return true

func step() -> bool:
	for index in 2:
		if queue.is_empty(): break
		_apply(queue.pop_front())
	for id: int in pages.keys():
		var page: Dictionary = pages[id]
		var anchor: MeshInstance3D = page.anchor.get_ref()
		if not is_instance_valid(anchor) or not anchor.is_visible_in_tree():
			_release(id)
			continue
		if not page.dirty: continue
		for layer: Dictionary in page.layers:
			if layer.texture == null: layer.texture = ImageTexture.create_from_image(layer.image)
			else: (layer.texture as ImageTexture).update(layer.image)
		page.material.set_shader_parameter("damage", page.layers[0].texture)
		page.material.set_shader_parameter("scuffs", page.layers[1].texture)
		page.dirty = false
		uploads += 1
		break
	return not queue.is_empty() or _dirty()

func _apply(request: Dictionary) -> void:
	var anchor := request.anchor.get_ref() as MeshInstance3D
	if not is_instance_valid(anchor) or not anchor.is_visible_in_tree(): return
	var id := anchor.get_instance_id()
	if not pages.has(id):
		if anchor.material_overlay != null: return
		if pages.size() >= MAX_RECEIVERS: _release(int(pages.keys()[0]))
		pages[id] = _page(anchor, request.glass)
	var page: Dictionary = pages[id]
	var mapping := face_mapping(anchor.get_aabb(), request.point, request.normal, request.glass, anchor.global_basis)
	var key := Vector3i(mapping.face, floori(mapping.uv.x * 8), floori(mapping.uv.y * 8))
	if int(page.density.get(key, 0)) >= 6: return
	var image: Image = PIXELS.source(sources.sources[request.kind][request.frame], request.opacity, request.turns, request.kind == "bullet" and request.frame >= 5)
	var extent: Vector2 = mapping.extent
	var scale_axes: Vector2 = mapping.scale_axes
	var size := Vector2.ONE * float(request.size) / (extent * scale_axes).max(Vector2.ONE * 0.001) * (FACE - 1)
	image.resize(clampi(roundi(size.x), 2, FACE), clampi(roundi(size.y), 2, FACE), Image.INTERPOLATE_BILINEAR)
	var offset := Vector2i(Vector2(mapping.uv) * (FACE - 1) - Vector2(image.get_size()) * Vector2(request.center))
	var region := Rect2i(Vector2i.ZERO, image.get_size()).intersection(Rect2i(-offset, Vector2i.ONE * FACE))
	var layer: Dictionary = page.layers[1 if "scuff" in str(request.kind) else 0]
	var origin := Vector2i(int(mapping.face) % 3, floori(mapping.face / 3.0)) * FACE
	(layer.image as Image).blend_rect(image, region, origin + offset + region.position)
	page.density[key] = int(page.density.get(key, 0)) + 1
	page.dirty = true
	pages.erase(id)
	pages[id] = page

static func face_mapping(bounds: AABB, point: Vector3, normal: Vector3, glass: bool, basis: Basis = Basis.IDENTITY) -> Dictionary:
	var axis := normal.abs().max_axis_index()
	var pair: Vector2i = [Vector2i(2, 1), Vector2i(0, 2), Vector2i(0, 1)][axis]
	var size := Vector2(bounds.size[pair.x], bounds.size[pair.y]).max(Vector2.ONE * 0.0001)
	var uv := Vector2(point[pair.x] - bounds.position[pair.x], point[pair.y] - bounds.position[pair.y]) / size
	var face := axis * 2 + (0 if glass or normal[axis] >= 0 else 1)
	return {"face": face, "uv": Vector2(uv.x, 1.0 - uv.y).clamp(Vector2.ZERO, Vector2.ONE), "extent": size,
		"scale_axes": Vector2(basis[pair.x].length(), basis[pair.y].length())}

func _page(anchor: MeshInstance3D, glass: bool) -> Dictionary:
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.render_priority = 3
	material.set_shader_parameter("bounds_origin", anchor.get_aabb().position)
	material.set_shader_parameter("bounds_size", anchor.get_aabb().size)
	material.set_shader_parameter("glass", glass)
	anchor.material_overlay = material
	var layers: Array[Dictionary] = []
	var saved: Dictionary = _archive.get(anchor.get_instance_id(), {})
	_archive.erase(anchor.get_instance_id())
	for index in 2:
		if not saved.is_empty():
			layers.append({"image": _resized(saved.layers[index], 0.5), "texture": null})
			continue
		var image := Image.create(FACE * 3, FACE * 2, false, Image.FORMAT_RGBA8)
		image.fill(Color.TRANSPARENT)
		layers.append({"image": image, "texture": null})
	var callback := func() -> void:
		if not anchor.is_visible_in_tree(): _release(anchor.get_instance_id())
	anchor.visibility_changed.connect(callback)
	return {"anchor": weakref(anchor), "material": material, "layers": layers, "dirty": true, "density": saved.get("density", {}), "callback": callback}

func _release(id: int) -> void:
	if not pages.has(id): return
	var page: Dictionary = pages[id]
	var anchor := page.anchor.get_ref() as MeshInstance3D
	if is_instance_valid(anchor):
		if anchor.material_overlay == page.material: anchor.material_overlay = null
		if anchor.visibility_changed.is_connected(page.callback): anchor.visibility_changed.disconnect(page.callback)
	for key: int in _archive.keys():
		if not is_instance_valid(_archive[key].anchor.get_ref()): _archive.erase(key)
	if is_instance_valid(anchor):
		_archive[id] = {"anchor": page.anchor, "layers": [_resized(page.layers[0].image, 2), _resized(page.layers[1].image, 2)], "density": page.density}
		while _archive.size() > MAX_ARCHIVE: _archive.erase(_archive.keys()[0])
	pages.erase(id)

# factor 2 halves, 0.5 doubles.
func _resized(source: Image, factor: float) -> Image:
	var copy := source.duplicate() as Image
	copy.resize(roundi(copy.get_width() / factor), roundi(copy.get_height() / factor), Image.INTERPOLATE_BILINEAR)
	return copy

func clear() -> void:
	for id: int in pages.keys(): _release(id)
	_archive.clear()
	queue.clear()

func _dirty() -> bool:
	for page: Dictionary in pages.values():
		if page.dirty: return true
	return false
