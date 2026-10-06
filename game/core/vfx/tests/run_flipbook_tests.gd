extends SceneTree
## Runtime checks for sprite_flipbook_v1: frame timing (fast flash, slow tail),
## crossfade fraction, self-freeing, fixed-frame sprites and missing atlases.

const FLIPBOOK := preload("res://game/core/vfx/public/sprite_flipbook.gd")
const ATLASES := preload("res://game/core/vfx/public/effect_atlases.gd")
# Any texture serves as a 4x3 test sheet.
const TEST_SHEET := {
	"path": "res://models/objects/textures/grenade_explosion_layers/Twelve-frame fiery explosion flipbook atlas.png",
	"columns": 4, "rows": 3, "frames": 12,
	"durations": [0.02, 0.02, 0.02, 0.02, 0.03, 0.03, 0.04, 0.05, 0.06, 0.08, 0.1, 0.13],
}

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	_expect(is_equal_approx(FLIPBOOK.frame_at(TEST_SHEET, 0.0), 0.0), "Playback starts on the first frame.")
	_expect(is_equal_approx(FLIPBOOK.frame_at(TEST_SHEET, 0.03), 1.5), "Frame position carries the crossfade fraction.")
	_expect(FLIPBOOK.frame_at(TEST_SHEET, 10.0) < 0.0, "Playback ends after the last frame.")
	_expect(is_equal_approx(FLIPBOOK.length_of(TEST_SHEET), 0.6), "Sheet length is the sum of frame times.")
	for atlas in [ATLASES.GRENADE_EXPLOSION, ATLASES.ELECTRIC_SPARK, ATLASES.EXTINGUISHER_SPRAY]:
		var spans: Array = atlas["durations"]
		_expect(spans.size() == int(atlas["frames"]), "Every frame has a time: " + str(atlas["path"]))
		_expect(float(spans[0]) <= float(spans[spans.size() - 1]), "Opening frames play no slower than the closing ones.")
	var missing := {"path": "res://does/not/exist.png", "columns": 1, "rows": 1, "frames": 1, "durations": [0.1]}
	_expect(FLIPBOOK.spawn(stage, missing, Vector3.ZERO, 1.0) == null, "A missing sheet spawns nothing.")
	var sprite := FLIPBOOK.spawn(stage, TEST_SHEET, Vector3(1, 2, 3), 2.0, {"additive": 1.0})
	_expect(sprite != null and sprite.global_position.is_equal_approx(Vector3(1, 2, 3)), "A flipbook appears where it was asked.")
	_expect(sprite != null and is_equal_approx(sprite.scale.x, 2.0), "The flipbook has the requested size.")
	await create_timer(0.3).timeout
	_expect(is_instance_valid(sprite) and float(sprite.get_instance_shader_parameter(&"frame_position")) > 5.0, "Frames advance with time.")
	await create_timer(0.5).timeout
	_expect(not is_instance_valid(sprite), "The flipbook frees itself after the last frame.")
	var scrap := FLIPBOOK.spawn(stage, TEST_SHEET, Vector3.ZERO, 0.2, {"frame": 7, "lifetime": 0.4, "velocity": Vector3(1, 1, 0), "gravity": 3.0, "billboard": false})
	await create_timer(0.2).timeout
	_expect(is_instance_valid(scrap) and is_equal_approx(float(scrap.get_instance_shader_parameter(&"frame_position")), 7.0), "A fixed-frame sprite keeps its frame.")
	_expect(is_instance_valid(scrap) and scrap.global_position.x > 0.1, "A moving sprite travels with its velocity.")
	await create_timer(0.4).timeout
	_expect(not is_instance_valid(scrap), "A fixed-frame sprite frees itself after its lifetime.")
	for atlas in [ATLASES.GRENADE_EXPLOSION, ATLASES.ELECTRIC_SPARK, ATLASES.TORN_PAPER, ATLASES.EXTINGUISHER_SPRAY]:
		_expect(ATLASES.available(atlas), "Supplied sheet is in the project: " + str(atlas["path"]))
		var texture := load(str(atlas["path"])) as Texture2D
		var cell := Vector2(texture.get_width() / float(atlas["columns"]), texture.get_height() / float(atlas["rows"]))
		_expect(absf(cell.x / cell.y - 1.0) < 0.05, "Sheet cells are square, so the grid is right: " + str(atlas["path"]))
	var looping := FLIPBOOK.spawn(stage, TEST_SHEET, Vector3.ZERO, 1.0, {"first_frame": 0, "last_frame": 5, "loop_from": 3, "axis": Vector3.FORWARD})
	var seen_low := 9.0
	var seen_high := 0.0
	for i in 40:
		await process_frame
	var until := Time.get_ticks_msec() + 600
	while Time.get_ticks_msec() < until:
		var frame := float(looping.get_instance_shader_parameter(&"frame_position"))
		seen_low = minf(seen_low, frame)
		seen_high = maxf(seen_high, frame)
		await process_frame
	_expect(is_instance_valid(looping), "A looping flipbook keeps playing.")
	_expect(seen_low >= 2.99 and seen_low < 3.6 and seen_high <= 5.0 and seen_high > 4.4, "The loop swings between its frames (%.2f..%.2f)." % [seen_low, seen_high])
	_expect(float(looping.get_instance_shader_parameter(&"axial")) > 0.5, "An axis turns the sprite into an axial billboard.")
	looping.call("stop", 0.1)
	await create_timer(0.3).timeout
	_expect(not is_instance_valid(looping), "stop() fades a looping flipbook out.")
	await _check_cycle_and_ground(stage)
	_check_skill_sheets()
	stage.queue_free()
	await process_frame
	print("Flipbook tests: %d failure(s)." % failures)
	quit(failures)


