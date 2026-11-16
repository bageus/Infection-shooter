extends Node
## Weapon flashlight: clipped under the barrel of the gun the model holds, so it moves with the baked clips (the roll too);
## the flashlight action (T) switches the beam.
const MODEL := preload("res://models/objects/weapons/weapon_flashlight_lowpoly.glb")
## Under the barrel, just behind the muzzle, in the model muzzle's frame (barrel along +X), at 1.6 times the model's size.
const OFFSET := Vector3(-0.1, -0.05, 0.0)
const MODEL_SCALE := 1.6
## The flashlight model points along -Z, the model's barrel along +X.
const BARREL_TURN := Basis(Vector3.UP, -PI * 0.5)
const ENERGY := 6.0
## The beam leans down a little so the floor ahead of the hero is lit, not only far walls.
const PITCH_DOWN := 10.0
var _model: Node3D
var _light: SpotLight3D
var _on := false


func _ready() -> void:
	_model = MODEL.instantiate() as Node3D
	# This node is no Node3D: until a gun carries it the model would sit at the world origin.
	_model.visible = false
	add_child(_model)
	# The beam leaves the model's LightSocket (the lens), pointing where the barrel points.
	_light = SpotLight3D.new()
	_light.name = "Flashlight"
	_light.light_color = Color(1.0, .96, .88)
	_light.light_energy = 0.0
	_light.spot_range = 9.0
	_light.spot_angle = 28.0
	_light.spot_attenuation = 0.8
	_light.shadow_enabled = false
	_light.rotation_degrees.x = -PITCH_DOWN
	_model.find_child("LightSocket", true, false).add_child(_light)


## Clips the flashlight under the model's muzzle of the weapon now held.
func attach(muzzle: Node3D) -> void:
	if muzzle == null or _model.get_parent() == muzzle:
		return
	_model.reparent(muzzle, false)
	_model.transform = Transform3D(BARREL_TURN * Basis.from_scale(Vector3.ONE * MODEL_SCALE), OFFSET)
	_model.visible = true


func _process(delta: float) -> void:
	if Input.is_action_just_pressed("flashlight"):
		_on = not _on
	_light.light_energy = move_toward(_light.light_energy, ENERGY if _on else 0.0, delta * 4.0)
	# A gun the clip has put away is scaled to nothing, and its flashlight with it.
	_light.visible = _model.is_inside_tree() and _model.visible and absf(_model.global_basis.determinant()) > 0.001
