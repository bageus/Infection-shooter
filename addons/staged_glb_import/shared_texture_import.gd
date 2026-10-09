@tool
extends RefCounted
## Import-time cache only: identical embedded maps become one external resource.
## Derived assets are regenerated from GLBs; their visible resource paths also
## let the exporter include the shared maps as ordinary scene dependencies.
const CACHE := "res://assets/runtime_shared_maps/"
const MAX_DIMENSION := 1024


static func process(root: Node) -> Error:
	var replacements: Dictionary = {}
	return _visit(root, replacements)


static func _visit(node: Node, replacements: Dictionary) -> Error:
	if node is MeshInstance3D and node.mesh != null:
		for surface in node.mesh.get_surface_count():
			var material := node.get_active_material(surface) as BaseMaterial3D
			if material == null:
				continue
			for slot in BaseMaterial3D.TEXTURE_MAX:
				var texture := material.get_texture(slot)
				# External imported textures already have their own import policy.
				if not texture is ImageTexture:
					continue
				var normal := slot == BaseMaterial3D.TEXTURE_NORMAL
				var key := "%d|%d" % [texture.get_instance_id(), int(normal)]
				if not replacements.has(key):
					var replacement := _shared(texture, normal)
					if replacement == null:
						return ERR_CANT_CREATE
					replacements[key] = replacement
				material.set_texture(slot, replacements[key])
	for child: Node in node.get_children():
		var error := _visit(child, replacements)
		if error != OK:
			return error
	return OK


static func _shared(texture: Texture2D, normal: bool) -> Texture2D:
	var image := texture.get_image()
	if image == null or image.is_empty():
		return null
	if maxi(image.get_width(), image.get_height()) < 512:
		return texture
	if image.is_compressed() and maxi(image.get_width(), image.get_height()) <= MAX_DIMENSION:
		return texture
	image = image.duplicate() as Image
	if image.is_compressed() and image.decompress() != OK:
		return null
	var longest := maxi(image.get_width(), image.get_height())
	if longest > MAX_DIMENSION:
		image.clear_mipmaps()
		var factor := float(MAX_DIMENSION) / longest
		image.resize(maxi(1, roundi(image.get_width() * factor)),
			maxi(1, roundi(image.get_height() * factor)), Image.INTERPOLATE_LANCZOS)
	# Include layout and semantic usage: equal bytes alone are insufficient.
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(image.get_data())
	var path := CACHE + "%dx%d_%d_%d_%d_%s.res" % [image.get_width(), image.get_height(),
		image.get_format(), int(image.has_mipmaps()), int(normal), hashing.finish().hex_encode()]
	if FileAccess.file_exists(path):
		return _load_registered(path)
	if not image.has_mipmaps():
		image.generate_mipmaps(normal)
	var source := Image.COMPRESS_SOURCE_NORMAL if normal else Image.COMPRESS_SOURCE_GENERIC
	if image.compress(Image.COMPRESS_S3TC, source) != OK:
		push_error("Could not compress embedded texture: " + path)
		return null
	var result := ImageTexture.create_from_image(image)
	if DirAccess.make_dir_recursive_absolute(CACHE) != OK:
		return null
	if ResourceSaver.save(result, path) != OK:
		push_error("Could not save shared embedded texture: " + path)
		return null
	return _load_registered(path)


static func _load_registered(path: String) -> Texture2D:
	# Generated .res files appear during import, before the filesystem rescan.
	# Register their stored UID now so packed scenes never record unknown IDs.
	var uid := ResourceLoader.get_resource_uid(path)
	if uid != ResourceUID.INVALID_ID:
		if ResourceUID.has_id(uid):
			ResourceUID.set_id(uid, path)
		else:
			ResourceUID.add_id(uid, path)
	return ResourceLoader.load(path) as Texture2D
