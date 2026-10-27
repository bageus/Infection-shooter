extends RefCounted
## Derived skin presentation for one geometry/material combination. A page shares
## one material per surface; actor/piece leases own distinct texture-array layers.
## 128 layers is below WebGL2's minimum MAX_ARRAY_TEXTURE_LAYERS (256).
const BLOOD_LEVEL := preload("res://game/core/vfx/public/blood_level.gd")
const BAKE := preload("res://game/features/infected/body_blood_bake.gd")
const SHADER := preload("res://game/features/infected/body_wound.gdshader")
const PAGE_LAYERS := 128
const INSTANCE_SELECTOR := "instance uniform float blood_layer : instance_index(1) = -1.0;"
const MATERIAL_SELECTOR := "uniform float blood_layer = -1.0;"
## Every body owns a one-layer page, so blood_layer is a plain material parameter.
## An instance uniform reserves 16 of the renderer's 4096 uniform slots per mesh,
## so at most 256 meshes could use one at a time (and it is broken on WebGL2,
## godotengine/godot#112674). The shared 128-layer pages below are kept for tests
## and pass per_body = false to use the instance-uniform shader.
static var _material_shader: Shader
var _originals: Array
var _per_body: bool
var _pages: Array[Page] = []
var _blank: Texture2DArray

class Page extends RefCounted:
	var materials: Array = []
	var textures: Array[Texture2DArray] = []
	var available: Array[int] = []
	var active := 0
	var blank: Texture2DArray

	var layer_count := PAGE_LAYERS

	func _init(skins: Array, empty: Texture2DArray, layers := PAGE_LAYERS) -> void:
		materials = skins
		blank = empty
		layer_count = layers
		for material: ShaderMaterial in materials:
			material.set_shader_parameter("blood_masks", blank)
		for i in range(layer_count - 1, -1, -1):
			available.append(i)

	func upload(images: Array, layer: int) -> void:
		if textures.is_empty():
			var mask := BAKE.create_mask()
			var layers: Array[Image] = []
			for i in layer_count:
				layers.append(mask)
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

	var per_body := false

	## Materials a mesh surface must use: shared per page natively, private per body on Web.
	var materials: Array:
		get:
			return page.materials

	func bind(instance: MeshInstance3D, bloody := false) -> void:
		instance.set_meta("body_skin_lease", self)
		var wound := float(layer) if bloody else -1.0
		if per_body:
			for material: ShaderMaterial in page.materials:
				material.set_shader_parameter(&"blood_layer", wound)
		else:
			instance.set_instance_shader_parameter(&"blood_layer", wound)

	## Current wound selector (-1 = clean) for this lease's body, whichever path stores it.
	func selector(instance: MeshInstance3D) -> float:
		if per_body:
			return float(page.materials[0].get_shader_parameter(&"blood_layer"))
		return float(instance.get_instance_shader_parameter(&"blood_layer"))

	func upload(images: Array) -> void:
		page.upload(images, layer)

func _init(originals: Array, per_body := true) -> void:
	_originals = originals.duplicate()
	_per_body = per_body
	# Supply a valid sampler even for clean bodies (required by Forward+).
	_blank = Texture2DArray.new()
	var empty: Array[Image] = [Image.create(1, 1, false, Image.FORMAT_RG8)]
	_blank.create_from_images(empty)

func acquire() -> Lease:
	if _per_body:
		var own: Array = []
		for original: Material in _originals:
			own.append(create_material(original, material_shader()))
		var solo := Page.new(own, _blank, 1)
		solo.active = 1
		var lease := Lease.new(solo, solo.available.pop_back())
		lease.per_body = true
		return lease
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

## Same source as body_wound.gdshader with blood_layer as a plain uniform.
static func material_shader() -> Shader:
	if _material_shader == null:
		assert(SHADER.code.contains(INSTANCE_SELECTOR), "blood_layer declaration changed")
		_material_shader = Shader.new()
		_material_shader.code = SHADER.code.replace(INSTANCE_SELECTOR, MATERIAL_SELECTOR)
	return _material_shader

static func create_material(original: Material, shader: Shader = SHADER) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = shader
	if BLOOD_LEVEL.is_green():
		material.set_shader_parameter("blood_color", BLOOD_LEVEL.GREEN_COLOR)
		material.set_shader_parameter("wound_core_color", BLOOD_LEVEL.GREEN_WOUND_CORE)
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
