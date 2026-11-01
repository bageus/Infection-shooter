extends SceneTree

const InfectionDomain = preload("res://game/features/infection/domain/infection_domain.gd")
const Catalog = preload("res://game/features/infection/domain/mutation_catalog.gd")
const Runtime = preload("res://game/features/infection/public/infection_runtime.gd")
const MutationTree = preload("res://game/features/infection/domain/mutation_tree.gd")

var failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_cloud_rate_and_bounds()
	_test_ability_hysteresis_and_priority()
	_test_control_ampule_threshold_cap()
	_test_ordinary_antidote()
	_test_last_circle_is_reachable()
	_test_first_control_loss()
	_test_contact_escalates_to_second_loss()
	_test_third_contact_defeats_without_loss()
	_test_loss_does_not_escalate_on_timer()
	_test_antidote_resets_escalation()
	_test_antidote_resets_after_second_loss()
	_test_emergency_antidote_during_control_loss()
	_test_exact_threshold_and_immediate_crossing()
	_test_below_threshold_has_no_delayed_loss()
	_test_mutagen_pauses_during_control_loss()
	_test_frame_steps_land_on_threshold()
	_test_progression_budget_and_stages()
	_test_retained_budget_and_preview()
	_test_pinned_skill_refreshes_tree_on_antidote()
	_test_control_ampule_compensation()
	_test_path_feedback_without_spare_points()
	_test_organic_ammo_hybrid()
	_test_runtime_cast_control_guard()
	_test_hybrid_stage_gates()
	_test_ampule_notification_and_antidote()
	_test_skill_tree_lock_and_reactivation()
	_test_skill_branch_order_and_locked_prerequisites()
	_test_gas_mask_blocks_mutagen()
	_test_gas_mask_cooldown()

	if failures == 0:
		print("T001 infection domain tests passed.")
	else:
		push_error("T001 infection domain tests failed: %d failure(s)." % failures)
	quit(failures)


func _test_pinned_skill_refreshes_tree_on_antidote() -> void:
	# A pinned skill stays learned below its threshold, so the progress bar must still refresh.
	var runtime := Runtime.new()
	var refreshes := [0]
	runtime.tree_changed.connect(func() -> void: refreshes[0] += 1)
	runtime._domain.mutation = 30.0
	_expect(runtime.upgrade_skill("muscle_memory"), "Pinned fixture learns a real skill")
	runtime.toggle_skill_lock("muscle_memory")
	var before: int = refreshes[0]
	_expect(runtime.use_antidote(), "Antidote applies to a pinned skill")
	_expect(runtime.skill_learned("muscle_memory") and not runtime.skill_requirements("muscle_memory")["path_reached"], "Pinned skill stays learned but its path is no longer reached")
	_expect(refreshes[0] > before, "Antidote that drops mutation below a pinned skill's threshold refreshes the tree")
	runtime.free()


func _test_retained_budget_and_preview() -> void:
	var runtime := Runtime.new()
	runtime._domain.mutation = 30.0
	_expect(runtime.upgrade_skill("muscle_memory"), "Fixture learns a real skill")
	var learned_before: Dictionary = runtime.tree.learned.duplicate()
	var preview := runtime.antidote_preview()
	_expect(runtime.tree.learned == learned_before and runtime.get_mutation() == 30.0, "Preview leaves live mutation/skills unchanged")
	_expect(preview.forgotten == ["muscle_memory"] and preview.after == 20.0 and preview.points_after == 0, "Preview shows exact forgotten skill and the budget at the new mutation")
	_expect(runtime.use_antidote(), "Runtime applies confirmed or emergency use")
	_expect(runtime.mutation_points() == preview.points_after and not runtime.skill_learned("muscle_memory"), "Actual result equals preview")
	for _i in 5:
		runtime.absorb_mutagen(2.0)
		runtime.use_antidote()
	_expect(runtime.mutation_points() == 0, "Repeated antidote cycles cannot farm new budget: points follow the current mutation")
	runtime._domain.mutation = 100.0
	_expect(runtime.mutation_points() == 16, "Budget caps at 16 at full mutation")
	runtime.free()


