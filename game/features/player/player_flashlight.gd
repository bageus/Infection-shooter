extends Node
## Weapon flashlight: a dim spot beside the muzzle, moved onto whichever weapon is held; the flashlight action (T) switches the beam.
const MODEL := preload("res://models/objects/weapons/weapon_flashlight_lowpoly.glb")
## Flashlight sits this far (m) to the side of the muzzle, at twice the model's size, and is dim enough to read the room, not light it.
const SIDE := .09
const MODEL_SCALE := 2.0
const ENERGY := .6
var mount: Node
var _model: Node3D
var _light: SpotLight3D
var _on := false


func _ready() -> void:
	_model = MODEL.instantiate() as Node3D
	_model.position = Vector3(SIDE, 0, 0)
	_model.scale = Vector3.ONE * MODEL_SCALE
	add_child(_model)
	# The beam leaves the model's LightSocket (the lens), pointing where the muzzle points.
	_light = SpotLight3D.new()
	_light.name = "Flashlight"
	_light.light_color = Color(1.0, .96, .88)
	_light.light_energy = 0.0
	_light.spot_range = 7.0
	_light.spot_angle = 22.0
	_light.spot_attenuation = 1.6
	_light.shadow_enabled = false
	_model.find_child("LightSocket", true, false).add_child(_light)


func _process(delta: float) -> void:
	var weapon := mount.get("_active") as Node3D
	var muzzle := weapon.get_node_or_null("Muzzle") as Node3D if is_instance_valid(weapon) else null
	if muzzle != null and _model.get_parent() != muzzle:
		_model.reparent(muzzle, false)
	if Input.is_action_just_pressed("flashlight"):
		_on = not _on
	_light.light_energy = move_toward(_light.light_energy, ENERGY if _on else 0.0, delta * 3.0)
