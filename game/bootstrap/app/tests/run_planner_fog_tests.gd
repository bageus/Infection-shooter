extends SceneTree
## Preference persistence, live/late zones, pause, reveal preservation and rebuilding.
const FOG := preload("res://game/bootstrap/app/planning_fog.gd")
const ZONE := preload("res://game/presentation/office_floor/public/props/darkness_zone.tscn")
const FILE := "user://planner_fog_toggle_test.cfg"
var failures := 0


func _init() -> void:
	call_deferred("_run")


func _ui() -> Control:
	var ui := Control.new()
	root.add_child(ui)
	var panel := PanelContainer.new()
	panel.name = "Panel"
	ui.add_child(panel)
	var box := VBoxContainer.new()
	box.name = "VBox"
	panel.add_child(box)
	var local_lights := CheckButton.new()
	local_lights.name = "LocalLights"
	box.add_child(local_lights)
	return ui


func _zone(permanent: bool, room: int = 0) -> Node3D:
	var zone := ZONE.instantiate() as Node3D
	zone.set("permanent", permanent)
	zone.set("room_id", room)
	zone.position = Vector3(0, 2.75, 0)
	root.add_child(zone)
	return zone


func _run() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(FILE))
	var ui := _ui()
	var permanent := _zone(true)
	var legacy := _zone(false)
	var room := _zone(false, 7)
	var hidden := _zone(true)
	hidden.hide()
	legacy.call("reveal")
	var fog := FOG.new()
	root.add_child(fog)
	fog.setup(ui, FILE)
	_check(fog.enabled and fog.button.button_pressed, "Fog defaults to on")
	fog.button.button_pressed = false
	_check(not permanent.get_node("Overlay").visible and not room.get_node("Overlay").visible, "Switch hides permanent and room darkness immediately")
	_check(not room.call("blocks_view", Vector3(0, 8, 6), Vector3(0, 0.5, 0)), "Disabled fog cannot block the hero view")
	room.call("_process", 1.0)
	room.call("configure_zone", Vector2(6, 6), 0.7, false)
	_check(not room.get_node("Overlay").visible, "Processing and rebuilding cannot restore disabled fog")
	var late := _zone(false, 8)
	var baked := ZONE.instantiate() as Node3D
	baked.scene_file_path = ""
	root.add_child(baked)
	await process_frame
	await process_frame
	_check(not late.get_node("Overlay").visible, "A zone loaded while disabled inherits the setting")
	_check(not baked.get_node("Overlay").visible, "A baked zone without a source scene path inherits the setting")
	var config := ConfigFile.new()
	_check(config.load(FILE) == OK and config.get_value("view", "fog_of_war", true) == false, "Switch persists the preference")
	paused = true
	fog.button.button_pressed = true
	_check(permanent.get_node("Overlay").visible and late.get_node("Overlay").visible, "Switch works while the planner pauses the tree")
	_check(not legacy.get_node("Overlay").visible, "An explored legacy zone stays revealed")
	_check(not hidden.visible, "An authored hidden zone stays hidden")
	paused = false
	fog.button.button_pressed = false
	fog.queue_free()
	await process_frame
	var restored := FOG.new()
	root.add_child(restored)
	restored.setup(ui, FILE)
	_check(not restored.enabled and not restored.button.button_pressed, "Restart restores disabled preference")
	restored.set_enabled(true)
	_check(permanent.get_node("Overlay").visible and room.get_node("Overlay").visible, "Re-enable restores room and permanent darkness")
	restored.queue_free()
	await process_frame
	config.set_value("view", "fog_of_war", "invalid")
	config.save(FILE)
	var fallback := FOG.new()
	root.add_child(fallback)
	fallback.setup(ui, FILE)
	_check(fallback.enabled, "Malformed preference falls back to on")
	fallback.queue_free()
	for node in [permanent, legacy, room, hidden, late, baked, ui]:
		node.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(FILE))
	print("Planner fog tests: %d failure(s)." % failures)
	quit(failures)


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error(label)
