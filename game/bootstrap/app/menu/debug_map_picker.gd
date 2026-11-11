extends RefCounted
## Debug main-menu map dialog section: a list of the maps from debug_map_list.gd and a load button.

const LIST := preload("res://game/bootstrap/app/menu/debug_map_list.gd")
const STYLE := preload("res://game/bootstrap/app/menu/menu_style.gd")


## Adds the list and the load button to a menu dialog; loading starts the map straight in the planner.
static func build(view: Control, layout: VBoxContainer) -> void:
	var rows: Array = LIST.entries()
	var list := ItemList.new()
	list.custom_minimum_size.y = 260
	layout.add_child(list)
	for row: Dictionary in rows:
		var suffix: String = " (" + view.text("shippedMap") + ")" if row.shipped else ""
		list.add_item(str(row.label) + suffix)
	if rows.is_empty():
		list.hide()
		layout.add_child(STYLE.label(view.text("noSavedMaps"), roundi(14 * view.preferences.values.text_scale)))
	else:
		list.select(0)
	var load_button := STYLE.button(view.text("loadSelected"), func() -> void:
		var selected := list.get_selected_items()
		if not selected.is_empty():
			view.dispatch("plan_map:" + rows[selected[0]].path))
	load_button.disabled = rows.is_empty()
	layout.add_child(load_button)
	layout.add_child(STYLE.button(view.text("back"), view.close_dialog))