# Cycle mode repeats the whole sheet in order (last frame blends into the
# first); ground mode lays the quad on the floor with the atlas stretch.
func _check_cycle_and_ground(stage: Node3D) -> void:
	var sheet := {"path": TEST_SHEET["path"], "columns": 4, "rows": 3, "frames": 12, "durations": TEST_SHEET["durations"], "ground_stretch": 2.5}
	var ring := FLIPBOOK.spawn(stage, sheet, Vector3.ZERO, 2.0, {"cycle": true, "ground": true})
	_expect(float(ring.get_instance_shader_parameter(&"ground")) > 0.5, "Ground mode is passed to the shader.")
	_expect(is_equal_approx(float(ring.get_instance_shader_parameter(&"ground_stretch")), 2.5), "Ground mode uses the sheet's stretch.")
	_expect(float(ring.get_instance_shader_parameter(&"cycle")) > 0.5, "Cycle mode is passed to the shader.")
	var wrapped := false
	var previous := -1.0
	var until := Time.get_ticks_msec() + int(FLIPBOOK.length_of(sheet) * 2500.0)
	while Time.get_ticks_msec() < until:
		var frame := float(ring.get_instance_shader_parameter(&"frame_position"))
		wrapped = wrapped or (previous > 9.0 and frame < 2.0)
		previous = frame
		await process_frame
	_expect(is_instance_valid(ring), "A cycling flipbook outlives its sheet.")
	_expect(wrapped, "A cycling flipbook starts over from the first frame.")
	ring.call("stop", 0.05)
	await create_timer(0.2).timeout
	_expect(not is_instance_valid(ring), "stop() ends a cycling flipbook.")


func _check_skill_sheets() -> void:
	for atlas: Dictionary in [ATLASES.ELECTRIC_FIELD, ATLASES.CLAW_SLASH, ATLASES.ELECTRIC_PULSE, ATLASES.SPIKE_BURST, ATLASES.ENERGY_SHIELD, ATLASES.CHAIN_LIGHTNING, ATLASES.SPORE_COCOON, ATLASES.BLADE_ORBIT, ATLASES.STUN_STARS, ATLASES.ACID_PUDDLES, ATLASES.HEARTBEAT]:
		_expect(ATLASES.available(atlas), "Skill sheet is in the project: " + str(atlas["path"]))
		var texture := load(str(atlas["path"])) as Texture2D
		var cell := Vector2(texture.get_width() / float(atlas["columns"]), texture.get_height() / float(atlas["rows"]))
		_expect(absf(cell.x / cell.y - 1.0) < 0.05, "Skill sheet cells are square: " + str(atlas["path"]))
		var spans: Array = atlas["durations"]
		_expect(spans.is_empty() or spans.size() == int(atlas["frames"]), "Every skill frame has a time: " + str(atlas["path"]))
	_expect(is_equal_approx(ATLASES.size_for_radius(ATLASES.ELECTRIC_FIELD, 4.0), 8.0 / 0.9), "A ring of radius R plays at 2R / extent.")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
