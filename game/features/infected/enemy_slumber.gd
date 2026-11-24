extends RefCounted
## An infected that has not noticed the hero and is far from them stops processing altogether (physics, animation,
## audio). A slow timer checks the distance and wakes it before the hero can be in sight range; a shot, a push, a
## noise or a cry wakes it at once through the infected's own entry points.
const SLEEP_MARGIN := 12.0  # metres beyond sight range before it dozes off
const WAKE_MARGIN := 8.0  # metres beyond sight range where it wakes again (less than SLEEP_MARGIN: no flicker)
const CHECK_SECONDS := 0.3

## Tests that drive the far LOD paths turn this off.
var enabled := true
var asleep := false
var _clock: Timer
var _mode := Node.PROCESS_MODE_INHERIT


## True when this infected may stop: far from the hero, idle and undisturbed.
func may_sleep(e: CharacterBody3D, gap_sq: float) -> bool:
	var limit: float = e.sight_range + SLEEP_MARGIN
	return enabled and gap_sq > limit * limit and e.is_on_floor() and e._push_velocity.is_zero_approx() \
		and e._blast_stun_remaining <= 0.0 and e.mutation_poison_remaining <= 0.0 \
		and e._pending_hit < 0.0 and e.health >= e.max_health


func sleep(e: CharacterBody3D) -> void:
	if asleep:
		return
	asleep = true
	_mode = e.process_mode
	if _clock == null:
		_clock = Timer.new()
		_clock.process_mode = Node.PROCESS_MODE_ALWAYS
		_clock.timeout.connect(_check.bind(e))
		e.add_child(_clock)
	_clock.start(CHECK_SECONDS + float(e.get_instance_id() % 7) * 0.02)
	e.process_mode = Node.PROCESS_MODE_DISABLED


func wake(e: CharacterBody3D) -> void:
	if not asleep:
		return
	asleep = false
	_clock.stop()
	e.process_mode = _mode


func _check(e: CharacterBody3D) -> void:
	var target: Node3D = e._target
	if not is_instance_valid(target):
		wake(e)
		return
	var limit: float = e.sight_range + WAKE_MARGIN
	if e.global_position.distance_squared_to(target.global_position) <= limit * limit:
		wake(e)
