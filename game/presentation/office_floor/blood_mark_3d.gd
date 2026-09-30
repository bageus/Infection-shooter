extends Node3D

var surface_ref: WeakRef
var _anchor: RemoteTransform3D
var _decal: Decal
var _quad: QuadMesh
var _material: StandardMaterial3D
var _growth: Tween
var _fade: Tween
var _depth := 0.08


func _init() -> void:
	set_meta("blood_effect", true)


func configure(hit: Dictionary, definition: Dictionary, settings: Dictionary) -> void:
	set_meta("blood_effect", true)
	_depth = settings["depth"]
	var body: Node3D = hit["collider"]
	surface_ref = weakref(body)
	global_position = hit["position"]
	global_basis = definition["basis"]
	var footprint: Vector2 = definition["footprint"]
	if settings["decal"]:
		_decal = Decal.new()
		_decal.texture_albedo = definition["texture"]
		_decal.texture_emission = null
		_decal.modulate = definition["tint"]
		_decal.upper_fade = 0.0
		_decal.lower_fade = 0.0
		_decal.normal_fade = 0.8
		_decal.cull_mask = settings["visual_mask"]
		_decal.distance_fade_enabled = settings["distance_fade"]
		_decal.distance_fade_begin = settings["fade_begin"]
		_decal.distance_fade_length = settings["fade_length"]
		add_child(_decal)
	else:
		var visual := MeshInstance3D.new()
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		visual.layers = 1
		_material = StandardMaterial3D.new()
		_material.albedo_texture = definition["texture"]
		_material.albedo_color = definition["tint"]
		_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_material.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
		_material.emission_enabled = false
		_material.roughness = 0.95
		if settings["distance_fade"]:
			_material.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
			_material.distance_fade_min_distance = settings["fade_begin"]
			_material.distance_fade_max_distance = settings["fade_begin"] + settings["fade_length"]
		_quad = QuadMesh.new()
		_quad.material = _material
		visual.mesh = _quad
		visual.rotation.x = -PI * 0.5
		visual.position.y = settings["quad_offset"]
		add_child(visual)
	_set_dimensions(footprint)
	if definition.get("pool", false):
		_set_dimensions(footprint * 0.35)
		_growth = create_tween()
		_growth.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_growth.tween_method(_set_dimensions, footprint * 0.35, footprint, definition.get("growth_seconds", settings["growth_seconds"]))
	_anchor = RemoteTransform3D.new()
	_anchor.set_meta("blood_effect", true)
	_anchor.update_scale = false
	body.add_child(_anchor)
	_anchor.global_transform = global_transform
	_anchor.remote_path = _anchor.get_path_to(self)


func _set_dimensions(footprint: Vector2) -> void:
	if _decal != null:
		_decal.size = Vector3(footprint.x, _depth, footprint.y)
	if _quad != null:
		_quad.size = footprint


func _set_opacity(value: float) -> void:
	if _decal != null:
		var tint := _decal.modulate
		tint.a = value
		_decal.modulate = tint
	if _material != null:
		var tint := _material.albedo_color
		tint.a = value
		_material.albedo_color = tint


func fade_out(seconds: float, completed: Callable) -> void:
	if _growth != null and _growth.is_valid():
		_growth.kill()
	_fade = create_tween()
	var alpha := _decal.modulate.a if _decal != null else _material.albedo_color.a
	_fade.tween_method(_set_opacity, alpha, 0.0, maxf(seconds, 0.01))
	_fade.tween_callback(completed)


func _exit_tree() -> void:
	if is_instance_valid(_anchor):
		_anchor.remote_path = NodePath()
		_anchor.queue_free()
