extends MeshInstance3D
## Plays a frame of a sprite-sheet atlas (left to right, top to bottom) on a
## quad in 3D. Frames follow the atlas's own timing (fast flash, slow smoke)
## and crossfade into the next frame. A fixed `frame` turns it into a single
## tumbling sprite (torn paper). The node frees itself when it is done.

const SHADER := preload("res://game/core/vfx/public/flipbook.gdshader")
const ATLASES := preload("res://game/core/vfx/public/effect_atlases.gd")
const SELF := "res://game/core/vfx/public/sprite_flipbook.gd"

static var _materials := {}

var _atlas: Dictionary
var _time := 0.0
var _length := 0.0
var _fixed_frame := -1
var _fade_out := 0.0
var _opacity := 1.0
var _velocity := Vector3.ZERO
var _gravity := 0.0
var _drag := 0.0
var _spin := 0.0
var _spin_speed := 0.0
var _tumble := Vector3.ZERO
var _size := 1.0
var _grow := 1.0
var _time_scale := 1.0


## options: billboard (true), additive (0..1), brightness, tint, opacity,
## frame (fixed frame index), lifetime (for a fixed frame), speed (time scale),
## fade_out (seconds), velocity, gravity, drag, spin, spin_speed, tumble, grow.
static func spawn(parent: Node, atlas: Dictionary, position: Vector3, size: float, options := {}) -> MeshInstance3D:
	if parent == null or not parent.is_inside_tree() or not ATLASES.available(atlas):
		return null
	var node: MeshInstance3D = load(SELF).new()
	node.call("_setup", atlas, size, options)
	parent.add_child(node)
	node.global_position = position
	return node


## Fractional frame for a play time, or -1 once the sheet has finished.
static func frame_at(atlas: Dictionary, seconds: float) -> float:
	var durations: Array = atlas.get("durations", [])
	var start := 0.0
	for index in durations.size():
		var span := float(durations[index])
		if seconds < start + span:
			return index + clampf((seconds - start) / maxf(span, 0.0001), 0.0, 0.999)
		start += span
	return -1.0


static func length_of(atlas: Dictionary) -> float:
	var total := 0.0
	for span in atlas.get("durations", []):
		total += float(span)
	return total


func _setup(atlas: Dictionary, size: float, options: Dictionary) -> void:
	name = "Flipbook"
	_atlas = atlas
	_size = size
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	mesh = quad
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	material_override = _material(atlas, bool(options.get("billboard", true)), float(options.get("additive", 0.0)), float(options.get("brightness", 1.0)))
	_fixed_frame = int(options.get("frame", -1))
	var time_scale := maxf(float(options.get("speed", 1.0)), 0.01)
	_length = float(options.get("lifetime", 1.0)) if _fixed_frame >= 0 else length_of(atlas) / time_scale
	_time_scale = time_scale
	_fade_out = float(options.get("fade_out", 0.0))
	_opacity = float(options.get("opacity", 1.0))
	_velocity = options.get("velocity", Vector3.ZERO)
	_gravity = float(options.get("gravity", 0.0))
	_drag = float(options.get("drag", 0.0))
	_spin = float(options.get("spin", 0.0))
	_spin_speed = float(options.get("spin_speed", 0.0))
	_tumble = options.get("tumble", Vector3.ZERO)
	_grow = float(options.get("grow", 1.0))
	scale = Vector3.ONE * size
	set_instance_shader_parameter(&"frame_count", float(atlas.get("frames", 1)))
	set_instance_shader_parameter(&"tint", options.get("tint", Color.WHITE))
	_apply(0.0)



func _process(delta: float) -> void:
	_time += delta
	if _time >= _length:
		queue_free()
		return
	_velocity.y -= _gravity * delta
	_velocity *= exp(-_drag * delta)
	global_position += _velocity * delta
	if _tumble != Vector3.ZERO:
		rotate_object_local(_tumble.normalized(), _tumble.length() * delta)
	_spin += _spin_speed * delta
	_apply(_time)


func _apply(seconds: float) -> void:
	var progress := seconds / maxf(_length, 0.0001)
	var frame := float(_fixed_frame) if _fixed_frame >= 0 else maxf(frame_at(_atlas, seconds * _time_scale), 0.0)
	var alpha := _opacity
	if _fade_out > 0.0:
		alpha *= clampf((_length - seconds) / _fade_out, 0.0, 1.0)
	set_instance_shader_parameter(&"frame_position", frame)
	set_instance_shader_parameter(&"opacity", alpha)
	set_instance_shader_parameter(&"spin", _spin)
	if _grow != 1.0:
		scale = Vector3.ONE * _size * lerpf(1.0, _grow, 1.0 - pow(1.0 - progress, 2.0))


# One material per atlas and blend mode; per-sprite state lives in instance uniforms.
static func _material(atlas: Dictionary, billboard: bool, additive: float, brightness: float) -> ShaderMaterial:
	var key := "%s|%s|%.2f|%.2f" % [atlas.get("path", ""), billboard, additive, brightness]
	if _materials.has(key):
		return _materials[key]
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter(&"atlas", load(str(atlas["path"])))
	material.set_shader_parameter(&"grid", Vector2(float(atlas.get("columns", 1)), float(atlas.get("rows", 1))))
	material.set_shader_parameter(&"billboard", billboard)
	material.set_shader_parameter(&"additive", additive)
	material.set_shader_parameter(&"brightness", brightness)
	_materials[key] = material
	return material
