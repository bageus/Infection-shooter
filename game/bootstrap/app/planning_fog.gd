extends Node
## Planner-only preview preference; gameplay always enables authored fog.
const FILE := "user://planner_settings.cfg"
var session: Node
var enabled := true
var button: CheckButton
var _file := FILE
var _ui: Control


func setup(ui: Control, settings_file: String = FILE) -> void:
	_file = settings_file
	_ui = ui
	ui.visibility_changed.connect(_apply_all)
	var config := ConfigFile.new()
	if config.load(_file) == OK:
		var value: Variant = config.get_value("view", "fog_of_war", true)
		enabled = value if value is bool else true
	button = CheckButton.new()
	button.name = "FogOfWarToggle"
	button.text = "Туман войны (затемнение)"
	button.tooltip_text = "Показывать затемнение комнат только в режиме планирования. В игре затемнение всегда включено. Выбор предпросмотра сохраняется между запусками."
	var box := ui.get_node("Panel/VBox")
	box.add_child(button)
	box.move_child(button, box.get_node("LocalLights").get_index() + 1)
	button.toggled.connect(set_enabled)
	get_tree().node_added.connect(_on_node_added)
	set_enabled(enabled, false)


func set_enabled(value: bool, persist: bool = true) -> void:
	enabled = value
	button.set_pressed_no_signal(enabled)
	_apply_all()
	if not enabled and session != null and is_instance_valid(session.objects.selected) and session.objects.selected.is_in_group("darkness_zone"):
		session.objects._reset_selection()
	if persist:
		var config := ConfigFile.new()
		config.load(_file)
		config.set_value("view", "fog_of_war", enabled)
		var error := config.save(_file)
		if error != OK:
			push_warning("Unable to save fog-of-war preference: %s" % error_string(error))


func _apply_all() -> void:
	for zone in get_tree().get_nodes_in_group("darkness_zone"):
		_apply_zone(weakref(zone))


func _on_node_added(node: Node) -> void:
	# Wait for _ready to build the overlay, including zones packed into baked maps.
	if node.has_method("set_fog_of_war_enabled"):
		_apply_zone.call_deferred(weakref(node))


func _apply_zone(reference: WeakRef) -> void:
	var zone := reference.get_ref() as Node
	if is_instance_valid(zone) and not zone.is_queued_for_deletion() and zone.has_method("set_fog_of_war_enabled"):
		zone.call("set_fog_of_war_enabled", enabled if _ui.is_visible_in_tree() else true)


func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)
