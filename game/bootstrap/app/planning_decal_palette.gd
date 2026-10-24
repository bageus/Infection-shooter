extends RefCounted
## Decal category/filter UI; surface marks reuse blood placement, attachment and undo.
const CATALOG := preload("res://game/presentation/office_floor/public/surface_decor_catalog.gd")
var controls: Node
var panel: VBoxContainer
var filters: HFlowContainer
var category := "blood"
var material := "all"
var _category_buttons: Array[Button] = []
var _material_buttons: Array[Button] = []


func setup(owner_controls: Node) -> void:
	controls = owner_controls
	panel = VBoxContainer.new()
	panel.name = "DecalCategories"
	var box: Node = controls.palette.get_parent()
	box.add_child(panel)
	box.move_child(panel, controls.blood_options.get_index())
	var row := HFlowContainer.new()
	panel.add_child(row)
	var group := ButtonGroup.new()
	for entry in [["Кровь", "blood"], ["Стекло", "glass"], ["Пол", "floor"], ["Стены", "walls"]]:
		_category_buttons.append(_button(row, str(entry[0]), str(entry[1]), group, choose_category))
	filters = HFlowContainer.new()
	panel.add_child(filters)
	var materials := ButtonGroup.new()
	for entry in [["Все", "all"], ["Повреждения", "floor_damage"], ["Потёртости", "floor_scuff"]]:
		_material_buttons.append(_button(filters, str(entry[0]), str(entry[1]), materials, choose_material))
	for kind: String in CATALOG.FLOOR_MATERIALS:
		_material_buttons.append(_button(filters, CATALOG.LABELS[kind], kind, materials, choose_material))
	panel.hide()


func _button(parent: Node, label: String, id: String, group: ButtonGroup, action: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.toggle_mode = true
	button.button_group = group
	button.set_meta("filter", id)
	button.pressed.connect(action.bind(id))
	parent.add_child(button)
	return button


func open() -> void:
	choose_category(category)


func choose_category(value: String) -> void:
	category = value
	_refresh()


func choose_material(value: String) -> void:
	material = value
	_refresh()


func _refresh() -> void:
	var entries: Array = controls.catalog.blood_catalog() if category == "blood" else CATALOG.entries(category, material)
	if category == "blood":
		entries = entries.filter(func(entry: Dictionary) -> bool: return not str(entry.blood_texture).begins_with("biomass_"))
	controls._enter_simple_catalog(entries, "DECALS | выберите декаль, поверхность и размер")
	controls.blood_options.show()
	panel.show()
	filters.visible = category == "floor"
	for button in _category_buttons:
		button.set_pressed_no_signal(str(button.get_meta("filter")) == category)
	for button in _material_buttons:
		button.set_pressed_no_signal(str(button.get_meta("filter")) == material)
	if category != "blood":
		controls.blood_surface.select(1 if category in ["glass", "walls"] else 0)


func hide() -> void:
	if panel != null:
		panel.hide()