func _test_control_ampule_compensation() -> void:
	var runtime := Runtime.new()
	runtime.begin_control_level("floor_a")
	_expect(runtime.complete_control_level("other") == 0, "A mismatched level id cannot grant an ampule")
	_expect(runtime.complete_control_level("floor_a") == 1 and runtime.get_critical_threshold() == 35.0, "Exit compensates one missed ampule")
	_expect(runtime.complete_control_level("floor_a") == 0 and runtime.get_critical_threshold() == 35.0, "Repeated exit cannot duplicate compensation")
	runtime.begin_control_level("floor_b")
	runtime.add_control_ampule()
	_expect(runtime.complete_control_level("floor_b") == 0 and runtime.get_critical_threshold() == 40.0, "Collected ampule suppresses compensation")
	runtime.begin_control_level("floor_c")
	_expect(runtime.complete_control_level("floor_c") == 1 and runtime.get_critical_threshold() == 45.0, "A new missed level is tracked independently")
	for level in range(20):
		var id := "floor_%d" % level
		runtime.begin_control_level(id)
		runtime.complete_control_level(id)
	_expect(runtime.get_critical_threshold() == 95.0, "Compensation respects the95 stability cap")
	runtime.free()


func _test_skill_tree_lock_and_reactivation() -> void:
	var tree := MutationTree.new()
	_expect(tree.upgrade("muscle_memory", 70.0, 95.0), "The first skill can be learned with sufficient mutation.")
	_expect(tree.upgrade("claws", 70.0, 95.0), "A second passive branch can be learned.")
	_expect(not tree.is_active("killer_instinct", 70.0, 95.0), "Two first circles do not complete a hybrid.")
	_expect(not tree.upgrade("killer_instinct", 70.0, 95.0), "A hybrid is not a separate point purchase.")
	_expect(tree.toggle_lock("muscle_memory"), "Learned skill lock toggles.")
	_expect(tree.reconcile(10.0), "Unlocked skills disappear below their threshold.")
	_expect(tree.learned.has("muscle_memory"), "Locked skill remains learned below threshold.")
	_expect(not tree.is_active("muscle_memory", 10.0, 95.0), "Locked skill is inactive below threshold.")
	_expect(tree.is_active("muscle_memory", 70.0, 95.0), "Locked skill reactivates without another point.")
	_expect(not tree.learned.has("claws"), "Unlocked skill must be learned again.")


func _test_skill_branch_order_and_locked_prerequisites() -> void:
	var tree := MutationTree.new()
	_expect(tree.upgrade("hypertrophy", 100.0, 95.0), "Passive Biomass begins at its first circle.")
	_expect(not tree.upgrade("blood_burst_2", 100.0, 95.0), "Passive Biomass cannot unlock the active branch's second circle.")
	_expect(tree.upgrade("regeneration", 100.0, 95.0), "Passive Biomass may advance from its first circle.")
	_expect(tree.upgrade("blood_burst", 100.0, 95.0), "Active Biomass begins independently.")
	_expect(tree.upgrade("blood_burst_2", 100.0, 95.0), "Active Biomass advances after its own first circle.")
	_expect(tree.upgrade("blood_burst_3", 100.0, 95.0), "The third circle follows the second.")
	_expect(tree.toggle_lock("blood_burst_3"), "The last circle can be locked.")
	tree.reconcile(10.0)
	_expect(tree.learned.has("blood_burst") and tree.learned.has("blood_burst_2"), "A locked descendant keeps its earlier circles learned.")
	_expect(tree.toggle_lock("blood_burst_3"), "The last circle can be unlocked.")
	tree.reconcile(10.0)
	_expect(not tree.learned.has("blood_burst_3") and not tree.learned.has("blood_burst_2"), "Unlocked chain is removed below threshold.")



