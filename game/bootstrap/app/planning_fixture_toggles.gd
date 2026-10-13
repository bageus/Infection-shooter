extends RefCounted
## Palette switches for the automatic wall fixtures placed on save: light switches
## (1.25 m) and fire alarms with call points (alarm 2.5 m, call point 1.5 m).
## Both are off until chosen; a group that is off leaves everything placed alone.
var controls: Node
var switches: CheckButton
var fire: CheckButton


func setup(owner_controls: Node) -> void:
	controls = owner_controls
	switches = _toggle("AutoLightSwitches", "Авто: выключатели света",
		"При сохранении карты или слоя расставить выключатели света на стенах у дверей на высоте 1,25 м.")
	fire = _toggle("AutoFireAlarms", "Авто: пожарные оповещатели",
		"При сохранении карты или слоя расставить пожарные оповещатели (2,5 м) и пожарные кнопки (1,5 м): по одному на дверь.")
	var box: Node = controls.session.ui.get_node("Panel/VBox")
	var anchor := box.get_node("Tabs").get_index() + 1
	for button in [switches, fire]:
		box.add_child(button)
		box.move_child(button, anchor)
		anchor += 1


func options() -> Dictionary:
	return {"switches": switches.button_pressed, "fire": fire.button_pressed}


func _toggle(node_name: String, label: String, tip: String) -> CheckButton:
	var button := CheckButton.new()
	button.name = node_name
	button.text = label
	button.tooltip_text = tip
	return button
