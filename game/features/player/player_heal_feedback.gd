extends Node3D
## Healing presentation on the player: a medkit pickup flashes a floor ring,
## a green light and a burst of rising crosses; any restored health shows
## soft rising sparkles and a short-lived floating "+HP" number. Continuous
## healing (regeneration) is summed so numbers do not spam every frame.

const BODY_FONT := preload("res://assets/interface/fonts/body.ttf")
const RING_SHADER := preload("res://game/features/player/player_heal_ring.gdshader")
const HEAL_COLOR := Color(0.42, 0.95, 0.55)
const NUMBER_COLOR := Color(0.62, 1.0, 0.66)
const NUMBER_RISE := 0.8
const NUMBER_TIME := 1.5
## The number fades in and grows this long before it drifts and fades out.
const NUMBER_APPEAR := 0.25
const RING_TIME := 0.55
## Restored health below this is summed until the next flush.
const SUM_FLUSH_SECONDS := 0.9
const SPARKLE_LINGER := 0.45

static var _cross_texture: Texture2D

var _player: Node3D
var _sparkles: CPUParticles3D
var _sparkle_time := 0.0
var _pending := 0.0
var _pending_age := 0.0
var _number_stack := 0


func configure(player: Node3D) -> void:
	_player = player
	if player.has_signal("healed"):
		player.connect("healed", _on_healed)
	_sparkles = _make_sparkles()
	add_child(_sparkles)
	set_process(false)


func _on_healed(amount: float, source: StringName) -> void:
	if amount <= 0.0 or not is_inside_tree():
		return
	_sparkle_time = SPARKLE_LINGER
	_sparkles.emitting = true
	if source == &"medkit":
		_flush_pending()
		_play_medkit_burst()
		_spawn_number(amount, true)
	else:
		_pending += amount
		if _pending >= 5.0:
			_flush_pending()
	set_process(true)


func _process(delta: float) -> void:
	_sparkle_time -= delta
	if _sparkle_time <= 0.0:
		_sparkles.emitting = false
	if _pending > 0.0:
		_pending_age += delta
		if _pending_age >= SUM_FLUSH_SECONDS and _pending >= 1.0:
			_flush_pending()
	if _sparkle_time <= 0.0 and _pending < 1.0:
		set_process(false)


func _flush_pending() -> void:
	if _pending >= 1.0:
		_spawn_number(_pending, false)
		_pending = fmod(_pending, 1.0)
	_pending_age = 0.0


