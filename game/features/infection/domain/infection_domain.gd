extends RefCounted

enum AbilityChoice {
	NONE,
	FAST_HANDS,
	LEG_MUTATION,
	ENHANCED_AMMO,
}

const MUTATION_MIN := 0.0
const MUTATION_MAX := 100.0
const CLOUD_MUTATION_PER_SECOND := 5.0
const ABILITY_UNLOCK_THRESHOLD := 25.0
const ABILITY_DISABLE_THRESHOLD := 15.0
const BASE_CRITICAL_THRESHOLD := 30.0
const CONTROL_AMPULE_BONUS := 5.0
const MAX_CRITICAL_THRESHOLD := 95.0
const ANTIDOTE_REDUCTION := 10.0
const INSTABILITY_DURATION := 10.0
const FIRST_CONTROL_LOSS_DURATION := 5.0
const SECOND_CONTROL_LOSS_DURATION := 7.0
const RISK_WINDOW_DURATION := 30.0
const EPSILON := 0.00001

var mutation: float = 0.0
var active_ability: int = AbilityChoice.NONE
var priority_ability: int = AbilityChoice.NONE
var ability_choice_pending: bool = false

var critical_threshold: float = BASE_CRITICAL_THRESHOLD
var instability_elapsed: float = 0.0
var control_loss_remaining: float = 0.0
var risk_window_remaining: float = 0.0
var next_control_loss_stage: int = 1
var active_control_loss_stage: int = 0
var defeated: bool = false


func absorb_mutagen(delta_seconds: float) -> float:
	if delta_seconds <= 0.0 or defeated or is_control_lost():
		return 0.0

	var previous := mutation
	mutation = clampf(
		mutation + CLOUD_MUTATION_PER_SECOND * delta_seconds,
		MUTATION_MIN,
		MUTATION_MAX
	)
	_after_mutation_changed()
	return mutation - previous


func select_ability(choice: int, mark_priority: bool = false) -> bool:
	if not ability_choice_pending or mutation < ABILITY_UNLOCK_THRESHOLD:
		return false
	if not _is_valid_ability(choice):
		return false

	active_ability = choice
	ability_choice_pending = false
	if mark_priority:
		priority_ability = choice
	return true


func set_priority_ability(choice: int) -> bool:
	if choice == AbilityChoice.NONE:
		priority_ability = AbilityChoice.NONE
		return true
	if not _is_valid_ability(choice):
		return false

	priority_ability = choice
	return true


func add_control_ampule() -> float:
	critical_threshold = minf(
		critical_threshold + CONTROL_AMPULE_BONUS,
		MAX_CRITICAL_THRESHOLD
	)
	if mutation < critical_threshold:
		instability_elapsed = 0.0
	return critical_threshold


func use_antidote() -> bool:
	if defeated or is_control_lost():
		return false

	if risk_window_remaining > 0.0:
		risk_window_remaining = 0.0
		next_control_loss_stage = 1
		instability_elapsed = 0.0
		return true

	mutation = maxf(MUTATION_MIN, mutation - ANTIDOTE_REDUCTION)
	_after_mutation_changed()
	return true


func tick(delta_seconds: float) -> void:
	var remaining := maxf(delta_seconds, 0.0)
	while remaining > EPSILON and not defeated:
		if is_control_lost():
			var loss_step := minf(remaining, control_loss_remaining)
			control_loss_remaining -= loss_step
			remaining -= loss_step
			if control_loss_remaining <= EPSILON:
				control_loss_remaining = 0.0
				_finish_control_loss()
			continue

		var at_or_above_critical := mutation >= critical_threshold
		if not at_or_above_critical:
			instability_elapsed = 0.0

		var risk_time := INF
		if risk_window_remaining > 0.0:
			risk_time = risk_window_remaining

		var instability_time := INF
		if at_or_above_critical:
			instability_time = maxf(0.0, INSTABILITY_DURATION - instability_elapsed)

		var step := minf(remaining, minf(risk_time, instability_time))
		if step <= EPSILON:
			if at_or_above_critical and instability_time <= EPSILON:
				_trigger_control_loss()
				continue
			if risk_window_remaining > 0.0 and risk_time <= EPSILON:
				_expire_risk_window()
				continue
			break

		var instability_hits := (
			at_or_above_critical
			and instability_time <= step + EPSILON
		)
		var risk_expires := (
			risk_window_remaining > 0.0
			and risk_time <= step + EPSILON
		)

		if risk_window_remaining > 0.0:
			risk_window_remaining = maxf(0.0, risk_window_remaining - step)
		if at_or_above_critical:
			instability_elapsed += step
		remaining -= step

		if instability_hits:
			_trigger_control_loss()
		elif risk_expires:
			_expire_risk_window()


func is_control_lost() -> bool:
	return control_loss_remaining > 0.0


func _after_mutation_changed() -> void:
	_refresh_ability_state()
	if mutation < critical_threshold:
		instability_elapsed = 0.0


func _refresh_ability_state() -> void:
	if active_ability != AbilityChoice.NONE:
		if mutation < ABILITY_DISABLE_THRESHOLD:
			active_ability = AbilityChoice.NONE
			ability_choice_pending = false
		return

	if mutation < ABILITY_UNLOCK_THRESHOLD:
		ability_choice_pending = false
		return

	if priority_ability != AbilityChoice.NONE:
		active_ability = priority_ability
		ability_choice_pending = false
	else:
		ability_choice_pending = true


func _trigger_control_loss() -> void:
	instability_elapsed = 0.0
	risk_window_remaining = 0.0
	var stage := next_control_loss_stage

	if stage >= 3:
		defeated = true
		active_control_loss_stage = 3
		control_loss_remaining = 0.0
		return

	active_control_loss_stage = stage
	if stage == 1:
		control_loss_remaining = FIRST_CONTROL_LOSS_DURATION
	else:
		control_loss_remaining = SECOND_CONTROL_LOSS_DURATION
	next_control_loss_stage = stage + 1


func _finish_control_loss() -> void:
	active_control_loss_stage = 0
	risk_window_remaining = RISK_WINDOW_DURATION


func _expire_risk_window() -> void:
	risk_window_remaining = 0.0
	next_control_loss_stage = 1


func _is_valid_ability(choice: int) -> bool:
	return (
		choice == AbilityChoice.FAST_HANDS
		or choice == AbilityChoice.LEG_MUTATION
		or choice == AbilityChoice.ENHANCED_AMMO
	)