func _test_progression_budget_and_stages() -> void:
	var tree := MutationTree.new()
	for pair in [[0.0, 0], [24.99, 0], [25.0, 1], [29.99, 1], [30.0, 2], [40.0, 4], [55.0, 7], [70.0, 10], [85.0, 13], [100.0, 16]]:
		_expect(tree.points(pair[0]) == pair[1], "Point budget matches the +5 progression boundary.")
	var expected_roots := [
		["muscle_memory", "power_strike"], ["claws", "blood_burst"],
		["hypertrophy", "active_claws"], ["bone_armor", "discharge"], ["synapses", "recycling"]
	]
	for stage_index in range(5):
		var stability := 30.0 + stage_index * 15.0
		var roots := 0
		for row in Catalog.all():
			if int(row[3]) == 0 and tree.can_upgrade(str(row[0]), 100.0, stability):
				roots += 1
		_expect(roots == (stage_index + 1) * 2, "Exactly two branches open at each stability stage.")
		for skill_id in expected_roots[stage_index]:
			var row := Catalog.find(skill_id)
			_expect_float(Catalog.threshold(row), 25.0 + stage_index * 15.0, "Each stage shifts the first mutation threshold by 15.")
			_expect(tree.can_upgrade(skill_id, Catalog.threshold(row), stability), "A root is available at both exact thresholds.")
			_expect(not tree.can_upgrade(skill_id, Catalog.threshold(row) - 0.01, stability), "Mutation immediately below the root threshold cannot unlock it.")
			_expect(not tree.can_upgrade(skill_id, 100.0, stability - 0.01), "Mutation cannot bypass the stability gate.")
	_expect(tree.upgrade("muscle_memory", 25.0), "First point can buy the initial passive skill.")
	_expect(not tree.upgrade("power_strike", 25.0), "One point cannot buy two skills.")
	_expect(tree.upgrade("stabilizers", 30.0), "Second circle unlocks after +5 mutation.")
	_expect(tree.upgrade("combat_reflex", 35.0), "Third circle follows another +5 mutation.")
	var full := MutationTree.new()
	for row in Catalog.ACTIVE.filter(func(item: Array) -> bool: return not Catalog.alternative(str(item[0]))) + Catalog.PASSIVE.slice(0, 4):
		_expect(full.upgrade(str(row[0]), 100.0, 95.0), "The capped budget permits sixteen ordered upgrades.")
	_expect(full.points(100.0) == 0, "Sixteen upgrades exhaust the budget.")
	_expect(not full.upgrade("adrenaline", 100.0, 95.0), "A seventeenth upgrade is refused.")


func _test_hybrid_stage_gates() -> void:
	var tree := MutationTree.new()
	for skill_id in ["muscle_memory", "stabilizers", "combat_reflex", "claws", "blood_scent"]:
		_expect(tree.upgrade(skill_id, 50.0, 45.0), "Each regular parent circle uses its existing point.")
	_expect(not tree.is_active("killer_instinct", 50.0, 45.0), "One incomplete branch cannot activate a hybrid.")
	_expect(tree.upgrade("adrenaline", 50.0, 45.0), "Completing both branches uses the sixth point.")
	_expect(tree.points(50.0) == 0, "The fixture has no spare point for a separate hybrid purchase.")
	_expect(tree.is_active("killer_instinct", 50.0, 45.0), "The hybrid activates automatically with two full branches.")
	_expect(not tree.can_upgrade("killer_instinct", 50.0, 45.0), "An automatic bonus cannot consume another point.")
	_expect(not tree.is_active("killer_instinct", 49.99, 45.0), "The bonus disables below its later branch's last-circle mutation.")
	_expect(not tree.is_active("killer_instinct", 50.0, 44.99), "The bonus respects the later branch's stability gate.")
	_expect(tree.toggle_lock("adrenaline"), "The later branch can remain learned below mutation.")
	tree.reconcile(49.0)
	_expect(not tree.is_active("killer_instinct", 49.0, 45.0), "Retained learned parents cannot bypass the mutation gate.")
	_expect(tree.is_active("killer_instinct", 50.0, 45.0), "A retained full pair restores its derived bonus.")
	for row in Catalog.PASSIVE:
		if int(row[3]) < 3:
			tree.learned[str(row[0])] = true
	for hybrid_id in Catalog.HYBRID_PARENTS:
		var row := Catalog.find(str(hybrid_id))
		_expect(tree.is_active(str(hybrid_id), Catalog.threshold(row), Catalog.required_stability(row)), "Every adjacent full pair activates its hybrid at its exact gates.")
	tree.learned["killer_instinct"] = true
	tree.locked["killer_instinct"] = true
	tree.reconcile(100.0)
	_expect(not tree.learned.has("killer_instinct") and not tree.locked.has("killer_instinct"), "Legacy purchased/locked hybrid state is removed without another charge.")


