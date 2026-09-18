extends Node

const InfectionDomain = preload("res://game/features/infection/domain/infection_domain.gd")

signal mutation_changed(current: float, critical_threshold: float)
signal control_loss_changed(active: bool)
signal defeated

var _domain = InfectionDomain.new()
var _was_control_lost: bool = false
var _was_defeated: bool = false


func _physics_process(delta: float) -> void:
	var previous_mutation: float = _domain.mutation
	_domain.tick(delta)
	_emit_state_changes(previous_mutation)


func absorb_mutagen(delta_seconds: float) -> float:
	var previous_mutation: float = _domain.mutation
	var gained: float = _domain.absorb_mutagen(delta_seconds)
	_emit_state_changes(previous_mutation)
	return gained


func use_antidote() -> bool:
	var previous_mutation: float = _domain.mutation
	var used: bool = _domain.use_antidote()
	_emit_state_changes(previous_mutation)
	return used


func add_control_ampule() -> float:
	var previous_mutation: float = _domain.mutation
	var threshold: float = _domain.add_control_ampule()
	_emit_state_changes(previous_mutation)
	return threshold


func get_mutation() -> float:
	return _domain.mutation


func get_critical_threshold() -> float:
	return _domain.critical_threshold


func is_control_lost() -> bool:
	return _domain.is_control_lost()


func is_defeated() -> bool:
	return _domain.defeated


func _emit_state_changes(previous_mutation: float) -> void:
	if not is_equal_approx(previous_mutation, _domain.mutation):
		mutation_changed.emit(_domain.mutation, _domain.critical_threshold)

	var control_lost := _domain.is_control_lost()
	if control_lost != _was_control_lost:
		_was_control_lost = control_lost
		control_loss_changed.emit(control_lost)

	if _domain.defeated and not _was_defeated:
		_was_defeated = true
		defeated.emit()
