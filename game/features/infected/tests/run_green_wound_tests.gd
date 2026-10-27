extends SceneTree
## Wounds on infected bodies follow the blood colour: green when a platform forces green blood.

const BLOOD_LEVEL := preload("res://game/core/vfx/public/blood_level.gd")
const SKIN := preload("res://game/features/infected/body_skin_materials.gd")
var failures := 0


func _init() -> void:
	BLOOD_LEVEL.set_level(2)
	var red := SKIN.create_material(null)
	if red.get_shader_parameter("blood_color") == BLOOD_LEVEL.GREEN_COLOR:
		failures += 1
		push_error("FAIL: wounds are green at a red level")
	BLOOD_LEVEL.force_green()
	var green := SKIN.create_material(null)
	if green.get_shader_parameter("blood_color") != BLOOD_LEVEL.GREEN_COLOR or green.get_shader_parameter("wound_core_color") != BLOOD_LEVEL.GREEN_WOUND_CORE:
		failures += 1
		push_error("FAIL: wounds are not green when green blood is forced")
	BLOOD_LEVEL.forced_green = false
	BLOOD_LEVEL.set_level(2)
	print("Green wound tests: %d failures" % failures)
	quit(failures)
