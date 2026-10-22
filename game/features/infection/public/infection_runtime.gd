extends Node
const MUTATION_BALANCE := preload("res://game/features/infection/public/mutation_balance.gd")

const InfectionDomain = preload("res://game/features/infection/domain/infection_domain.gd")
const MUTATION_TREE := preload("res://game/features/infection/domain/mutation_tree.gd")
const ACTIVE_STATE := preload("res://game/features/infection/domain/active_skill_state.gd")
const CATALOG := preload("res://game/features/infection/domain/mutation_catalog.gd")

signal mutation_changed(current: float, critical_threshold: float)
signal control_loss_changed(active: bool)
signal defeated
signal ability_choice_requested
signal ability_changed(choice: int)
signal tree_changed
signal skill_available
signal skill_cast(skill_id: String)
## Fact: an owned active skill's running cooldown reached zero.
signal skill_cooldown_finished(skill_id: String)
## Fact: a passive skill's effect just fired (duration 0 for instant effects).
signal passive_triggered(skill_id: String, duration: float)
## Fact: an active skill's lasting effect started or was extended.
signal skill_effect_started(skill_id: String, duration: float)
## Fact: a DNA ampule was collected; the control threshold rose to `critical_threshold`.
signal control_ampule_collected(critical_threshold: float)

const CONTROL_PROGRESS := preload("res://game/features/infection/domain/control_progress.gd")
var control_progress := CONTROL_PROGRESS.new()
var _domain = InfectionDomain.new()
var tree = MUTATION_TREE.new()
var _was_control_lost: bool = false
var _was_defeated: bool = false
var _was_choice_pending: bool = false
var _last_active_ability: int = 0
var _available_skills: Dictionary = {}
var active_state := ACTIVE_STATE.new()


func _physics_process(delta: float) -> void:
	var previous_mutation: float = _domain.mutation
	_domain.tick(delta)
	_tick_skills(delta, true)
	_emit_state_changes(previous_mutation)


func absorb_mutagen(delta_seconds: float) -> float:
	var previous_mutation: float = _domain.mutation
	var gained: float = _domain.absorb_mutagen(delta_seconds)
	_emit_state_changes(previous_mutation)
	return gained


func use_antidote() -> bool:
	var previous_mutation: float = _domain.mutation
	var used: bool = _domain.use_antidote(1.0 + MUTATION_BALANCE.value("assimilation", "percent") / 100.0 if has_skill("assimilation") else 1.0)
	_emit_state_changes(previous_mutation)
	return used


func add_control_ampule() -> float:
	var previous_mutation: float = _domain.mutation
	var previous_stability: float = _domain.critical_threshold
	control_progress.record_collection()
	var threshold: float = _domain.add_control_ampule()
	_emit_state_changes(previous_mutation, not is_equal_approx(previous_stability, threshold))
	control_ampule_collected.emit(threshold)
	return threshold


## Carries the control threshold over to the next map of a level chain or a respawn.
func restore_critical_threshold(value: float) -> void:
	var previous: float = _domain.critical_threshold
	_domain.restore_critical_threshold(value)
	_emit_state_changes(_domain.mutation, not is_equal_approx(previous, _domain.critical_threshold))


# Public progression_v1; level identity belongs to the authored mission.
func begin_control_level(id: String) -> void:
	control_progress.begin_level(id)


func complete_control_level(id: String) -> int:
	var recovered := control_progress.complete_level(id)
	for _i in recovered:
		add_control_ampule()
	return recovered


func antidote_preview() -> Dictionary:
	return CONTROL_PROGRESS.antidote_preview(_domain, tree)


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
		"active": CATALOG.is_active_skill(skill_id), "level": CATALOG.level(skill_id), "alternative": CATALOG.alternative(skill_id), "cooldown": CATALOG.cooldown(skill_id) * _cooldown_factor(),
		"version": 3, "path_reached": tree.path_reached(skill_id, _domain.mutation, _domain.critical_threshold), "stage": CATALOG.stage(row) + 1,
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


func _cooldown_factor() -> float:
	return 1.0 - MUTATION_BALANCE.value("neurostim", "percent") / 100.0 if has_skill("neurostim") else 1.0


func reduce_skill_cooldowns(seconds: float) -> void:
	_tick_skills(seconds, false)


