extends RefCounted
## One switch on the Lighting tab: lamp housings are drawn in play for every lamp or for none.
## A map saves it as lamp_fixtures_v1; a map without the key restores "hidden".
const LAMP_FIXTURES := preload("res://game/presentation/office_floor/public/lamp_fixtures.gd")
const KEY := "lamp_fixtures_v1"
var controls: Node
var button: CheckButton


func setup(owner_controls: Node) -> void:
	controls = owner_controls
	button = CheckButton.new()
	button.name = "LampsVisibleInGame"
	button.text = "Светильники видны в игре"
	button.tooltip_text = "Один переключатель для всех светильников карты: показывать их корпуса в игре или оставить только свет."
	button.button_pressed = LAMP_FIXTURES.in_game
	var box: Node = controls.session.ui.get_node("Panel/VBox")
	box.add_child(button)
	box.move_child(button, box.get_node("Tabs").get_index() + 1)
	button.hide()
	button.toggled.connect(func(enabled: bool) -> void: apply(controls.session, enabled))


func update_catalog() -> void:
	button.visible = controls.catalog.active_catalog == controls.catalog.lighting_catalog


static func capture(session: Variant) -> bool:
	return LAMP_FIXTURES.in_game


static func apply(session: Variant, enabled: bool) -> void:
	LAMP_FIXTURES.in_game = enabled
	for lamp: Node in (Engine.get_main_loop() as SceneTree).get_nodes_in_group("planner_lights"):
		lamp.call("refresh_fixture")


static func restore(session: Variant, raw: Variant) -> void:
	var enabled: bool = raw is bool and raw
	apply(session, enabled)
	var panel: Variant = session.get("controls") if session is Object else null
	if panel != null and panel.lamp_visibility.button != null:
		panel.lamp_visibility.button.set_pressed_no_signal(enabled)
