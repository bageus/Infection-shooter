extends SceneTree

const InfectionDomain = preload("res://game/features/infection/domain/infection_domain.gd")

var failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_cloud_rate_and_bounds()
	_test_ability_hysteresis_and_priority()
	_test_control_ampule_threshold_cap()
	_test_ordinary_antidote()
	_test_first_control_loss()
	_test_escalation_to_defeat()
	_test_risk_window_expiry_resets_escalation()
	_test_antidote_resets_risk_without_reducing_mutation()
	_test_instability_only_builds_at_critical_threshold()
	_test_mutagen_pauses_during_control_loss()

	if failures == 0:
		print("T001 infection domain tests passed.")
	else:
		push_error("T001 infection domain tests failed: %d failure(s)." % failures)
	quit(failures)


func _test_cloud_rate_and_bounds() -> void:
	var domain = InfectionDomain.new()
	_expect_float(domain.absorb_mutagen(2.0), 10.0, "A full 2-second cloud adds 10 mutation.")
	_expect_float(domain.mutation, 10.0, "Mutation records the cloud gain.")
	domain.absorb_mutagen(100.0)
	_expect_float(domain.mutation, 100.0, "Mutation is capped at 100.")


func _test_ability_hysteresis_and_priority() -> void:
	var domain = InfectionDomain.new()
	domain.absorb_mutagen(5.0)
	_expect(domain.ability_choice_pending, "Reaching 25 requests the first ability choice.")
	_expect(
		domain.select_ability(InfectionDomain.AbilityChoice.FAST_HANDS),
		"A pending first ability can be selected."
	)
	_expect(
		domain.active_ability == InfectionDomain.AbilityChoice.FAST_HANDS,
		"The selected ability becomes active."
	)

	domain.use_antidote()
	_expect_float(domain.mutation, 15.0, "Antidote from 25 leaves exactly 15 mutation.")
	_expect(
		domain.active_ability == InfectionDomain.AbilityChoice.FAST_HANDS,
		"Ability remains active at the lower threshold of 15."
	)

	domain.use_antidote()
	_expect(
		domain.active_ability == InfectionDomain.AbilityChoice.NONE,
		"Ability disables only below 15."
	)
	domain.absorb_mutagen(4.0)
	_expect(
		domain.ability_choice_pending,
		"Without priority, returning to 25 requests a choice again."
	)
	_expect(
		domain.select_ability(InfectionDomain.AbilityChoice.ENHANCED_AMMO, true),
		"Ability selection can also mark a priority."
	)

	domain.use_antidote()
	domain.use_antidote()
	_expect(
		domain.active_ability == InfectionDomain.AbilityChoice.NONE,
		"Priority does not prevent disabling below 15."
	)
	domain.absorb_mutagen(4.0)
	_expect(
		domain.active_ability == InfectionDomain.AbilityChoice.ENHANCED_AMMO,
		"Priority reactivates automatically when mutation returns to 25."
	)
	_expect(not domain.ability_choice_pending, "Priority reactivation skips the choice prompt.")


func _test_control_ampule_threshold_cap() -> void:
	var domain = InfectionDomain.new()
	domain.absorb_mutagen(4.0)
	var mutation_before := domain.mutation
	for index in range(20):
		domain.add_control_ampule()
	_expect_float(domain.critical_threshold, 95.0, "Control ampules cap the critical threshold at 95.")
	_expect_float(domain.mutation, mutation_before, "Control ampules do not alter accumulated mutation.")


func _test_ordinary_antidote() -> void:
	var domain = InfectionDomain.new()
	domain.absorb_mutagen(4.0)
	domain.use_antidote()
	_expect_float(domain.mutation, 10.0, "Ordinary antidote reduces mutation by exactly 10.")
	domain.use_antidote()
	domain.use_antidote()
	_expect_float(domain.mutation, 0.0, "Ordinary antidote cannot reduce mutation below zero.")


