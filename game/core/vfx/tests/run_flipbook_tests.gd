extends SceneTree
## Runtime checks for sprite_flipbook_v1: frame timing (fast flash, slow tail),
## crossfade fraction, self-freeing, fixed-frame sprites and missing atlases.

const FLIPBOOK := preload("res://game/core/vfx/public/sprite_flipbook.gd")
const ATLASES := preload("res://game/core/vfx/public/effect_atlases.gd")
# Any texture serves as a 4x3 test sheet.
const TEST_SHEET := {
	"path": "res://models/objects/textures/grenade_explosion_layers/01_flash.png",
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
	stage.queue_free()
	await process_frame
	print("Flipbook tests: %d failure(s)." % failures)
	quit(failures)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