func _test_ampule_notification_and_antidote() -> void:
	var runtime := Runtime.new()
	var notifications := [0]
	runtime.skill_available.connect(func() -> void: notifications[0] += 1)
	runtime.absorb_mutagen(8.0)
	_expect(not runtime.can_upgrade_skill("claws"), "Runtime guards unopened branches even at sufficient mutation.")
	runtime.add_control_ampule()
	runtime.add_control_ampule()
	var before: int = notifications[0]
	runtime.add_control_ampule()
	_expect(runtime.can_upgrade_skill("claws"), "The third ampule opens the second stage without mutation gain.")
	_expect(notifications[0] == before + 1, "Opening a stage announces a new available skill once.")
	runtime.call("_physics_process", 5.0)
	_expect(not runtime.is_control_lost(), "Raised stability lets the first loss finish safely.")
	_expect(runtime.upgrade_skill("claws"), "Runtime accepts an open branch.")
	runtime.toggle_skill_lock("claws")
	runtime.use_antidote()
	_expect(runtime.skill_learned("claws") and not runtime.has_skill("claws"), "A locked skill stays learned but inactive after antidote.")
	_expect(runtime.skill_requirements("claws")["branch_open"], "Antidote does not close the branch.")
	runtime.absorb_mutagen(2.0)
	_expect(runtime.has_skill("claws"), "Locked skill reactivates at its new mutation threshold.")
	_expect(not runtime.can_upgrade_skill("claws"), "Reactivation never offers a locked skill for purchase again.")
	runtime.free()
	var locked_runtime := Runtime.new()
	var locked_notifications := [0]
	locked_runtime.skill_available.connect(func() -> void: locked_notifications[0] += 1)
	locked_runtime.absorb_mutagen(5.0)
	locked_runtime.upgrade_skill("muscle_memory")
	locked_runtime.toggle_skill_lock("muscle_memory")
	var locked_before: int = locked_notifications[0]
	locked_runtime.use_antidote()
	locked_runtime.absorb_mutagen(2.0)
	_expect(locked_notifications[0] == locked_before, "Returning to a locked skill with no new candidate does not reopen the menu.")
	locked_runtime.free()


func _test_gas_mask_blocks_mutagen() -> void:
	var domain = InfectionDomain.new()
	domain.gas_mask_worn = true
	_expect_float(domain.absorb_mutagen(2.0), 0.0, "A worn gas mask takes no mutagen from a cloud.")
	_expect_float(domain.mutation, 0.0, "Mutation stays unchanged while the mask is worn.")
	domain.gas_mask_worn = false
	_expect_float(domain.absorb_mutagen(2.0), 10.0, "Mutagen is absorbed again once the mask is taken off.")


func _test_gas_mask_cooldown() -> void:
	var domain = InfectionDomain.new()
	_expect(domain.toggle_gas_mask() and domain.gas_mask_worn, "The mask goes on at once.")
	_expect(not domain.toggle_gas_mask() and domain.gas_mask_worn, "The mask cannot come off during the cooldown.")
	domain.tick(59.0)
	_expect(not domain.toggle_gas_mask(), "59 s after putting it on the mask is still locked.")
	domain.tick(1.0)
	_expect(domain.toggle_gas_mask() and not domain.gas_mask_worn, "After 60 s the mask can come off.")
	_expect_float(domain.gas_mask_cooldown_remaining, 60.0, "Taking it off starts a new 60 s cooldown.")
	_expect(not domain.toggle_gas_mask(), "The mask cannot go back on during that cooldown.")


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
	var mutation_before: float = domain.mutation
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
	_expect(domain.is_control_lost(), "Crossing the critical threshold starts loss inside absorb_mutagen.")
	_expect(domain.active_control_loss_stage == 1, "The first loss is stage one.")
	_expect_float(domain.control_loss_remaining, 2.0, "Stage one lasts two seconds.")
	_expect(not domain.is_escalated(), "The first loss is not yet an escalation.")
	domain.tick(2.0)
	_expect(not domain.is_control_lost(), "Control returns after the two-second loss.")
	_expect(not domain.defeated, "Returning control after the first loss does not end the run.")


func _test_contact_escalates_to_second_loss() -> void:
	var domain = _reach_first_control_loss()
	domain.tick(2.0)
	var mutation_before: float = domain.mutation
	_expect_float(domain.absorb_mutagen(1.0), 0.0, "Touching the cloud above the limit absorbs nothing.")
	_expect_float(domain.mutation, mutation_before, "Mutation stays at the limit when the cloud is touched.")
	_expect(domain.active_control_loss_stage == 2, "The next contact starts the second loss.")
	_expect_float(domain.control_loss_remaining, 5.0, "The second loss lasts five seconds.")
	_expect(domain.is_escalated(), "The second loss is escalated.")
	domain.tick(5.0)
	_expect(not domain.is_control_lost(), "Control returns after the five-second loss.")
	_expect(not domain.defeated, "Control returns after the second loss without defeat until the next contact.")


