extends SceneTree
const RUNTIME := preload("res://game/features/infection/public/infection_runtime.gd")
const CATALOG := preload("res://game/features/infection/domain/mutation_catalog.gd")
var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_loadout()
	_test_timing()
	_test_dormant()
	_test_finals()
	_test_assimilation_antidote()
	print("Active skill state tests: %d failures" % failures)
	quit(failures)


func _runtime() -> Node:
	var runtime := RUNTIME.new()
	runtime._domain.mutation = 94.0
	runtime._domain.critical_threshold = 95.0
	runtime.set_physics_process(false)
	root.add_child(runtime)
	return runtime


func _test_loadout() -> void:
	var r := _runtime()
	_expect(r.equipped_skills() == ["", ""], "Exactly two empty slots before learning")
	_expect(r.upgrade_skill("blood_burst") and r.upgrade_skill("discharge"), "First two active roots are learned")
	_expect(r.equipped_skills() == ["blood_burst", "discharge"], "First two skills auto-equip in purchase order")
	_expect(r.upgrade_skill("power_strike"), "Third active can be learned")
	_expect(not r.can_cast_skill("power_strike"), "Unequipped third active cannot cast")
	_expect(r.assign_skill(0, "power_strike"), "A slot can choose another available family")
	_expect(not r.assign_skill(1, "power_strike"), "The same family cannot fill both slots")
	_expect(not r.assign_skill(0, "claws") and not r.assign_skill(2, "blood_burst"), "Reject passive and invalid slot")
	_expect(r.cast_skill("power_strike"), "Assigned skill can start recovery before upgrading")
	_expect(r.upgrade_skill("power_strike_2"), "An equipped family can upgrade")
	_expect(r.skill_cooldown_remaining("power_strike_2") == 5.0 and not r.can_cast_skill("power_strike_2"), "Upgrading cannot bypass an existing recovery timer")
	_expect(r.equipped_skills() == ["power_strike_2", "discharge"], "Upgrade automatically replaces the assigned icon/id")
	_expect(r.upgrade_skill("blood_burst_2"), "Unequipped family can upgrade")
	_expect(r.equipped_skills() == ["power_strike_2", "discharge"], "Upgrading another family preserves the manual selection")
	_expect("blood_burst_2" in r.assignable_skills() and "blood_burst" not in r.assignable_skills(), "Picker only lists the latest learned level")
	_expect(r.assign_skill(0, "") and r.assign_skill(0, "blood_burst_2"), "A slot can clear and reassign")
	r.free()


func _test_timing() -> void:
	var r := _runtime()
	r.upgrade_skill("blood_burst")
	r.upgrade_skill("power_strike")
	var done: Array[String] = []
	r.skill_cooldown_finished.connect(func(id: String) -> void: done.append(id))
	_expect(r.cast_skill("blood_burst") and r.cast_skill("power_strike"), "Independent cooldowns let both equipped skills cast")
	_expect(is_equal_approx(r.skill_cooldown_remaining("blood_burst"), 5.0), "Level1 cooldown is five seconds")
	r.reduce_skill_cooldowns(5.0)
	_expect(done.size() == 2 and r.can_cast_skill("blood_burst"), "Recovery completes exactly once per skill")
	r.reduce_skill_cooldowns(5.0)
	_expect(done.size() == 2, "No repeated ready facts")
	r.skill_cast.connect(func(id: String) -> void: r.report_skill_effect(id, 6.0))
	r.cast_skill("blood_burst")
	_expect(is_zero_approx(r.skill_cooldown_remaining("blood_burst")) and not r.can_cast_skill("blood_burst"), "Lasting effect blocks recast before cooldown begins")
	r.reduce_skill_cooldowns(100.0)
	_expect(is_equal_approx(r.skill_effect_remaining("blood_burst"), 6.0), "Passive cooldown acceleration never shortens the active effect")
	r.call("_tick_skills", 2.0, true)
	_expect(is_equal_approx(r.skill_effect_remaining("blood_burst"), 4.0), "Effect advances separately")
	r.report_skill_effect("blood_burst", 7.0)
	r.call("_tick_skills", 7.5, true)
	_expect(is_equal_approx(r.skill_cooldown_remaining("blood_burst"), 4.5), "Extension delays recovery; a coarse frame carries only its excess into cooldown")
	r.reduce_skill_cooldowns(4.5)
	_expect(done.size() == 3, "Extended effect produces one ready fact after recovery")
	_expect(CATALOG.cooldown("blood_burst_2") == 6.0 and CATALOG.cooldown("blood_infection") == 8.0, "Higher levels have six/eight second base recovery")
	r.tree.learned["synapses"] = true
	r.tree.learned["neurostim"] = true
	r.cast_skill("power_strike")
	r.call("_tick_skills", 6.0, true)
	_expect(is_equal_approx(r.skill_cooldown_remaining("power_strike"), 3.5), "Thirty-percent Neurostimulation applies to recovery after the effect")
	r.free()


