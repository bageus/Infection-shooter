extends Node3D
## Dust motes floating in the air of a rectangular zone (4 m base, stretched by the node scale like
## darkness zones). Three stacked layers of one shader; the motes are lit only by the scene lights,
## so they show in the flashlight cone and under lamps. The density is set per zone in the planner.

const SHADER := preload("res://game/presentation/office_floor/public/dust_zone.gdshader")
const BASE_SIZE := 4.0
const HEIGHT := 3.0
## Light, weak and dense dust; the index is saved in the map as `dust`.
const DENSITIES := [0.3, 0.6, 1.0]
const DEFAULT_LEVEL := 1
const LAYERS := [{"at": 0.2, "weight": 0.6}, {"at": 0.5, "weight": 1.0}, {"at": 0.8, "weight": 0.6}]
const FADE_SPEED := 1.5
const DRAW_RANGE := 30.0
const GROUP := &"dust_zones"

## The menu switch; a zone fades out and in instead of popping.
static var enabled := true

var level := DEFAULT_LEVEL
var _fade := 1.0
var _materials: Array[ShaderMaterial] = []
var _layers: Array[MeshInstance3D] = []
var _marker: MeshInstance3D


static func set_enabled(tree: SceneTree, value: bool) -> void:
	enabled = value
	if tree != null:
		tree.call_group(GROUP, "refresh")


func _ready() -> void:
	add_to_group(GROUP)
	set_meta("planning_kind", "dust")
	var mesh := QuadMesh.new()
	mesh.size = Vector2(BASE_SIZE, BASE_SIZE)
	mesh.orientation = PlaneMesh.FACE_Y
	for index in LAYERS.size():
		var material := ShaderMaterial.new()
		material.shader = SHADER
		material.render_priority = 5
		material.set_shader_parameter("layer_weight", float(LAYERS[index].weight))
		material.set_shader_parameter("layer_seed", float(index) * 17.0)
		var layer := MeshInstance3D.new()
		layer.name = "Layer%d" % index
		layer.mesh = mesh
		layer.material_override = material
		layer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		layer.visibility_range_end = DRAW_RANGE
		layer.position.y = HEIGHT * float(LAYERS[index].at)
		add_child(layer)
		_materials.append(material)
		_layers.append(layer)
	_marker = MeshInstance3D.new()
	_marker.name = "Marker"
	_marker.mesh = mesh
	var marker_material := StandardMaterial3D.new()
	marker_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	marker_material.albedo_color = Color(0.7, 0.8, 0.9, 0.18)
	_marker.material_override = marker_material
	_marker.position.y = 0.03
	_marker.visible = bool(Engine.get_meta("planning_active", false))
	add_child(_marker)
	set_density(level)
	_fade = 1.0 if enabled else 0.0
	_apply_fade()
	set_process(false)


func set_density(value: int) -> void:
	level = clampi(value, 0, DENSITIES.size() - 1)
	set_meta("planning_dust", level)
	for material in _materials:
		material.set_shader_parameter("density", float(DENSITIES[level]))


func get_density() -> int:
	return level


## The planner shows the footprint (the dust itself is dark without a light).
func set_planning_visual(value: bool) -> void:
	if _marker != null:
		_marker.visible = value


func refresh() -> void:
	set_process(true)


func _process(delta: float) -> void:
	var target := 1.0 if enabled else 0.0
	_fade = move_toward(_fade, target, FADE_SPEED * delta)
	_apply_fade()
	if _fade == target:
		set_process(false)


func _apply_fade() -> void:
	for material in _materials:
		material.set_shader_parameter("fade", _fade)
	for layer in _layers:
		layer.visible = _fade > 0.0
