extends Node3D

const FRAMES := 6
const GUN_FOG := preload("res://models/objects/textures/gun_fog/gun_fog.png")
const SHOTGUN_ATLAS := preload("res://models/objects/textures/gun_fog/shotgun_muzzle.png")
const RIFLE_ATLASES: Array[Texture2D] = [
	preload("res://models/objects/textures/gun_fog/frame_muzzle_1.png"),
	preload("res://models/objects/textures/gun_fog/frame_muzzle_2.png"),
	preload("res://models/objects/textures/gun_fog/frame_muzzle_3.png"),
	preload("res://models/objects/textures/gun_fog/frame_muzzle_4.png"),
]

@export_range(0.06, 0.4, 0.01) var duration := 0.19
@export_range(0.1, 1.4, 0.01) var width := 0.425
@export_range(0.1, 1.0, 0.01) var height := 0.26
@export_range(0.0, 1.0, 0.01) var tip_position := 0.20
var barrel_axis := Vector3.FORWARD
## Set before add_child; the scene's default atlas is the gun_fog smoke.
var atlas: Texture2D = GUN_FOG

@onready var _visual: MeshInstance3D = $Visual

var _elapsed := 0.0
var _material: ShaderMaterial


func _ready() -> void:
	_material = (_visual.mesh.surface_get_material(0) as ShaderMaterial).duplicate() as ShaderMaterial
	_visual.material_override = _material
	_visual.scale = Vector3(width, height, 1.0)
	_material.set_shader_parameter("atlas", atlas)
	_material.set_shader_parameter("frame_index", 0)
	_update_visual_anchor()
	set_process(true)


## Shotgun has its own flash, rifles, sniper and minigun alternate per shot, others keep gun_fog.
static func atlas_for(weapon: String) -> Texture2D:
	if weapon == "SHOTGUN":
		return SHOTGUN_ATLAS
	if weapon in ["AK", "M4", "SNIPER RIFLE", "MINIGUN"]:
		return RIFLE_ATLASES[randi() % RIFLE_ATLASES.size()]
	return GUN_FOG


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= duration:
		queue_free()
		return
	_material.set_shader_parameter("frame_index", mini(int(_elapsed / duration * FRAMES), FRAMES - 1))
	_update_visual_anchor()


func _update_visual_anchor() -> void:
	var nozzle := get_parent() as Node3D
	var camera := get_viewport().get_camera_3d()
	if nozzle == null or camera == null:
		return
	var toward_camera := camera.global_position - nozzle.global_position
	if toward_camera.length_squared() < 0.0001:
		return
	toward_camera = toward_camera.normalized()
	var fire_direction := (nozzle.global_basis * barrel_axis).normalized()
	var right := fire_direction - toward_camera * fire_direction.dot(toward_camera)
	if right.length_squared() < 0.001:
		right = camera.global_basis.x
	right = right.normalized()
	var up := toward_camera.cross(right).normalized()
	_visual.global_basis = Basis(right * width, up * height, toward_camera)
	_visual.global_position = nozzle.global_position + right * width * (0.5 - tip_position)
