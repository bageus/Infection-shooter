extends RefCounted
## Retains derived body geometry, never actor state. Live actors keep their data
## when an entry is evicted. Shared materials/textures are outside this budget.
const MAX_ENTRIES := 16
const MAX_BYTES := 64 * 1024 * 1024
var _entries: Dictionary = {}
var _order: Array[String] = []
var _bytes := 0
var _max_entries := MAX_ENTRIES
var _max_bytes := MAX_BYTES


func _init(entries: int = MAX_ENTRIES, bytes: int = MAX_BYTES) -> void:
	_max_entries = clampi(entries, 1, MAX_ENTRIES)
	_max_bytes = clampi(bytes, 1, MAX_BYTES)


func key(source: ArrayMesh, bindings: Dictionary) -> String:
	var identity := source_identity(source)
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(var_to_bytes(bindings))
	return identity + "|" + hashing.finish().hex_encode()


func source_identity(source: ArrayMesh) -> String:
	var identity := str(source.get_meta("body_part_source", ""))
	if identity.is_empty():
		identity = "asset:" + source.resource_path if not source.resource_path.is_empty() else "runtime:%d" % source.get_instance_id()
	return identity


func get_data(identity: String) -> Dictionary:
	if not _entries.has(identity):
		return {}
	_order.erase(identity)
	_order.append(identity)
	return _entries[identity].data


func put(identity: String, data: Dictionary) -> void:
	var bytes := _geometry_bytes(data)
	if bytes > _max_bytes:
		return
	if _entries.has(identity):
		_bytes -= int(_entries[identity].bytes)
		_entries.erase(identity)
		_order.erase(identity)
	while not _order.is_empty() and (_entries.size() >= _max_entries or _bytes + bytes > _max_bytes):
		var oldest: String = _order.pop_front()
		_bytes -= int(_entries[oldest].bytes)
		_entries.erase(oldest)
	_entries[identity] = {"data": data, "bytes": bytes}
	_order.append(identity)
	_bytes += bytes


func size() -> int:
	return _entries.size()


func stats() -> Dictionary:
	return {"entries": size(), "geometry_bytes": _bytes}


func _geometry_bytes(data: Dictionary) -> int:
	var total := var_to_bytes(data.binds).size()
	for surface: Dictionary in data.surfaces:
		total += surface.vertices.size() * 12 + surface.normals.size() * 12 + surface.uvs.size() * 8
		total += surface.bones.size() * 4 + surface.weights.size() * 4 + surface.indices.size() * 4
	var mesh: ArrayMesh = data.mesh
	for index in mesh.get_surface_count():
		var stored := RenderingServer.mesh_get_surface(mesh.get_rid(), index)
		for field in ["vertex_data", "array_data", "attribute_data", "skin_data", "index_data"]:
			total += (stored.get(field, PackedByteArray()) as PackedByteArray).size()
		for lod: Dictionary in stored.get("lods", []):
			total += (lod.index_data as PackedByteArray).size()
	return total
