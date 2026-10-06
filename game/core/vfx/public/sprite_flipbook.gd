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
var _first := 0
var _last := 0
var _loop_from := -1
var _cycle := false
var _intro := 0.0
var _floor_y := -INF
var _landed := false


## options: billboard (true), additive (0..1), brightness, tint, opacity,
## frame (fixed frame index), lifetime (for a fixed frame), speed (time scale),
## first_frame / last_frame (play a range), loop_from (after the range, swing
## back and forth between this frame and last_frame until stop()),
## cycle (true: repeat the whole sheet in order, last frame blending into the
## first, until stop() — for sheets drawn as a seamless loop),
## pivot (UV point at the origin), axis + atlas_angle (axial billboard),
## fade_out (seconds), velocity, gravity, drag, spin, spin_speed, tumble, grow,
## floor_y (a falling sprite settles flat on this height),
## ground (lie flat on the floor facing away from the camera, stretched in
## depth by the atlas's ground_stretch).
static func spawn(parent: Node, atlas: Dictionary, point: Vector3, size: float, options := {}) -> MeshInstance3D:
	if parent == null or not parent.is_inside_tree() or not ATLASES.available(atlas):
		return null
	var node: MeshInstance3D = load(SELF).new()
	node.call("_setup", atlas, size, options)
	parent.add_child(node, true)
	node.global_position = point
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
	var frames := int(atlas.get("frames", 1))
	_first = clampi(int(options.get("first_frame", 0)), 0, frames - 1)
	_last = clampi(int(options.get("last_frame", frames - 1)), _first, frames - 1)
	_loop_from = int(options.get("loop_from", -1))
	_intro = _span(_first, _last)
	_length = float(options.get("lifetime", 1.0)) if _fixed_frame >= 0 else _intro / time_scale
	if _loop_from >= _first and _loop_from < _last and _fixed_frame < 0:
		_length = INF
	_cycle = bool(options.get("cycle", false)) and _fixed_frame < 0
	if _cycle:
		_first = 0
		_last = frames - 1
		_intro = _span(_first, _last)
		_length = INF
		set_instance_shader_parameter(&"cycle", 1.0)
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
	_floor_y = float(options.get("floor_y", -INF))
	scale = Vector3.ONE * size
	set_instance_shader_parameter(&"frame_count", float(atlas.get("frames", 1)))
	set_instance_shader_parameter(&"tint", options.get("tint", Color.WHITE))
	set_instance_shader_parameter(&"pivot", options.get("pivot", atlas.get("pivot", Vector2(0.5, 0.5))))
	if bool(options.get("ground", false)):
		set_instance_shader_parameter(&"ground", 1.0)
		set_instance_shader_parameter(&"ground_stretch", float(atlas.get("ground_stretch", 1.0)))
	if options.has("axis"):
		set_axis(options["axis"])
		set_instance_shader_parameter(&"atlas_angle", float(options.get("atlas_angle", 0.0)))
	_apply(0.0)



func _process(delta: float) -> void:
	# A hitch (first-use shader compile) must not skip the short flash frames.
	delta = minf(delta, 1.0 / 30.0)
	_time += delta
	if _time >= _length:
		queue_free()
		return
	_velocity.y -= _gravity * delta
	_velocity *= exp(-_drag * delta)
	global_position += _velocity * delta
	if not _landed and global_position.y <= _floor_y:
		_settle()
	if _tumble != Vector3.ZERO:
		rotate_object_local(_tumble.normalized(), _tumble.length() * delta)
	_spin += _spin_speed * delta
	_apply(_time)


# Lands flat on the floor and stays there until it fades.
func _settle() -> void:
	_landed = true
	_velocity = Vector3.ZERO
	_gravity = 0.0
	_tumble = Vector3.ZERO
	_spin_speed = 0.0
	global_basis = Basis(Vector3.UP, randf() * TAU) * Basis(Vector3.RIGHT, -PI * 0.5) * Basis.from_scale(Vector3.ONE * scale.x)
	global_position.y = _floor_y


## Ends a looping (or any) flipbook with a fade over `fade_seconds`.
func stop(fade_seconds: float = 0.3) -> void:
	_length = minf(_length, _time + maxf(fade_seconds, 0.0))
	_fade_out = maxf(fade_seconds, 0.0001)


func set_opacity(value: float) -> void:
	_opacity = value


func set_axis(direction: Vector3) -> void:
	set_instance_shader_parameter(&"axial", 1.0)
	set_instance_shader_parameter(&"axis", direction.normalized() if direction.length_squared() > 0.0001 else Vector3.RIGHT)


func _span(from: int, to: int) -> float:
	var durations: Array = _atlas.get("durations", [])
	var total := 0.0
	for index in range(from, mini(to + 1, durations.size())):
		total += float(durations[index])
	return total


# Fractional frame inside the played range; a loop swings back and forth so
# the crossfade never jumps between distant frames.
func _frame_for(seconds: float) -> float:
	var durations: Array = _atlas.get("durations", [])
	var t := seconds * _time_scale
	if _cycle and _intro > 0.0:
		t = fmod(t, _intro)
	if _cycle or t < _intro or _loop_from < 0:
		var start := 0.0
		for index in range(_first, _last + 1):
			var span := float(durations[index]) if index < durations.size() else 0.1
			if t < start + span:
				var frame := index + clampf((t - start) / maxf(span, 0.0001), 0.0, 0.999)
				return frame if _cycle else minf(frame, float(_last))
			start += span
		return float(_last)
	var swing := float(_last - _loop_from)
	var period := _span(_loop_from, _last) * 2.0
	var phase := fmod(t - _intro, period) / period
	return float(_last) - swing * (1.0 - absf(1.0 - 2.0 * phase))


func _apply(seconds: float) -> void:
	var progress := seconds / _length if is_finite(_length) and _length > 0.0 else 0.0
	var frame := float(_fixed_frame) if _fixed_frame >= 0 else _frame_for(seconds)
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
	# Sheets whose art runs to the cell border fade out there instead of
	# showing the cell's straight edge.
	material.set_shader_parameter(&"edge_softness", float(atlas.get("edge_softness", 0.02)))
	_materials[key] = material
	return material
