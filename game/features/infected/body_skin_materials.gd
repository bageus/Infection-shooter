extends RefCounted
## Derived skin presentation for one geometry/material combination. A page shares
## one material per surface; actor/piece leases own distinct texture-array layers.
## 128 layers is below WebGL2's minimum MAX_ARRAY_TEXTURE_LAYERS (256).
const BAKE := preload("res://game/features/infected/body_blood_bake.gd")
const SHADER := preload("res://game/features/infected/body_wound.gdshader")
const PAGE_LAYERS := 128
var _originals: Array
var _pages: Array[Page] = []
var _blank: Texture2DArray

class Page extends RefCounted:
	var materials: Array = []
	var textures: Array[Texture2DArray] = []
	var available: Array[int] = []
	var active := 0
	var blank: Texture2DArray

	func _init(skins: Array, empty: Texture2DArray) -> void:
		materials = skins
		blank = empty
		for material: ShaderMaterial in materials:
			material.set_shader_parameter("blood_masks", blank)
		for i in range(PAGE_LAYERS - 1, -1, -1):
			available.append(i)

	func upload(images: Array, layer: int) -> void:
		if textures.is_empty():
			var blank := BAKE.create_mask()
			var layers: Array[Image] = []
			for i in PAGE_LAYERS:
				layers.append(blank)
			for material: ShaderMaterial in materials:
				var texture := Texture2DArray.new()
				texture.create_from_images(layers)
				textures.append(texture)
				material.set_shader_parameter("blood_masks", texture)
		for surface in images.size():
			textures[surface].update_layer(images[surface], layer)

	func release(layer: int) -> void:
		available.append(layer)
		active -= 1
		if active == 0:
			for material: ShaderMaterial in materials:
				material.set_shader_parameter("blood_masks", blank)
			textures.clear()

class Lease extends RefCounted:
	var page: Page
	var layer: int

	func _init(owner: Page, index: int) -> void:
		page = owner
		layer = index

	func _notification(what: int) -> void:
		if what == NOTIFICATION_PREDELETE:
			page.release(layer)

	func bind(instance: MeshInstance3D, bloody := false) -> void:
		instance.set_meta("body_skin_lease", self)
		instance.set_instance_shader_parameter(&"blood_layer", float(layer) if bloody else -1.0)

	func upload(images: Array) -> void:
		page.upload(images, layer)

func _init(originals: Array) -> void:
	_originals = originals.duplicate()
	# Supply a valid sampler even for clean bodies (required by Forward+).
	_blank = Texture2DArray.new()
	var empty: Array[Image] = [Image.create(1, 1, false, Image.FORMAT_RG8)]
	_blank.create_from_images(empty)

func acquire() -> Lease:
	for page in _pages:
		if not page.available.is_empty():
			page.active += 1
			return Lease.new(page, page.available.pop_back())
	var skins: Array = []
	for original: Material in _originals:
		skins.append(create_material(original))
	var page := Page.new(skins, _blank)
	_pages.append(page)
	page.active = 1
	return Lease.new(page, page.available.pop_back())

## Only properties used by the skin shader enter the identity. No actor state.
static func signature(originals: Array) -> Array:
	var values: Array = []
	for original: Material in originals:
		if original is BaseMaterial3D:
			var base := original as BaseMaterial3D
			values.append([base.albedo_color, base.roughness, base.metallic,
				base.albedo_texture, base.normal_enabled, base.normal_texture])
		else:
			values.append(null)
	return values

static func create_material(original: Material) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SHADER
	if original is BaseMaterial3D:
		var base := original as BaseMaterial3D
		material.set_shader_parameter("albedo_color", base.albedo_color)
		material.set_shader_parameter("roughness_value", base.roughness)
		material.set_shader_parameter("metallic_value", base.metallic)
		if base.albedo_texture != null:
			material.set_shader_parameter("albedo_texture", base.albedo_texture)
			material.set_shader_parameter("use_albedo_texture", true)
		if base.normal_enabled and base.normal_texture != null:
			material.set_shader_parameter("normal_texture", base.normal_texture)
			material.set_shader_parameter("use_normal_texture", true)
	return material