func _test_first_control_loss() -> void:
	var domain = _reach_first_control_loss()
	_expect(domain.is_control_lost(), "Ten seconds at critical mutation starts control loss.")
	_expect(domain.active_control_loss_stage == 1, "The first control loss is stage one.")
	_expect_float(domain.control_loss_remaining, 5.0, "Stage one control loss lasts five seconds.")
	domain.tick(5.0)
	_expect(not domain.is_control_lost(), "Control returns after five seconds.")
	_expect_float(domain.risk_window_remaining, 30.0, "Stage one opens a 30-second risk window.")


func _test_escalation_to_defeat() -> void:
	var domain = _reach_first_control_loss()
	domain.tick(5.0)
	domain.tick(10.0)
	_expect(domain.active_control_loss_stage == 2, "A new loss inside the first risk window is stage two.")
	_expect_float(domain.control_loss_remaining, 7.0, "Stage two control loss lasts seven seconds.")
	domain.tick(7.0)
	_expect_float(domain.risk_window_remaining, 30.0, "Stage two opens a new 30-second risk window.")
	domain.tick(10.0)
	_expect(domain.defeated, "A third trigger inside the second risk window causes defeat.")


func _test_risk_window_expiry_resets_escalation() -> void:
	var domain = _reach_first_control_loss()
	domain.tick(5.0)
	domain.add_control_ampule()
	_expect_float(domain.critical_threshold, 35.0, "A control ampule raises the threshold by five.")
	domain.tick(30.0)
	_expect_float(domain.risk_window_remaining, 0.0, "A survived risk window expires.")
	_expect(domain.next_control_loss_stage == 1, "Risk-window expiry resets escalation to stage one.")
	domain.absorb_mutagen(1.0)
	domain.tick(10.0)
	_expect(domain.active_control_loss_stage == 1, "The next loss after reset lasts as stage one.")


func _test_antidote_resets_risk_without_reducing_mutation() -> void:
	var domain = _reach_first_control_loss()
	domain.tick(5.0)
	var mutation_before := domain.mutation
	_expect(domain.use_antidote(), "Antidote is usable during the risk window.")
	_expect_float(domain.mutation, mutation_before, "Risk-window antidote does not reduce mutation.")
	_expect_float(domain.risk_window_remaining, 0.0, "Risk-window antidote ends the window immediately.")
	_expect(domain.next_control_loss_stage == 1, "Risk-window antidote resets escalation to stage one.")
	domain.tick(10.0)
	_expect(domain.active_control_loss_stage == 1, "Continued high mutation restarts from stage one.")


func _test_instability_only_builds_at_critical_threshold() -> void:
	var domain = InfectionDomain.new()
	domain.absorb_mutagen(5.0)
	domain.tick(100.0)
	_expect_float(domain.instability_elapsed, 0.0, "Instability does not build below the critical threshold.")
	domain.absorb_mutagen(1.0)
	domain.tick(9.9)
	_expect(not domain.is_control_lost(), "Instability has not triggered before ten seconds.")
	domain.tick(0.1)
	_expect(domain.is_control_lost(), "Instability triggers at ten seconds at or above threshold.")


func _test_mutagen_pauses_during_control_loss() -> void:
	var domain = _reach_first_control_loss()
	var mutation_before := domain.mutation
	_expect_float(domain.absorb_mutagen(2.0), 0.0, "Mutagen does not accumulate during control loss.")
	_expect_float(domain.mutation, mutation_before, "Mutation remains unchanged during control loss.")


func _reach_first_control_loss():
	var domain = InfectionDomain.new()
	domain.absorb_mutagen(6.0)
	domain.tick(10.0)
	return domain


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)


func _expect_float(actual: float, expected: float, message: String) -> void:
	_expect(is_equal_approx(actual, expected), "%s Expected %.4f, got %.4f." % [message, expected, actual])
