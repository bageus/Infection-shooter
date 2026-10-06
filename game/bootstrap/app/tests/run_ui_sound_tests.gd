extends SceneTree

const SFX := preload("res://game/core/audio/public/sound_events.gd")
const MENU := preload("res://game/bootstrap/app/menu/front_end.tscn")
const TREE_UI := preload("res://game/bootstrap/app/mutation_tree_ui.gd")
const INFECTION := preload("res://game/features/infection/public/infection_runtime.gd")
var failures := 0


class Host:
	extends Node
	@warning_ignore("unused_private_class_variable")
	var _mutation_menu_open := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var frontend := MENU.instantiate()
	root.add_child(frontend)
	await process_frame
	var menu: Control = frontend.get_node("Menu")
	var master := AudioServer.get_bus_index(&"Master")
	var saved_mute := AudioServer.is_bus_mute(master)
	var saved_volume := AudioServer.get_bus_volume_db(master)
	AudioServer.set_bus_mute(master, false)
	AudioServer.set_bus_volume_db(master, 0)
	menu.preferences.values.sound = true
	menu.preferences.values.volume = 0.4
	menu.buttons[0].mouse_entered.emit()
	_check(_count(menu, &"menu_hover") == 1, "Menu item hover creates one non-positional cue")
	menu.buttons[1].mouse_entered.emit()
	_check(_count(menu, &"menu_hover") == 1, "Disabled menu item is silent")
	menu.preferences.values.sound = false
	menu.buttons[2].mouse_entered.emit()
	_check(_count(menu, &"menu_hover") == 1, "Menu sound preference disables hover")
	menu.preferences.values.sound = true
	menu.activate("settings")
	await process_frame
	var modal: Control = menu.modal
	var dialog_buttons := modal.find_children("*", "Button", true, false)
	_check(not dialog_buttons.is_empty(), "Settings exposes controls")
	var before := _count(menu, &"menu_hover")
	for button in dialog_buttons:
		if button.name != "SoundToggle":
			button.mouse_entered.emit()
	_check(_count(menu, &"menu_hover") == before, "Settings buttons are silent on hover")
	modal.settings.tabs.current_tab = 3
	modal.find_child("SoundToggle", true, false).mouse_entered.emit()
	_check(_count(menu, &"menu_hover") == before + 1, "Only audio toggle has settings hover sound")
	frontend.queue_free()
	await process_frame
	await _test_mutation_tree()
	AudioServer.set_bus_mute(master, saved_mute)
	AudioServer.set_bus_volume_db(master, saved_volume)
	print("UI sound tests: %d failure(s)." % failures)
	quit(failures)


func _test_mutation_tree() -> void:
	var host := Host.new()
	root.add_child(host)
	var runtime := INFECTION.new()
	host.add_child(runtime)
	runtime.set_physics_process(false)
	runtime._domain.mutation = 35.0
	runtime._domain.critical_threshold = 45.0
	var ui := TREE_UI.new()
	root.add_child(ui)
	ui.configure(runtime)
	ui.open_tree()
	_check(paused, "Mutation tree pauses gameplay")
	var skill := _tree_button(ui.content, "skill_id", "acid_spit")
	_check(skill != null and not skill.disabled, "A real mutation skill is available")
	if skill != null:
		_check(skill.tooltip_text.is_empty(), "Skill circle has no plain engine tooltip")
		_check(skill.icon != null and skill.text.is_empty(), "Skill circle shows its atlas icon")
		skill.mouse_entered.emit()
		_check(_count(ui, &"mutation_hover") == 1 and _count(ui, &"menu_hover") == 0, "Skill hover uses a distinct cue")
		_check(ui.card.visible and ui.card.anchor_id == "acid_spit", "Skill hover opens the detail card")
		var card_text := ""
		for label: Label in ui.card.find_children("*", "Label", true, false):
			card_text += label.text + "\n"
		_check(card_text.contains("ACID SPIT") and card_text.contains("Leave a corrosive acid pool."), "Detail card shows the skill name and description")
		_check(card_text.contains("CLICK TO LEARN") and card_text.contains("Mutation"), "Detail card shows status and requirements")
		_check(ui.window.get_global_rect().encloses(ui.card.get_global_rect()), "Detail card stays on screen")
		skill.mouse_exited.emit()
		_check(not ui.card.visible, "Leaving the circle hides the detail card")
		skill.mouse_entered.emit()
		skill.pressed.emit()
		_check(runtime.skill_learned("acid_spit"), "Click still buys the skill")
		_check(_count(ui, &"mutation_click") == 1, "Click cue survives synchronous UI rebuild")
		await process_frame
		_check(ui.card.visible and ui.card.anchor_id == "acid_spit", "Detail card follows the rebuilt circle after buying")
	var lock := _tree_button(ui.content, "lock_skill_id", "acid_spit")
	_check(lock != null, "Learned skill has a lock")
	if lock != null:
		lock.pressed.emit()
		_check(runtime.skill_locked("acid_spit") and _count(ui, &"mutation_lock") == 1, "Lock transition plays its own cue")
	var unlock := _tree_button(ui.content, "lock_skill_id", "acid_spit")
	if unlock != null:
		unlock.pressed.emit()
		_check(not runtime.skill_locked("acid_spit") and _count(ui, &"mutation_unlock") == 1, "Unlock transition plays the reverse cue")
	else:
		_check(false, "Locked skill exposes an unlock control")
	var disabled := _tree_button(ui.content, "skill_id", "acid_spit")
	if disabled != null:
		var before := _count(ui, &"mutation_hover")
		disabled.mouse_entered.emit()
		disabled.pressed.emit()
		_check(_count(ui, &"mutation_hover") == before, "Inactive/disabled skills are silent")
		_check(_count(ui, &"mutation_click") == 1, "Disabled skill does not play a click cue")
	_check(AudioServer.get_bus_index(&"UI") >= 0 and AudioServer.get_bus_effect_count(AudioServer.get_bus_index(&"UI")) == 0, "UI bus is dry without room reverb")
	for child in ui.get_children():
		if child is AudioStreamPlayer:
			_check(child.bus == &"UI" and child.process_mode == Node.PROCESS_MODE_ALWAYS, "Cues play during pause and obey the shared mix")
	var lock_stream: AudioStreamWAV = SFX.UI_EVENTS[&"mutation_lock"][0]
	var unlock_stream: AudioStreamWAV = SFX.UI_EVENTS[&"mutation_unlock"][0]
	_check(lock_stream.data.size() == unlock_stream.data.size(), "Lock and unlock have matching lengths")
	var reversed := true
	for index in range(0, lock_stream.data.size(), 2):
		var other := lock_stream.data.size() - 2 - index
		reversed = reversed and lock_stream.data[index] == unlock_stream.data[other] and lock_stream.data[index + 1] == unlock_stream.data[other + 1]
	_check(reversed, "Unlock is the exact reversed PCM lock cue")
	ui.close_tree()
	_check(not ui.card.visible, "Closing the tree hides the detail card")
	ui.queue_free()
	host.queue_free()
	await process_frame
	_check(get_node_count_in_group(SFX.UI_GROUP) == 0, "Freeing UI releases its voices")


func _tree_button(parent: Node, key: String, skill_id: String) -> Button:
	for node in parent.find_children("*", "Button", true, false):
		if node.get_meta(key, "") == skill_id and not node.is_queued_for_deletion():
			return node
	return null


func _count(parent: Node, event: StringName) -> int:
	var count := 0
	for child in parent.get_children():
		if child.is_in_group(StringName("ui_sfx_" + String(event))):
			count += 1
	return count


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
