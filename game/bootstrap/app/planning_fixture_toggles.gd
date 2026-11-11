extends RefCounted
## Palette switches for the automatic wall fixtures placed on save: light switches
## (1.25 m) and fire alarms with call points (alarm 2.5 m, call point 1.5 m).
## Both are off until chosen; a group that is off leaves everything placed alone.
const WALL_FIXTURES := preload("res://game/bootstrap/app/planning_wall_fixtures.gd")
var controls: Node
var switches: CheckButton
var fire: CheckButton
var clear_switches: Button
var clear_fire: Button
var clear_lights: Button


func setup(owner_controls: Node) -> void:
	controls = owner_controls
	switches = _toggle("AutoLightSwitches", "Авто: выключатели света",
		"При сохранении карты или слоя расставить выключатели света на стенах у дверей на высоте 1,25 м.")
	fire = _toggle("AutoFireAlarms", "Авто: пожарные оповещатели",
		"При сохранении карты или слоя расставить пожарные оповещатели (2,5 м) и пожарные кнопки (1,5 м): по одному на дверь.")
	clear_switches = _clear_button("ClearLightSwitches", "Очистить выключатели света", ["switch"], switches)
	clear_fire = _clear_button("ClearFireAlarms", "Очистить пожарные оповещатели", ["alarm", "call_point"], fire)
	clear_lights = Button.new()
	clear_lights.name = "ClearLights"
	clear_lights.text = "Очистить светильники"
	clear_lights.tooltip_text = "Удаляет с карты все светильники. Зоны темноты остаются."
	clear_lights.pressed.connect(clear_all_lights)
	var box: Node = controls.session.ui.get_node("Panel/VBox")
	var anchor := box.get_node("Tabs").get_index() + 1
	for control: Control in [switches, clear_switches, fire, clear_fire, clear_lights]:
		box.add_child(control)
		box.move_child(control, anchor)
		anchor += 1


func options() -> Dictionary:
	return {"switches": switches.button_pressed, "fire": fire.button_pressed}


func _toggle(node_name: String, label: String, tip: String) -> CheckButton:
	var button := CheckButton.new()
	button.name = node_name
	button.text = label
	button.tooltip_text = tip
	return button


func _clear_button(node_name: String, label: String, kinds: Array[String], toggle: CheckButton) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = label
	button.tooltip_text = "Удаляет с карты все автоматически расставленные объекты этой группы и выключает авто-расстановку, иначе при сохранении они вернутся. Объекты, поставленные вручную, остаются."
	button.pressed.connect(clear.bind(kinds, toggle))
	return button


## Removes the automatic fixtures of the given kinds; returns how many were removed.
func clear(kinds: Array[String], toggle: CheckButton) -> int:
	toggle.button_pressed = false
	var doomed: Array = controls.objects.placed.filter(func(node: Node) -> bool:
		return is_instance_valid(node) and node.has_meta(WALL_FIXTURES.META) and str(node.get_meta(WALL_FIXTURES.META)) in kinds)
	_delete(doomed)
	controls.status.text = "Удалено авто-объектов: %d. Авто-расстановка выключена." % doomed.size()
	return doomed.size()


## Removes every placed lamp (darkness zones stay); returns how many were removed.
func clear_all_lights() -> int:
	var doomed: Array = controls.objects.placed.filter(func(node: Node) -> bool:
		return is_instance_valid(node) and node.is_in_group("planner_lights"))
	_delete(doomed)
	controls.status.text = "Удалено светильников: %d." % doomed.size()
	return doomed.size()


func _delete(nodes: Array) -> void:
	for node: Node3D in nodes:
		controls.session.edit_history.call("record_deleted", node)
		controls.objects._delete_node(node)
