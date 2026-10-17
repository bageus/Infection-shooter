extends SceneTree
const RUNTIME := preload("res://game/features/infection/public/infection_runtime.gd")
const UI := preload("res://game/bootstrap/app/mutation_tree_ui.gd")
const BINDINGS := preload("res://game/bootstrap/app/menu/control_bindings.gd")
const TEXT := preload("res://game/bootstrap/app/mutation_text.gd")
var failures := 0

func _init() -> void: call_deferred("_run")

func _run() -> void:
	var runtime := RUNTIME.new()
	root.add_child(runtime)
	runtime.set_physics_process(false)
	runtime._domain.mutation = 94.0
	runtime._domain.critical_threshold = 95.0
	var ui := UI.new()
	root.add_child(ui)
	ui.configure(runtime)
	var slots := ui.content.find_children("SkillSlot*", "MenuButton", true, false)
	_expect(slots.size() == 2 and slots[0].disabled and slots[1].disabled, "Two dimmed selection slots before learning")
	_expect(ui.skill_bar.circles.size() == 2, "HUD always has exactly two equipped slots")
	runtime.upgrade_skill("blood_burst")
	runtime.upgrade_skill("discharge")
	runtime.upgrade_skill("power_strike")
	await process_frame
	slots = ui.content.find_children("SkillSlot*", "MenuButton", true, false)
	_expect(not slots[0].disabled and slots[0].icon != null, "Owned skill shows its icon in the selector")
	var popup: PopupMenu = slots[0].get_popup()
	for index in popup.item_count:
		if popup.get_item_text(index) == TEXT.skill_name("power_strike"):
			popup.id_pressed.emit(popup.get_item_id(index))
	_expect(runtime.equipped_skills() == ["power_strike", "discharge"], "Picker actually changes authoritative slot state")
	runtime.upgrade_skill("power_strike_2")
	runtime.upgrade_skill("predator_dash")
	_expect(ui.skill_bar.circles[0].skill_id == "predator_dash", "HUD follows alternative final upgrade automatically")
	_expect(not runtime.can_upgrade_skill("power_strike_3"), "Unchosen final cannot be purchased through UI")
	runtime.upgrade_skill("blood_burst_2")
	runtime.upgrade_skill("blood_burst_3")
	var final_lock: Button
	var alternative: Button
	for button in ui.content.find_children("*", "Button", true, false):
		if button.get_meta("lock_skill_id", "") == "blood_burst_3": final_lock = button
		if button.get_meta("skill_id", "") == "blood_infection": alternative = button
	_expect(final_lock != null and alternative != null and not final_lock.get_rect().intersects(alternative.get_rect()), "Final rank lock does not overlap the alternative choice")
	runtime.toggle_skill_lock("predator_dash")
	runtime._domain.mutation = 10.0
	runtime.call("_emit_state_changes", 94.0)
	_expect(ui.skill_bar.circles[0].skill_id == "predator_dash" and not ui.skill_bar.circles[0].castable, "Dormant locked slot/icon stays visible and inactive")
	_test_bindings()
	ui.queue_free()
	runtime.queue_free()
	await process_frame
	print("Active loadout UI tests: %d failures" % failures)
	quit(failures)

func _test_bindings() -> void:
	var controls := BINDINGS.new()
	_expect(controls.values.camera_left.code == KEY_Z and controls.values.camera_right.code == KEY_X and controls.values.skill_1.code == KEY_Q and controls.values.skill_2.code == KEY_E, "Default camera Z/X and skills Q/E")
	_expect(not controls.values.has("skill_3") and not controls.values.has("skill_4"), "Obsolete slots are absent from settings")
	var config := ConfigFile.new()
	for pair in [["camera_left", KEY_Q], ["camera_right", KEY_E], ["skill_1", KEY_4], ["skill_2", KEY_5]]:
		config.set_value("controls_v1", pair[0], {"kind": "key", "code": pair[1]})
	controls.load_config(config)
	_expect(controls.values.skill_1.code == KEY_Q and controls.values.camera_left.code == KEY_Z, "Saved original defaults migrate to the new scheme")
	config.set_value("controls_v1", "melee", {"kind": "key", "code": KEY_Z})
	controls.load_config(config)
	_expect(controls.values.melee.code == KEY_Z and controls.values.camera_left.code == KEY_Q, "A custom key conflicting with new defaults survives migration")
	config.set_value("controls_v1", "melee", {"kind": "key", "code": KEY_C})
	config.set_value("controls_v1", "camera_left", {"kind": "key", "code": KEY_H})
	config.set_value("controls_v1", "camera_right", {"kind": "key", "code": KEY_J})
	controls.load_config(config)
	_expect(controls.values.camera_left.code == KEY_H and controls.values.skill_1.code == KEY_4, "Custom bindings remain intact")
	controls.save_config(config)
	controls.load_config(config)
	_expect(controls.values.camera_left.code == KEY_H, "Custom layout survives save/load under version2")
	controls.apply()
	_expect(not InputMap.has_action("skill_3") and not InputMap.has_action("skill_4"), "Obsolete inputs are removed at apply")

func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