func _test_dormant() -> void:
	var r := _runtime()
	r.upgrade_skill("blood_burst")
	r.upgrade_skill("blood_burst_2")
	r.upgrade_skill("blood_infection")
	r.toggle_skill_lock("blood_infection")
	r.upgrade_skill("discharge")
	var learned_before: Dictionary = r.tree.learned.duplicate()
	r.antidote_preview()
	_expect(r.tree.learned == learned_before and r.equipped_skills()[0] == "blood_infection", "Antidote preview never edits the live loadout")
	r._domain.mutation = 10.0
	r.call("_emit_state_changes", 94.0)
	_expect(r.equipped_skills() == ["blood_infection", ""], "Locked dormant retains its slot while forgotten unpinned skill clears")
	_expect(not r.can_cast_skill("blood_infection"), "Dormant retained skill cannot cast")
	var done := [0]
	r.skill_cooldown_finished.connect(func(_id: String) -> void: done[0] += 1)
	r._domain.mutation = 94.0
	r.call("_emit_state_changes", 10.0)
	_expect(r.skill_cooldown_remaining("blood_infection") == 8.0 and not r.can_cast_skill("blood_infection"), "Reactivation starts a full level3 recovery")
	r.reduce_skill_cooldowns(7.99)
	_expect(done[0] == 0, "Reactivation remains silent before readiness")
	r.reduce_skill_cooldowns(0.02)
	_expect(done[0] == 1 and r.can_cast_skill("blood_infection"), "Reactivation emits exactly one ready cue")
	r.free()


func _test_finals() -> void:
	for ids in [["blood_burst", "blood_burst_2", "blood_burst_3", "blood_infection"], ["discharge", "discharge_2", "discharge_3", "storm_pulse"], ["power_strike", "power_strike_2", "power_strike_3", "predator_dash"], ["active_claws", "active_claws_2", "active_claws_3", "berserk"]]:
		for chosen in [2, 3]:
			var r := _runtime()
			_expect(not r.upgrade_skill(ids[chosen]), "A final requires both preceding ranks")
			r.upgrade_skill(ids[0])
			r.upgrade_skill(ids[1])
			_expect(r.upgrade_skill(ids[chosen]), "Either final choice can be purchased")
			_expect(not r.upgrade_skill(ids[5 - chosen]), "Final choices are mutually exclusive in both directions")
			_expect(r.equipped_skills()[0] == ids[chosen], "Alternative final follows its equipped family automatically")
			_expect(r.mutation_points() == 11, "Three ranks cost three points from the retained fourteen-point budget")
			r.free()


func _expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)


func _test_assimilation_antidote() -> void:
	var r := _runtime()
	r.tree.learned["recycling"] = true
	r.tree.learned["assimilation"] = true
	_expect(r.has_skill("assimilation"), "Assimilation fixture is active")
	var preview: Dictionary = r.antidote_preview()
	_expect(preview.after == 79.0, "Assimilation preview accounts for fifteen mutation")
	_expect(r.get_mutation() == 94.0 and r.tree.learned.has("assimilation"), "Preview never changes mutation or learned skills")
	_expect(r.use_antidote(), "Assimilation permits normal antidote use")
	_expect(r.get_mutation() == preview.after and r.mutation_points() == preview.points_after, "Application matches the preview mutation and point budget")
	for id in preview.forgotten:
		_expect(not r.tree.learned.has(id), "Preview correctly predicts forgotten skill: " + str(id))
	for id in preview.dormant:
		_expect(not r.has_skill(id), "Preview correctly predicts dormant skill: " + str(id))
	_expect(is_equal_approx(r.get_mutation(), 79.0), "An active Assimilation antidote removes fifteen mutation")
	_expect(not r.has_skill("assimilation"), "Antidote still deactivates passives below their thresholds")
	r.free()
