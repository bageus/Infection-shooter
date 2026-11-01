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
const FIRST_CONTROL_LOSS_DURATION := 2.0
const SECOND_CONTROL_LOSS_DURATION := 5.0
const GAS_MASK_WEAR_DURATION := 60.0
const GAS_MASK_COOLDOWN := 120.0
const EPSILON := 0.00001

var mutation: float = 0.0
var active_ability: int = AbilityChoice.NONE
var priority_ability: int = AbilityChoice.NONE
var ability_choice_pending: bool = false
## A worn gas mask keeps mutagen out: the body takes nothing from clouds.
var gas_mask_worn: bool = false
## Seconds the mask stays on before it comes off by itself.
var gas_mask_worn_remaining: float = 0.0
## Seconds until the mask may be put on again.
var gas_mask_cooldown_remaining: float = 0.0

var critical_threshold: float = BASE_CRITICAL_THRESHOLD
var control_loss_remaining: float = 0.0
var next_control_loss_stage: int = 1
var active_control_loss_stage: int = 0
var defeated: bool = false


func absorb_mutagen(delta_seconds: float) -> float:
	if delta_seconds <= 0.0 or defeated or is_control_lost() or gas_mask_worn:
		return 0.0
	# Above the limit the cloud is no longer absorbed; touching it escalates the loss.
	if mutation > critical_threshold:
		_trigger_control_loss()
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


func restore_critical_threshold(value: float) -> void:
	critical_threshold = clampf(value, BASE_CRITICAL_THRESHOLD, MAX_CRITICAL_THRESHOLD)


func add_control_ampule() -> float:
	critical_threshold = minf(
		critical_threshold + CONTROL_AMPULE_BONUS,
		MAX_CRITICAL_THRESHOLD
	)
	return critical_threshold


func antidote_result(effectiveness: float = 1.0) -> float:
	return maxf(MUTATION_MIN, mutation - ANTIDOTE_REDUCTION * effectiveness)


func use_antidote(effectiveness: float = 1.0) -> bool:
	if defeated:
		return false
	if mutation <= MUTATION_MIN:
		return false

	next_control_loss_stage = 1
	control_loss_remaining = 0.0
	active_control_loss_stage = 0
	mutation = antidote_result(effectiveness)
	_after_mutation_changed()
	return true


## Puts the mask on for 60 s; refused while it is worn or the cooldown runs.
func put_on_gas_mask() -> bool:
	if gas_mask_worn or gas_mask_cooldown_remaining > 0.0 or defeated or is_control_lost():
		return false
	set_gas_mask_worn(true)
	return true


func set_gas_mask_worn(worn: bool) -> void:
	gas_mask_worn = worn
	gas_mask_worn_remaining = GAS_MASK_WEAR_DURATION if worn else 0.0


func tick(delta_seconds: float) -> void:
	gas_mask_cooldown_remaining = maxf(0.0, gas_mask_cooldown_remaining - maxf(delta_seconds, 0.0))
	if gas_mask_worn:
		gas_mask_worn_remaining = maxf(0.0, gas_mask_worn_remaining - maxf(delta_seconds, 0.0))
		if gas_mask_worn_remaining <= 0.0:
			set_gas_mask_worn(false)
			gas_mask_cooldown_remaining = GAS_MASK_COOLDOWN
	if not is_control_lost() or defeated:
		return
	control_loss_remaining = maxf(0.0, control_loss_remaining - maxf(delta_seconds, 0.0))
	if control_loss_remaining <= EPSILON:
		control_loss_remaining = 0.0
		active_control_loss_stage = 0


func is_control_lost() -> bool:
	return control_loss_remaining > 0.0


func _after_mutation_changed() -> void:
	_refresh_ability_state()
	if mutation > critical_threshold and not is_control_lost() and not defeated:
		_trigger_control_loss()


## True once the next contact ends the run, or while the second loss is running.
func is_escalated() -> bool:
	return active_control_loss_stage == 2 or next_control_loss_stage >= 3


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


func _is_valid_ability(choice: int) -> bool:
	return (
		choice == AbilityChoice.FAST_HANDS
		or choice == AbilityChoice.LEG_MUTATION
		or choice == AbilityChoice.ENHANCED_AMMO
	)
