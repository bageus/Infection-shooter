extends Area3D

signal depleted

@export var absorption_seconds: float = 2.0
@export var lifetime_seconds: float = 8.0

var _active: bool = false
var _absorption_remaining: float = 0.0
var _lifetime_remaining: float = 0.0


func _ready() -> void:
	monitoring = false
	visible = false


func activate() -> void:
	_active = true
	_absorption_remaining = absorption_seconds
	_lifetime_remaining = lifetime_seconds
	monitoring = true
	visible = true


func _physics_process(delta: float) -> void:
	if not _active:
		return

	_lifetime_remaining -= delta
	if _lifetime_remaining <= 0.0:
		_finish()
		return

	if _absorption_remaining <= 0.0:
		_finish()
		return

	var absorbing_body: Node = _find_absorbing_body()
	if absorbing_body == null:
		return

	var step := minf(delta, _absorption_remaining)
	absorbing_body.call("absorb_mutagen", step)
	_absorption_remaining -= step

	if _absorption_remaining <= 0.0:
		_finish()


func _find_absorbing_body() -> Node:
	for body in get_overlapping_bodies():
		if body != null and body.has_method("absorb_mutagen"):
			return body
	return null


func _finish() -> void:
	if not _active:
		return
	_active = false
	monitoring = false
	visible = false
	depleted.emit()
