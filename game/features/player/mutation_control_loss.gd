extends RefCounted

var direction := Vector3.ZERO
var _active := false
var _turn_remaining := 0.0
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.randomize()


func tick(delta: float, active: bool) -> void:
	if not active:
		_active = false
		_turn_remaining = 0.0
		direction = Vector3.ZERO
		return
	_turn_remaining -= delta
	if not _active or _turn_remaining <= 0.0:
		var angle := _rng.randf_range(0.0, TAU)
		direction = Vector3(cos(angle), 0.0, sin(angle))
		_turn_remaining = _rng.randf_range(0.65, 1.1)
	_active = true
