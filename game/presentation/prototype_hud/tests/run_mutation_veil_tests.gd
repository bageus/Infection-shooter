extends SceneTree
## Second-loss green veil: fades in while escalated, fades out afterwards, and lets mouse input through.

const VEIL := preload("res://game/presentation/prototype_hud/mutation_veil.gd")

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var veil := VEIL.new()
	root.add_child(veil)
	_expect(not veil.visible, "The veil starts hidden.")
	_expect(veil.mouse_filter == Control.MOUSE_FILTER_IGNORE, "The veil never blocks mouse input.")
	veil.call("update", 0.1, true)
	_expect(veil.visible, "The veil becomes visible when escalation starts.")
	for frame in range(120):
		veil.call("update", 1.0 / 60.0, true)
	var strength: float = (veil.material as ShaderMaterial).get_shader_parameter("strength")
	_expect(is_equal_approx(strength, 1.0), "The veil reaches full strength while escalated.")
	for frame in range(120):
		veil.call("update", 1.0 / 60.0, false)
	_expect(not veil.visible, "The veil fades out and hides after escalation ends.")

	print("Mutation veil tests: %d failures" % failures)
	quit(failures)


func _expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
