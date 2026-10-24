extends Node3D
## Immutable, sparse floor pages. No process callbacks, collision, shadows or lights.
const FORMAT := preload("res://game/presentation/office_floor/biomass_bake_format.gd")
@export var cache: Dictionary = {}
var _images: Dictionary = {}


func _ready() -> void:
	if not FORMAT.valid(cache):
		return
	set_meta("baked_biomass_floor", true)
	for page: Dictionary in cache.get("pages", []):
		var image := FORMAT.image(page)
		if image == null:
			continue
		var cell := Vector2i(int(page.x), int(page.z))
		_images[cell] = image
		var mesh := MeshInstance3D.new()
		mesh.mesh = PlaneMesh.new()
		mesh.mesh.size = Vector2.ONE * FORMAT.METERS
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var upload := image.duplicate()
		upload.generate_mipmaps()
		material.albedo_texture = ImageTexture.create_from_image(upload)
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		mesh.material_override = material
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mesh)
		mesh.position = Vector3((cell.x + 0.5) * FORMAT.METERS, float(cache.y) + 0.002, (cell.y + 0.5) * FORMAT.METERS)


func covers(point: Vector3) -> bool:
	if not is_visible_in_tree() or absf(point.y - (global_position.y + float(cache.get("y", 0.0)))) > 0.3:
		return false
	var local := to_local(point)
	var cell := Vector2i(floori(local.x / FORMAT.METERS), floori(local.z / FORMAT.METERS))
	if not _images.has(cell):
		return false
	var uv := Vector2(local.x, local.z) / FORMAT.METERS - Vector2(cell)
	var pixel := Vector2i(uv * FORMAT.PIXELS).clamp(Vector2i.ZERO, Vector2i.ONE * (FORMAT.PIXELS - 1))
	return (_images[cell] as Image).get_pixelv(pixel).a > 0.5


static func valid(raw: Variant) -> bool:
	return FORMAT.valid(raw)


static func baker() -> RefCounted:
	return preload("res://game/presentation/office_floor/biomass_floor_bake.gd").new()
