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
const SWITCH_SOUND := preload("res://assets/audio/sfx/flashlight/switch_on_flashlight.ogg")
const GLOW_SIZE := 0.45
## Lens glare peak alpha: the bright spot at the lens was too strong at full.
const GLOW_STRENGTH := 0.5
var _model: Node3D
var _light: SpotLight3D
var _glow: MeshInstance3D
var _on := false
var _switch: AudioStreamPlayer


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
	_glow = _make_glow()
	_light.add_child(_glow)
	# Same sound for on and off: one switch click.
	_switch = AudioStreamPlayer.new()
	_switch.stream = SWITCH_SOUND
	add_child(_switch)


## Lens glare: a soft additive billboard just in front of the lens, seen when the beam faces the camera.
func _make_glow() -> MeshInstance3D:
	var halo := GradientTexture2D.new()
	halo.fill = GradientTexture2D.FILL_RADIAL
	halo.fill_from = Vector2(0.5, 0.5)
	halo.fill_to = Vector2(0.5, 0.0)
	halo.gradient = Gradient.new()
	halo.gradient.set_color(0, Color(1, 1, 1, 1))
	halo.gradient.set_color(1, Color(1, 1, 1, 0))
	halo.gradient.add_point(0.15, Color(1, 1, 1, 0.9))
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.albedo_texture = halo
	material.albedo_color = Color(_light.light_color, 0.0)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * GLOW_SIZE
	var glow := MeshInstance3D.new()
	glow.name = "LensGlow"
	glow.mesh = quad
	glow.material_override = material
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glow.position = Vector3(0, 0, -0.03)
	return glow


## Glare strength: full when the beam points at the camera, none from the side or behind.
func _update_glow() -> void:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	var facing := 0.0
	if camera != null and _light.visible:
		# Compared on the ground plane: the camera looks down from 45°, so "towards the camera" means the beam points down-screen.
		var to_camera := (camera.global_position - _glow.global_position) * Vector3(1, 0, 1)
		var beam := -_light.global_basis.z * Vector3(1, 0, 1)
		facing = smoothstep(0.3, 0.9, beam.normalized().dot(to_camera.normalized()))
	_glow.visible = facing > 0.0
	(_glow.material_override as StandardMaterial3D).albedo_color.a = facing * _light.light_energy / ENERGY * GLOW_STRENGTH


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
		_switch.play()
	_light.light_energy = move_toward(_light.light_energy, ENERGY if _on else 0.0, delta * 4.0)
	# A gun the clip has put away is scaled to nothing, and its flashlight with it.
	_light.visible = _model.is_inside_tree() and _model.visible and absf(_model.global_basis.determinant()) > 0.001
	_update_glow()