func _test_third_contact_defeats_without_loss() -> void:
	var domain = _reach_first_control_loss()
	domain.tick(2.0)
	domain.absorb_mutagen(1.0)
	domain.tick(5.0)
	domain.absorb_mutagen(0.5)
	_expect(domain.defeated, "The third contact with the cloud above the limit defeats the run.")
	_expect(not domain.is_control_lost(), "The third contact does not start a playable loss.")
	_expect(domain.active_control_loss_stage == 3, "The defeat is recorded as the third stage.")

	var combined = _reach_first_control_loss()
	combined.tick(7.0)
	_expect(not combined.defeated and not combined.is_control_lost(), "Time alone never defeats or starts a loss.")


func _test_loss_does_not_escalate_on_timer() -> void:
	var domain = _reach_first_control_loss()
	domain.tick(2.0)
	domain.tick(100.0)
	_expect(not domain.is_control_lost(), "Staying above the limit without contact never starts a second loss.")
	_expect(not domain.defeated, "Staying above the limit without contact never defeats the run.")
	_expect(domain.next_control_loss_stage == 2, "The second loss stays armed for the next contact.")


func _test_antidote_resets_escalation() -> void:
	var domain = _reach_first_control_loss()
	domain.tick(2.0)
	var before: float = domain.mutation
	_expect(domain.use_antidote(), "Antidote is usable after the first loss.")
	_expect_float(domain.mutation, before - 10.0, "Antidote keeps its ten-point reduction.")
	_expect(not domain.is_control_lost(), "An antidote that brings mutation under the limit leaves control with the player.")
	_expect(domain.next_control_loss_stage == 1, "Antidote resets escalation.")
	domain.absorb_mutagen(3.0)
	_expect(domain.active_control_loss_stage == 1, "The next crossing after an antidote is a first-stage loss again.")


func _test_antidote_resets_after_second_loss() -> void:
	var domain = _reach_first_control_loss()
	domain.tick(2.0)
	domain.absorb_mutagen(1.0)
	domain.tick(5.0)
	_expect(domain.use_antidote(), "Antidote is usable after the second loss.")
	_expect(domain.next_control_loss_stage == 1, "Antidote after the second loss resets escalation.")
	_expect(not domain.defeated, "Antidote prevents the third-contact defeat.")


func _test_emergency_antidote_during_control_loss() -> void:
	var domain = _reach_first_control_loss()
	var mutation_before: float = domain.mutation
	_expect(domain.use_antidote(), "Owner-approved emergency antidote works during control loss.")
	_expect_float(domain.mutation, mutation_before - 10.0, "Emergency antidote keeps the ten-point reduction.")
	_expect(not domain.is_control_lost() and domain.active_control_loss_stage == 0 and domain.next_control_loss_stage == 1, "Emergency antidote returns control and resets escalation.")


func _test_below_threshold_has_no_delayed_loss() -> void:
	var domain = InfectionDomain.new()
	domain.absorb_mutagen(6.0)
	_expect(not domain.is_control_lost(), "Exactly at the threshold has not crossed it.")
	domain.use_antidote()
	domain.tick(100.0)
	_expect(not domain.is_control_lost(), "Below-threshold mutation never builds a delayed loss.")


func _test_exact_threshold_and_immediate_crossing() -> void:
	var domain = InfectionDomain.new()
	domain.absorb_mutagen(6.0)
	_expect_float(domain.mutation, 30.0, "The fixture is exactly at the threshold.")
	domain.tick(100.0)
	_expect(not domain.is_control_lost(), "Equality is safe: loss needs a crossing above the boundary.")
	domain.absorb_mutagen(0.001)
	_expect(domain.is_control_lost(), "The smallest positive crossing triggers without a timer tick.")
	_expect_float(domain.control_loss_remaining, 2.0, "The instantaneous trigger has not consumed any loss duration.")