func _tick_skills(seconds: float, advance_effects: bool) -> void:
	for id in active_state.tick(seconds, tree, get_mutation(), get_critical_threshold(), _cooldown_factor(), advance_effects):
		if not _domain.defeated and id in active_state.slots:
			skill_cooldown_finished.emit(id)


func equipped_skills() -> Array[String]:
	return active_state.slots.duplicate()


func assign_skill(slot: int, skill_id: String) -> bool:
	if not active_state.assign(slot, skill_id, tree, get_mutation(), get_critical_threshold()):
		return false
	tree_changed.emit()
	return true


func assignable_skills() -> Array[String]:
	var result: Array[String] = []
	for row in CATALOG.ACTIVE:
		var id := str(row[0])
		if not has_skill(id):
			continue
		var newer := false
		for other in CATALOG.ACTIVE:
			newer = newer or (other[2] == row[2] and int(other[3]) > int(row[3]) and tree.learned.has(str(other[0])))
		if not newer:
			result.append(id)
	return result


func upgrade_skill(skill_id: String) -> bool:
	if not tree.upgrade(skill_id, _domain.mutation, _domain.critical_threshold):
		return false
	active_state.learned(skill_id, tree, get_mutation(), get_critical_threshold())
	_available_skills = _upgrade_candidates()
	tree_changed.emit()
	return true


func toggle_skill_lock(skill_id: String) -> bool:
	if not tree.toggle_lock(skill_id):
		return false
	tree.reconcile(_domain.mutation)
	active_state.reconcile(tree, get_mutation(), get_critical_threshold(), _cooldown_factor())
	_available_skills = _upgrade_candidates()
	tree_changed.emit()
	return true


func cast_skill(skill_id: String) -> bool:
	if not can_cast_skill(skill_id):
		return false
	# Reserve first; the synchronous host effect may report a lasting duration.
	active_state.start_recovery(skill_id, tree, _cooldown_factor())
	skill_cast.emit(skill_id)
	if skill_effect_remaining(skill_id) > 0.0:
		tree.cooldowns[skill_id] = 0.0
	tree_changed.emit()
	return true


func skill_cooldown_remaining(skill_id: String) -> float:
	return float(tree.cooldowns.get(skill_id, 0.0))


## 1.0 right after casting, falling to 0.0 when the skill is ready again.
func skill_cooldown_ratio(skill_id: String) -> float:
	var total := float(active_state.totals.get(skill_id, 0.0))
	return clampf(skill_cooldown_remaining(skill_id) / total, 0.0, 1.0) if total > 0.0 else 0.0


func can_cast_skill(skill_id: String) -> bool:
	return not _domain.is_control_lost() and not _domain.defeated and active_state.can_cast(skill_id, tree, get_mutation(), get_critical_threshold())


func report_skill_effect(skill_id: String, duration: float) -> void:
	if duration <= 0.0 or not CATALOG.is_active_skill(skill_id):
		return
	active_state.report_effect(skill_id, duration)
	tree.cooldowns[skill_id] = 0.0
	skill_effect_started.emit(skill_id, duration)


func skill_effect_remaining(skill_id: String) -> float:
	return float(active_state.effects.get(skill_id, 0.0))


## 1.0 when a lasting effect starts, falling to 0.0 when it ends.
func skill_effect_ratio(skill_id: String) -> float:
	var total := float(active_state.effect_totals.get(skill_id, 0.0))
	return clampf(skill_effect_remaining(skill_id) / total, 0.0, 1.0) if total > 0.0 else 0.0


func report_passive(skill_id: String, duration: float = 0.0) -> void:
	if has_skill(skill_id):
		passive_triggered.emit(skill_id, duration)


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


## True once a second loss has started or the next mutagen contact ends the run.
func is_escalated() -> bool:
	return _domain.is_escalated()


func _emit_state_changes(previous_mutation: float, stability_changed: bool = false) -> void:
	if stability_changed or not is_equal_approx(previous_mutation, _domain.mutation):
		var tree_updated: bool = tree.reconcile(_domain.mutation)
		var slots_updated := active_state.reconcile(tree, get_mutation(), get_critical_threshold(), _cooldown_factor())
		if tree_updated or slots_updated:
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
