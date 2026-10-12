extends RefCounted
## Makes the mutation bar bright, taller and blinking while the player has lost control.
## Outside of control loss the bar keeps its normal look.

const BLINK_PERIOD := 0.5
const LOST_SCALE := Vector2(1.0, 1.6)
const BRIGHT := Color(2.2, 2.0, 1.6)
const DIM := Color(1.5, 0.7, 0.55)

var _bar: ProgressBar
var _time := 0.0
var _active := false


func _init(bar: ProgressBar) -> void:
	_bar = bar


func update(delta: float, control_lost: bool) -> void:
	if not control_lost:
		if _active:
			_active = false
			_time = 0.0
			_bar.modulate = Color.WHITE
			_bar.scale = Vector2.ONE
		return
	_active = true
	_time += delta
	_bar.pivot_offset = _bar.size * .5
	_bar.scale = LOST_SCALE
	_bar.modulate = BRIGHT if fmod(_time, BLINK_PERIOD * 2.0) < BLINK_PERIOD else DIM
