extends Node3D

# Artwork faces right (+X). Keep its original aspect, plus a small solid core.
const TEXTURES := {
	"PISTOL": "res://models/objects/textures/ammo/ammo_pistols.png",
	"UZI": "res://models/objects/textures/ammo/ammo_pistols.png",
	"RIFLE": "res://models/objects/textures/ammo/ammo_automate.png",
	"AK": "res://models/objects/textures/ammo/ammo_automate.png",
	"M4": "res://models/objects/textures/ammo/ammo_automate.png",
	"SNIPER RIFLE": "res://models/objects/textures/ammo/ammo_automate.png",
	"MINIGUN": "res://models/objects/textures/ammo/ammo_automate.png",
	"SHOTGUN": "res://models/objects/textures/ammo/ammo_shutgun.png",
	"GRENADE LAUNCHER": "res://models/objects/textures/ammo/ammo_granade.png"
}
static var _textures: Dictionary = {}
var _direction := Vector3.RIGHT


func configure(weapon: String, direction: Vector3) -> void:
	_direction = direction.normalized()
	var meshes: Array = _meshes_for(weapon)
	if meshes[0] != null:
		var face := MeshInstance3D.new()
		face.mesh = meshes[0]
		add_child(face)
	var core := MeshInstance3D.new()
	core.mesh = meshes[1]
	core.scale.x = 1.5
	core.position.x = float(meshes[2]) * 0.12
	add_child(core)
	_align()


# One face quad, one core sphere and their materials per weapon, shared by
# every bullet in flight instead of being built for each shot.
static var _meshes: Dictionary = {}


static func _meshes_for(weapon: String) -> Array:
	if _meshes.has(weapon):
		return _meshes[weapon]
	var path: String = TEXTURES.get(weapon, TEXTURES["PISTOL"])
	var texture := _texture(path)
	var length := 0.13 if weapon == "SHOTGUN" else (0.44 if weapon == "GRENADE LAUNCHER" else 0.32)
	var quad: QuadMesh = null
	if texture != null:
		quad = QuadMesh.new()
		var aspect := float(texture.get_width()) / maxf(1.0, float(texture.get_height()))
		quad.size = Vector2(length, length / aspect)
		var material := StandardMaterial3D.new()
		material.albedo_texture = texture
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.emission_enabled = true
		material.emission_texture = texture
		material.emission = Color(0.3, 0.24, 0.16)
		material.emission_energy_multiplier = 0.35
		quad.material = material
	var sphere := SphereMesh.new()
	sphere.radius = length * 0.11
	sphere.height = length * 0.22
	sphere.radial_segments = 8
	sphere.rings = 4
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.3, 0.35, 0.18) if weapon == "GRENADE LAUNCHER" else Color(0.78, 0.42, 0.14)
	metal.metallic = 0.65
	metal.roughness = 0.28
	sphere.material = metal
	_meshes[weapon] = [quad, sphere, length]
	return _meshes[weapon]


static func _texture(path: String) -> Texture2D:
	if _textures.has(path):
		return _textures[path] as Texture2D
	var texture: Texture2D
	if ResourceLoader.exists(path):
		texture = load(path) as Texture2D
	if texture == null:
		var image := Image.load_from_file(path)
		if image != null and not image.is_empty():
			texture = ImageTexture.create_from_image(image)
	_textures[path] = texture
	return texture


func set_direction(direction: Vector3) -> void:
	if direction.length_squared() > 0.0001:
		_direction = direction.normalized()


func _process(_delta: float) -> void:
	_align()


func _align() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null or _direction.length_squared() < 0.0001:
		return
	var toward_camera := camera.global_position - global_position
	var up := toward_camera.cross(_direction)
	if up.length_squared() < 0.0001:
		up = camera.global_basis.y - _direction * camera.global_basis.y.dot(_direction)
	if up.length_squared() < 0.0001:
		return
	up = up.normalized()
	global_basis = Basis(_direction, up, _direction.cross(up).normalized())