func _spawn_number(amount: float, large: bool) -> void:
	var label := Label3D.new()
	label.name = "HealNumber"
	label.font = BODY_FONT
	label.text = "+%d" % floori(amount)
	label.font_size = 50 if large else 34
	label.pixel_size = 0.0065
	label.outline_size = 11
	label.outline_modulate = Color(0.02, 0.12, 0.05, 0.9)
	label.modulate = NUMBER_COLOR
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.render_priority = 10
	label.outline_render_priority = 9
	# Numbers that overlap in time fan out so each stays readable.
	var side := float(_number_stack % 3 - 1) * 0.28
	_number_stack += 1
	label.position = Vector3(side, 2.15, 0.0)
	add_child(label)
	# One soft motion: fade and grow in without overshoot, drift up while
	# slowing down, fade out over the second half.
	var tween := label.create_tween()
	label.scale = Vector3.ONE * 0.8
	label.modulate.a = 0.0
	var outline_alpha := label.outline_modulate.a
	label.outline_modulate.a = 0.0
	tween.tween_property(label, "scale", Vector3.ONE, NUMBER_APPEAR).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(label, "modulate:a", 1.0, NUMBER_APPEAR * 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(label, "outline_modulate:a", outline_alpha, NUMBER_APPEAR * 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(label, "position:y", label.position.y + NUMBER_RISE, NUMBER_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(label, "modulate:a", 0.0, NUMBER_TIME * 0.5).set_delay(NUMBER_TIME * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.parallel().tween_property(label, "outline_modulate:a", 0.0, NUMBER_TIME * 0.5).set_delay(NUMBER_TIME * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_callback(func() -> void:
		_number_stack = maxi(0, _number_stack - 1)
		label.queue_free())


func _play_medkit_burst() -> void:
	var ring := MeshInstance3D.new()
	ring.name = "HealRing"
	var quad := QuadMesh.new()
	quad.size = Vector2(2.6, 2.6)
	quad.orientation = PlaneMesh.FACE_Y
	ring.mesh = quad
	var material := ShaderMaterial.new()
	material.shader = RING_SHADER
	material.set_shader_parameter("tint", HEAL_COLOR)
	material.set_shader_parameter("progress", 0.0)
	ring.material_override = material
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position.y = 0.06
	add_child(ring)
	var ring_tween := ring.create_tween()
	ring_tween.tween_method(func(value: float) -> void: material.set_shader_parameter("progress", value), 0.0, 1.0, RING_TIME).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	ring_tween.tween_callback(ring.queue_free)
	_flash_light()
	_burst_crosses()


func _flash_light() -> void:
	var light := OmniLight3D.new()
	light.name = "HealLight"
	light.light_color = HEAL_COLOR
	light.omni_range = 3.2
	light.light_energy = 0.0
	light.shadow_enabled = false
	light.position.y = 1.1
	add_child(light)
	var light_tween := light.create_tween()
	light_tween.tween_property(light, "light_energy", 2.4, 0.08)
	light_tween.tween_property(light, "light_energy", 0.0, 0.5).set_ease(Tween.EASE_IN)
	light_tween.tween_callback(light.queue_free)


func _burst_crosses() -> void:
	var burst := _make_cross_particles(12, 0.95)
	burst.name = "HealBurst"
	burst.one_shot = true
	burst.explosiveness = 0.7
	burst.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	burst.emission_ring_axis = Vector3.UP
	burst.emission_ring_height = 1.1
	burst.emission_ring_radius = 0.7
	burst.emission_ring_inner_radius = 0.45
	burst.position.y = 0.7
	burst.initial_velocity_min = 1.3
	burst.initial_velocity_max = 2.2
	burst.scale_amount_min = 0.9
	burst.scale_amount_max = 1.3
	add_child(burst)
	burst.emitting = true
	burst.finished.connect(burst.queue_free)


func _make_sparkles() -> CPUParticles3D:
	var sparkles := _make_cross_particles(8, 0.85)
	sparkles.name = "HealSparkles"
	sparkles.emitting = false
	sparkles.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	sparkles.emission_ring_axis = Vector3.UP
	sparkles.emission_ring_height = 1.3
	sparkles.emission_ring_radius = 0.55
	sparkles.emission_ring_inner_radius = 0.38
	sparkles.position.y = 0.85
	sparkles.initial_velocity_min = 0.5
	sparkles.initial_velocity_max = 0.9
	sparkles.scale_amount_min = 0.5
	sparkles.scale_amount_max = 0.8
	return sparkles


func _make_cross_particles(amount: int, lifetime: float) -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.amount = amount
	particles.lifetime = lifetime
	particles.local_coords = true
	particles.direction = Vector3.UP
	particles.spread = 12.0
	particles.gravity = Vector3.ZERO
	particles.damping_min = 0.6
	particles.damping_max = 1.2
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var fade := Gradient.new()
	fade.set_color(0, Color(HEAL_COLOR, 0.0))
	fade.set_color(1, Color(HEAL_COLOR, 0.0))
	fade.add_point(0.15, Color(0.85, 1.0, 0.88, 1.0))
	fade.add_point(0.5, Color(HEAL_COLOR, 0.85))
	particles.color_ramp = fade
	var shrink := Curve.new()
	shrink.add_point(Vector2(0.0, 0.6))
	shrink.add_point(Vector2(0.2, 1.0))
	shrink.add_point(Vector2(1.0, 0.35))
	particles.scale_amount_curve = shrink
	var quad := QuadMesh.new()
	quad.size = Vector2(0.12, 0.12)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = _cross()
	material.disable_receive_shadows = true
	quad.material = material
	particles.mesh = quad
	return particles


# A soft-edged medical cross, generated once and shared by every particle.
static func _cross() -> Texture2D:
	if _cross_texture != null:
		return _cross_texture
	const SIZE := 64
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var half := (SIZE - 1) * 0.5
	for y in range(SIZE):
		for x in range(SIZE):
			var dx := absf(x - half) / half
			var dy := absf(y - half) / half
			# Distance outside the union of a horizontal and a vertical bar.
			var bar_h := maxf(dx - 0.86, dy - 0.3)
			var bar_v := maxf(dx - 0.3, dy - 0.86)
			var outside := minf(bar_h, bar_v)
			var alpha := clampf(1.0 - outside / 0.12, 0.0, 1.0)
			var glow := clampf(1.0 - (outside + 0.12) / 0.5, 0.0, 1.0) * 0.35
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, maxf(alpha, glow)))
	_cross_texture = ImageTexture.create_from_image(image)
	return _cross_texture
