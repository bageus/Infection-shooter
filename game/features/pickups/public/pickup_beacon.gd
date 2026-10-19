extends Node3D
## Pickup marker: a soft additive glow plus, optionally, a blinking arrow that
## bobs above the item (1-2 m). Meshes are unshaded and cast no shadows.

const GLOW_TEXTURE_SIZE := 64
const ARROW_BLINK_PERIOD := 0.8
const ARROW_MIN_ALPHA := 0.55
static var _glow_texture: GradientTexture2D

var _arrow: Node3D
var _arrow_material: StandardMaterial3D
var _glow_material: StandardMaterial3D
var _arrow_base := 1.3
var _glow_energy := 1.0
var _time := 0.0


## `glow_radius` is the glow half-size in metres; `arrow_height` <= 0 omits the arrow.
static func make(color: Color, glow_radius: float, arrow_height: float, glow_energy := 1.0) -> Node3D:
	var beacon := (load("res://game/features/pickups/public/pickup_beacon.gd") as GDScript).new() as Node3D
	beacon.call("_build", color, glow_radius, arrow_height, glow_energy)
	return beacon


func _build(color: Color, glow_radius: float, arrow_height: float, glow_energy: float) -> void:
	name = "PickupBeacon"
	_glow_energy = glow_energy
	_glow_material = StandardMaterial3D.new()
	_glow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glow_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_glow_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_glow_material.albedo_texture = _glow_gradient()
	_glow_material.albedo_color = Color(color, 0.55 * glow_energy)
	_glow_material.disable_receive_shadows = true
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * glow_radius * 2.0
	quad.material = _glow_material
	_add(quad).position.y = glow_radius * 0.3
	if arrow_height > 0.0:
		_arrow_base = arrow_height
		_arrow = Node3D.new()
		_arrow.position.y = arrow_height
		add_child(_arrow)
		_arrow_material = StandardMaterial3D.new()
		_arrow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_arrow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_arrow_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_arrow_material.albedo_color = color
		var head := CylinderMesh.new()
		head.top_radius = 0.0
		head.bottom_radius = 0.24
		head.height = 0.36
		head.radial_segments = 12
		head.rings = 1
		head.material = _arrow_material
		var head_node := _add(head, _arrow)
		head_node.rotation.x = PI
		head_node.position.y = 0.0
		var shaft := CylinderMesh.new()
		shaft.top_radius = 0.08
		shaft.bottom_radius = 0.08
		shaft.height = 0.3
		shaft.radial_segments = 12
		shaft.rings = 1
		shaft.material = _arrow_material
		_add(shaft, _arrow).position.y = 0.33


func _ready() -> void:
	# Bobbing and pulsing only matter while the beacon can be seen. Headless runs
	# have no screen, so they keep animating.
	if DisplayServer.get_name() == "headless":
		return
	var notifier := VisibleOnScreenNotifier3D.new()
	notifier.aabb = AABB(Vector3(-1.5, -0.5, -1.5), Vector3(3.0, 3.5, 3.0))
	add_child(notifier)
	notifier.screen_entered.connect(set_process.bind(true))
	notifier.screen_exited.connect(set_process.bind(false))


func _add(mesh: Mesh, parent: Node3D = self) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.set_meta("planning_bounds_excluded", true)
	parent.add_child(node)
	return node


func _process(delta: float) -> void:
	_time += delta
	var pulse := 0.8 + 0.2 * sin(_time * 2.2)
	_glow_material.albedo_color.a = 0.55 * _glow_energy * pulse
	if _arrow != null:
		_arrow.position.y = _arrow_base + sin(_time * 3.4) * 0.14
		# Smooth blink: eases between full and a visible floor, so the arrow never vanishes.
		_arrow_material.albedo_color.a = lerpf(ARROW_MIN_ALPHA, 1.0, 0.5 + 0.5 * sin(_time * TAU / ARROW_BLINK_PERIOD))


## Shows or hides the blinking arrow; a beacon built without one ignores the call.
func set_arrow_visible(shown: bool) -> void:
	if _arrow != null:
		_arrow.visible = shown


static func _glow_gradient() -> GradientTexture2D:
	if _glow_texture == null:
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
		gradient.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.35), Color(1, 1, 1, 0)])
		_glow_texture = GradientTexture2D.new()
		_glow_texture.gradient = gradient
		_glow_texture.fill = GradientTexture2D.FILL_RADIAL
		_glow_texture.fill_from = Vector2(0.5, 0.5)
		_glow_texture.fill_to = Vector2(1.0, 0.5)
		_glow_texture.width = GLOW_TEXTURE_SIZE
		_glow_texture.height = GLOW_TEXTURE_SIZE
	return _glow_texture
