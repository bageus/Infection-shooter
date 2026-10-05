extends Node

const InfectionDomain = preload("res://game/features/infection/domain/infection_domain.gd")
const MUTATION_TREE := preload("res://game/features/infection/domain/mutation_tree.gd")
const CATALOG := preload("res://game/features/infection/domain/mutation_catalog.gd")

signal mutation_changed(current: float, critical_threshold: float)
signal control_loss_changed(active: bool)
signal defeated
signal ability_choice_requested
signal ability_changed(choice: int)
signal tree_changed
signal skill_available
signal skill_cast(skill_id: String)

var _domain = InfectionDomain.new()
var tree = MUTATION_TREE.new()
var _was_control_lost: bool = false
var _was_defeated: bool = false
var _was_choice_pending: bool = false
var _last_active_ability: int = 0
var _available_skills: Dictionary = {}


func _physics_process(delta: float) -> void:
	var previous_mutation: float = _domain.mutation
	_domain.tick(delta)
	tree.tick(delta)
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
	var previous_stability: float = _domain.critical_threshold
	var threshold: float = _domain.add_control_ampule()
	_emit_state_changes(previous_mutation, not is_equal_approx(previous_stability, threshold))
	return threshold


func get_mutation() -> float:
	return _domain.mutation


func skill_catalog() -> Array:
	return CATALOG.all().duplicate() # callers must not edit the shared rows


# Read-only versioned requirements DTO; UI never duplicates progression rules.
func skill_requirements(skill_id: String) -> Dictionary:
	var row := CATALOG.find(skill_id)
	if row.is_empty():
		return {}
	return {
		"version": 2, "path_reached": tree.path_reached(skill_id, _domain.mutation, _domain.critical_threshold), "stage": CATALOG.stage(row) + 1,
		"mutation": CATALOG.threshold(row), "stability": CATALOG.required_stability(row),
		"branch_open": _domain.critical_threshold >= CATALOG.required_stability(row)
	}


func mutation_points() -> int:
	return tree.points(_domain.mutation)


func has_skill(skill_id: String) -> bool:
	return tree.is_active(skill_id, _domain.mutation, _domain.critical_threshold)


func skill_learned(skill_id: String) -> bool:
	if CATALOG.HYBRID_PARENTS.has(skill_id):
		return tree.has_hybrid_parents(skill_id)
	return tree.learned.has(skill_id)


func skill_locked(skill_id: String) -> bool:
	return tree.locked.has(skill_id)


func can_upgrade_skill(skill_id: String) -> bool:
	return tree.can_upgrade(skill_id, _domain.mutation, _domain.critical_threshold)


func _upgrade_candidates() -> Dictionary:
	var candidates := {}
	for row in CATALOG.all():
		if tree.can_upgrade(str(row[0]), _domain.mutation, _domain.critical_threshold):
			candidates[str(row[0])] = true
	return candidates


func reduce_skill_cooldowns(seconds: float) -> void:
	for skill_id in tree.cooldowns.keys():
		tree.cooldowns[skill_id] = maxf(0.0, float(tree.cooldowns[skill_id]) - seconds)


func upgrade_skill(skill_id: String) -> bool:
	if not tree.upgrade(skill_id, _domain.mutation, _domain.critical_threshold):
		return false
	_available_skills = _upgrade_candidates()
	tree_changed.emit()
	return true


func toggle_skill_lock(skill_id: String) -> bool:
	if not tree.toggle_lock(skill_id):
		return false
	tree.reconcile(_domain.mutation)
	_available_skills = _upgrade_candidates()
	tree_changed.emit()
	return true


func cast_skill(skill_id: String) -> bool:
	if _domain.is_control_lost() or _domain.defeated:
		return false
	if not tree.cast(skill_id, _domain.mutation, _domain.critical_threshold):
		return false
	skill_cast.emit(skill_id)
	if has_skill("neurostim"):
		tree.cooldowns[skill_id] = float(tree.cooldowns[skill_id]) * 0.8
	tree_changed.emit()
	return true


func is_ability_choice_pending() -> bool:
	return _domain.ability_choice_pending


func get_active_ability() -> int:
	return _domain.active_ability


func select_ability(choice: int) -> bool:
	var selected := _domain.select_ability(choice)
	if selected:
		_emit_ability_state()
	return selected


func get_critical_threshold() -> float:
	return _domain.critical_threshold


func is_control_lost() -> bool:
	return _domain.is_control_lost()


func is_defeated() -> bool:
	return _domain.defeated


func _emit_state_changes(previous_mutation: float, stability_changed: bool = false) -> void:
	if stability_changed or not is_equal_approx(previous_mutation, _domain.mutation):
		if tree.reconcile(_domain.mutation):
			tree_changed.emit()
		mutation_changed.emit(_domain.mutation, _domain.critical_threshold)
		if stability_changed or CATALOG.point_budget(previous_mutation) != CATALOG.point_budget(_domain.mutation):
			tree_changed.emit()
		var candidates := _upgrade_candidates()
		if stability_changed or _domain.mutation > previous_mutation:
			for skill_id in candidates:
				if not _available_skills.has(skill_id):
					_available_skills = candidates
					skill_available.emit()
					break
		_available_skills = candidates

	var control_lost := _domain.is_control_lost()
	if control_lost != _was_control_lost:
		_was_control_lost = control_lost
		control_loss_changed.emit(control_lost)

	_emit_ability_state()

	if _domain.defeated and not _was_defeated:
		_was_defeated = true
		defeated.emit()


func _emit_ability_state() -> void:
	if _domain.ability_choice_pending and not _was_choice_pending:
		ability_choice_requested.emit()
	_was_choice_pending = _domain.ability_choice_pending
	if _domain.active_ability != _last_active_ability:
		_last_active_ability = _domain.active_ability
		ability_changed.emit(_last_active_ability)