func _test_mutagen_pauses_during_control_loss() -> void:
	var domain = _reach_first_control_loss()
	var mutation_before: float = domain.mutation
	_expect_float(domain.absorb_mutagen(2.0), 0.0, "Mutagen does not accumulate during control loss.")
	_expect_float(domain.mutation, mutation_before, "Mutation remains unchanged during control loss.")


func _test_frame_steps_land_on_threshold() -> void:
	# 60 FPS absorption used to drift to 24.9999... and grant the first point one frame late.
	var domain = InfectionDomain.new()
	for _frame in range(300):
		domain.absorb_mutagen(1.0 / 60.0)
	_expect_float(domain.mutation, 25.0, "Frame-sized absorption lands exactly on the first threshold.")
	_expect(MutationTree.new().points(domain.mutation) == 1, "The first mutation point is granted at 25, not one frame later.")


func _reach_first_control_loss():
	var domain = InfectionDomain.new()
	domain.absorb_mutagen(6.2)
	return domain


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)


func _expect_float(actual: float, expected: float, message: String) -> void:
	_expect(is_equal_approx(actual, expected), "%s Expected %.4f, got %.4f." % [message, expected, actual])



func _test_path_feedback_without_spare_points() -> void:
	var tree := MutationTree.new()
	tree.learned["power_strike"] = true
	_expect(tree.points(25.0) == 0, "Fixture has spent its only point.")
	_expect(tree.path_reached("muscle_memory", 25.0, 30.0), "Reached first circle is visible even with no spare point.")
	_expect(not tree.can_upgrade("muscle_memory", 25.0, 30.0), "Path feedback cannot buy a skill without a point.")
	_expect(not tree.path_reached("blood_scent", 100.0, 95.0), "A later circle still requires its predecessor.")
	_expect(not tree.path_reached("claws", 100.0, 30.0), "A closed stability gate cannot light a branch.")
	_expect(tree.path_reached("claws", 40.0, 45.0), "The next stage fills through its first reachable skill.")


func _test_organic_ammo_hybrid() -> void:
	var tree := MutationTree.new()
	tree.learned["organic_ammo"] = true
	tree.locked["organic_ammo"] = true
	_expect(not Catalog.find("organic_ammo").is_empty(), "Organic Ammo closes the passive hybrid ring.")
	tree.reconcile(100.0)
	_expect(not tree.learned.has("organic_ammo") and not tree.locked.has("organic_ammo"), "Retired locked progress is cleaned safely.")


func _test_runtime_cast_control_guard() -> void:
	var runtime := Runtime.new()
	runtime.absorb_mutagen(6.0)
	runtime.upgrade_skill("power_strike")
	_expect(runtime.has_skill("power_strike"), "Fixture has an active learned ability.")
	runtime.absorb_mutagen(0.2)
	_expect(runtime.is_control_lost(), "The runtime observes the immediate crossing.")
	_expect(not runtime.cast_skill("power_strike"), "Hotbar cannot bypass control loss.")
	runtime.add_control_ampule()
	runtime.call("_physics_process", 2.0)
	_expect(runtime.cast_skill("power_strike"), "Casting returns after safe recovery.")
	var terminal := Runtime.new()
	var defeats := [0]
	terminal.defeated.connect(func() -> void: defeats[0] += 1)
	terminal.absorb_mutagen(6.2)
	terminal.call("_physics_process", 2.0)
	terminal.absorb_mutagen(0.2)
	terminal.call("_physics_process", 5.0)
	terminal.absorb_mutagen(0.2)
	_expect(terminal.is_defeated() and defeats[0] == 1, "Third contact publishes terminal defeat once.")
	terminal.absorb_mutagen(0.2)
	_expect(defeats[0] == 1, "Terminal defeat is published only once.")
	terminal.free()
	runtime.free()


# The critical threshold caps at 95 and mutation above it means control loss,
# so every skill threshold must sit below that cap.
func _test_last_circle_is_reachable() -> void:
	var highest := 0.0
	for row in Catalog.all():
		highest = maxf(highest, Catalog.threshold(row))
	_expect(highest < InfectionDomain.MAX_CRITICAL_THRESHOLD, "Every skill threshold is below the critical cap (%.0f)." % highest)
	for skill_id in ["reflex_arc", "battle_metabolism"]:
		var row := Catalog.find(skill_id)
		_expect(Catalog.threshold(row) <= 94.0, "%s opens below the critical cap." % skill_id)
