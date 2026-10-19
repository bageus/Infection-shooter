extends RefCounted
## A brief slow-down on a heavy hit. The timer ignores time scale, so the
## slow-down always ends on its own.

const SLOW_SCALE := 0.08
const SECONDS := 0.06

static var _running := false


static func pulse(tree: SceneTree, seconds: float = SECONDS) -> void:
	if tree == null or _running or not is_equal_approx(Engine.time_scale, 1.0):
		return
	_running = true
	Engine.time_scale = SLOW_SCALE
	await tree.create_timer(seconds, true, false, true).timeout
	if is_equal_approx(Engine.time_scale, SLOW_SCALE):
		Engine.time_scale = 1.0
	_running = false
