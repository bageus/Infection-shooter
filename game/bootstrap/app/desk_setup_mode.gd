extends Node

# Local desk coordinates are the single source of truth for zones and templates.
const WORKSTATIONS := preload("res://game/bootstrap/app/workstation_templates.gd")
const VISUALS := preload("res://game/bootstrap/app/desk_setup_visuals.gd")
const ZONE_RULES := preload("res://game/bootstrap/app/desk_setup_zone_rules.gd")
const TEMPLATE_ACTIONS := preload("res://game/bootstrap/app/desk_setup_template_actions.gd")
const ZONE_FORM := preload("res://game/bootstrap/app/desk_setup_zone_form.gd")
const ZONE_ACTIONS := preload("res://game/bootstrap/app/desk_setup_zone_actions.gd")
const MODEL_ROOT := "res://models/objects/enviroments/"

var planner: Node
var desk: Node3D
var dragged: Node3D
var dragging_zone := false
var zone_drag_offset := Vector2.ZERO
var active := false
var saved_camera := Transform3D.IDENTITY
var zones: Array[Dictionary] = []
var stations: Array = []
var zone_index := -1
var front := 0
var placing_zone := false
var chair_positioning := false
var chair_model: OptionButton
var panel: PanelContainer
var scroll: ScrollContainer
var help_panel: PanelContainer
var zone_list: VBoxContainer
var zone_items: VBoxContainer
var zone_form: Control
var model_list: ItemList
var template_list: OptionButton
var template_name: LineEdit
var width_field: SpinBox
var depth_field: SpinBox
var status: Label
var front_button: Button
var markers: Node3D
var models: Array[String] = []
var shown_category := ""

func configure(owner_planner: Node, planning_ui: Control) -> void:
	planner = owner_planner
	scroll = ScrollContainer.new()
	scroll.name = "DeskSetupScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	planning_ui.add_child(scroll)
	scroll.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel = PanelContainer.new()
	panel.name = "DeskSetupPanel"
	panel.custom_minimum_size = Vector2(330, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	scroll.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var header := HBoxContainer.new()
	box.add_child(header)
	var title := Label.new()
	title.text = "DESK SETUP | zones and objects"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_button(header, "?", _toggle_help)
	front_button = _button(box, "Front: seated side", _switch_front)
	var zone_scroll := ScrollContainer.new()
	zone_scroll.custom_minimum_size.y = 105
	zone_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(zone_scroll)
	zone_list = VBoxContainer.new()
	zone_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	zone_scroll.add_child(zone_list)
	zone_form = ZONE_FORM.new()
	box.add_child(zone_form)
	zone_form.connect("zone_changed", _on_zone_changed)
	_button(box, "Add zone (click table or floor)", _start_zone)
	var chair_row := HBoxContainer.new()
	box.add_child(chair_row)
	chair_model = OptionButton.new()
	for model in ["06_office_chair", "06_office_chair_2", "06_office_chair_2_fell"]:
		chair_model.add_item(model)
	chair_model.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chair_row.add_child(chair_model)
	_button(chair_row, "Chair position", _choose_chair_position)
	var sizes := HBoxContainer.new()
	box.add_child(sizes)
	width_field = _dimension(sizes, "Width", 0.65)
	depth_field = _dimension(sizes, "Depth", 0.45)
	width_field.value_changed.connect(_resize_zone)
	depth_field.value_changed.connect(_resize_zone)
	model_list = ItemList.new()
	model_list.custom_minimum_size.y = 140
	box.add_child(model_list)
	_button(box, "Place selected item (click zone)", _start_item)
	_button(box, "Random items in selected zone", _randomize)
	_button(box, "Remove zone items", _clear_zone)
	var item_caption := Label.new()
	item_caption.text = "Items in selected zone (remove one with ×)"
	box.add_child(item_caption)
	var item_scroll := ScrollContainer.new()
	item_scroll.custom_minimum_size.y = 85
	item_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(item_scroll)
	zone_items = VBoxContainer.new()
	zone_items.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_scroll.add_child(zone_items)
	template_name = LineEdit.new()
	template_name.placeholder_text = "Template name"
	box.add_child(template_name)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(status)
	_button(box, "Save template", _save)
	template_list = OptionButton.new()
	box.add_child(template_list)
	_button(box, "Apply selected template", _load)
	_button(box, "Back to level planner", close)
	scroll.hide()
	_build_help(planning_ui)
	get_viewport().size_changed.connect(_resize_menu)
	_resize_menu()
	markers = VISUALS.new()
	markers.name = "DeskSetupMarkers"
	planner.root.add_child(markers)
	markers.hide()
	_collect_models()

func _button(parent: Node, caption: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = caption
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _dimension(parent: HBoxContainer, caption: String, initial: float) -> SpinBox:
	var label := Label.new()
	label.text = caption
	parent.add_child(label)
	var field := SpinBox.new()
	field.min_value = 0.15
	field.max_value = 3.0
	field.step = 0.05
	field.value = initial
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(field)
	return field

func _build_help(planning_ui: Control) -> void:
	help_panel = PanelContainer.new()
	help_panel.name = "DeskSetupHelp"
	help_panel.custom_minimum_size.x = 280
	help_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	planning_ui.add_child(help_panel)
	var contents := VBoxContainer.new()
	help_panel.add_child(contents)
	var instructions := Label.new()
	instructions.text = "LMB drag zone  Move zone and contents\nArrows  Move selected zone (0.1 m)\nDirection  Aim zone arrow and models\nShift + LMB drag  Move one item\nDelete  Remove selected item\nRMB  Clear selection; drag to orbit\nСтол / Пол in zone row  Change surface\nWheel  Zoom in or out"
	contents.add_child(instructions)
	_button(contents, "ROTATE LEFT", _orbit_left)
	_button(contents, "ROTATE RIGHT", _orbit_right)
	_button(contents, "RESET VIEW", _reset_view)
	_button(contents, "CLOSE HELP", _toggle_help)
	help_panel.hide()

func _resize_menu() -> void:
	if scroll == null:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var menu_width := minf(360.0, viewport_size.x - 16.0)
	scroll.offset_left = -menu_width - 8.0
	scroll.offset_right = -8.0
	scroll.offset_top = 8.0
	scroll.offset_bottom = viewport_size.y - 8.0
	panel.custom_minimum_size.x = menu_width - 12.0
	help_panel.position = Vector2(maxf(8.0, viewport_size.x - menu_width - 304.0), 8.0)

func _toggle_help() -> void:
	help_panel.visible = not help_panel.visible

func _collect_models() -> void:
	ZONE_ACTIONS.refresh_models(self)

func open(target: Node3D) -> void:
	if active:
		close()
	desk = target
	dragged = null
	active = true
	placing_zone = false
	chair_positioning = false
	dragging_zone = false
	saved_camera = planner.camera.global_transform
	var profile: Dictionary = WORKSTATIONS.profile(_desk_path())
	stations = profile.get("stations", [])
	zones.clear()
	for station_index in stations.size():
		var station_value: Variant = stations[station_index]
		var station: Dictionary = station_value
		zones.append({"name": "Surface %d" % (station_index + 1), "required": false, "category": "Другие", "angle": float(station.get("angle", 0.0)), "x": float(station.get("x", 0.0)), "z": float(station.get("z", 0.0)), "width": float(station.get("zone_width", 0.65)), "depth": float(station.get("zone_depth", 0.35)), "height": float(station.get("grid_height", profile.get("height", 0.89))), "floor": false})
	if zones.is_empty():
		zones.append({"name": "Work surface 1", "required": false, "category": "Другие", "angle": 0.0, "x": 0.0, "z": 0.0, "width": 1.5, "depth": 0.85, "height": 0.89, "floor": false})
	front = 0
	zone_index = 0
	scroll.show()
	planner.ui.get_node("Panel").hide()
	planner.help.get_parent().get_parent().hide()
	planner.help_button.hide()
	markers.call("configure", desk, profile)
	markers.show()
	_refresh_zones()
	_refresh_templates()
	planner._clear_preview()
	planner._clear_selection_highlight()
	_reset_view()
	status.text = "Click a zone to select it; the desk stays fixed."

func close() -> void:
	if not active:
		return
	active = false
	placing_zone = false
	chair_positioning = false
	dragging_zone = false
	dragged = null
	planner.camera.global_transform = saved_camera
	scroll.hide()
	help_panel.hide()
	planner.ui.get_node("Panel").show()
	planner.help_button.show()
	markers.hide()
	markers.call("clear")
	desk = null
	planner._select(null)

func handle_input(event: InputEvent) -> bool:
	if not active:
		return false
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if _editing_text():
			get_viewport().gui_get_focus_owner().release_focus()
		else:
			close()
		return true
	if event is InputEventKey and event.pressed and not event.echo and not _editing_text():
		if zone_index >= 0 and event.keycode in [KEY_Q, KEY_E]:
			_rotate_zone(-15.0 if event.keycode == KEY_Q else 15.0)
			return true
		if event.keycode == KEY_DELETE and dragged != null:
			planner.placed.erase(dragged)
			dragged.queue_free()
			dragged = null
			_refresh_zone_items()
			return true
		if zone_index >= 0 and event.keycode in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]:
			var direction := Vector2.ZERO
			if event.keycode == KEY_LEFT: direction.x = -0.1
			if event.keycode == KEY_RIGHT: direction.x = 0.1
			if event.keycode == KEY_UP: direction.y = -0.1
			if event.keycode == KEY_DOWN: direction.y = 0.1
			_move_zone(zone_index, Vector2(float(zones[zone_index]["x"]), float(zones[zone_index]["z"])) + direction)
			return true
	if event is InputEventMouse:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			ZONE_ACTIONS.clear_selection(self)
		if scroll.get_global_rect().has_point(event.position) or (help_panel.visible and help_panel.get_global_rect().has_point(event.position)):
			return false # GUI receives the event; world input stays disabled.
		if event is InputEventMouseButton:
			if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP: _zoom_orbit(-0.4)
			if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN: _zoom_orbit(0.4)
			if event.pressed and event.button_index == MOUSE_BUTTON_LEFT and not event.alt_pressed:
				_click_world(event.position, event.shift_pressed)
			if not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				dragging_zone = false
		if event is InputEventMouseMotion:
			if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or (event.alt_pressed and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)):
				_orbit(event.relative)
			elif dragging_zone and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and zone_index >= 0:
				var local := _local_at(event.position, zones[zone_index])
				if local.is_finite():
					_move_zone(zone_index, Vector2(local.x, local.z) + zone_drag_offset)
			elif dragged != null and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and zone_index >= 0:
				_drag_item(event.position)
		return true
	return false # Let focused LineEdit and SpinBox controls receive keyboard input.

func _editing_text() -> bool:
	return template_name.has_focus() or width_field.get_line_edit().has_focus() or depth_field.get_line_edit().has_focus() or bool(zone_form.call("editing_text"))

func _click_world(screen: Vector2, pick_item: bool) -> void:
	dragged = null
	if chair_positioning:
		_place_chair_at(screen)
		return
	if placing_zone:
		_add_zone_at(screen)
		return
	if pick_item and not model_list.has_meta("placing"):
		var hit := planner._planned_object_at(screen) as Node3D
		if hit != null and str(hit.get_meta("planning_attachment", "")) == _desk_id():
			dragged = hit
			var slot := int(hit.get_meta("planning_zone", -1))
			if slot >= 0 and slot < zones.size():
				zone_index = slot
				_refresh_zones()
			status.text = "Drag the item inside the zone; Delete removes it."
			return
	var zone := zone_index if zone_index >= 0 and _point_in_zone(zone_index, screen) else _zone_at(screen)
	if zone >= 0:
		var was_placing := model_list.has_meta("placing")
		var picked := ""
		if was_placing and not model_list.get_selected_items().is_empty():
			picked = models[model_list.get_selected_items()[0]]
		zone_index = zone
		_refresh_zones()
		if was_placing:
			if model_list.has_meta("placing"):
				model_list.remove_meta("placing")
			if not picked.is_empty():
				_place_model(picked, _local_at(screen, zones[zone]))
		else:
			var local := _local_at(screen, zones[zone])
			zone_drag_offset = Vector2(float(zones[zone]["x"]) - local.x, float(zones[zone]["z"]) - local.z)
			dragging_zone = true

func _add_zone_at(screen: Vector2) -> void:
	var tabletop_height: float = float(markers.get("surface_height"))
	if zone_index >= 0 and not bool(zones[zone_index].get("floor", false)):
		tabletop_height = float(zones[zone_index].get("height", tabletop_height))
	var table_point := _project(screen, tabletop_height)
	var table_local := desk.to_local(table_point)
	var preview := {"x": table_local.x, "z": table_local.z, "width": 0.65, "depth": 0.45, "angle": 0.0, "floor": false}
	var on_table := table_local.is_finite() and ZONE_RULES._inside_surface(Vector2(table_local.x, table_local.z), preview, stations)
	var point := table_point if on_table else _project(screen, 0.0)
	if not point.is_finite():
		return
	var local: Vector3 = desk.to_local(point)
	var zone := {"name": "Zone %d" % (zones.size() + 1), "required": false, "category": "Другие", "angle": 0.0, "x": snappedf(local.x, 0.05), "z": snappedf(local.z, 0.05), "width": 0.65, "depth": 0.45, "height": tabletop_height if on_table else 0.0, "floor": not on_table}
	var center := ZONE_RULES.snap_to_neighbors(Vector2(zone["x"], zone["z"]), zone, zones, -1)
	zone["x"] = center.x
	zone["z"] = center.y
	if not ZONE_RULES._inside_surface(Vector2(zone["x"], zone["z"]), zone, stations):
		status.text = "Zone must fit on the selected surface."
		return
	zones.append(zone)
	zone_index = zones.size() - 1
	placing_zone = false
	_refresh_zones()

func _move_zone(index: int, target: Vector2) -> void:
	if ZONE_RULES.move_zone(desk, zones, index, target, stations, _attachments()):
		_refresh_zones()

func _choose_chair_position() -> void:
	ZONE_ACTIONS.choose_chair(self)

func _place_chair_at(screen: Vector2) -> void:
	ZONE_ACTIONS.place_chair(self, screen)

func _rotate_zone(amount: float) -> void:
	zone_form.call("turn_by", amount)

func _drag_item(screen: Vector2) -> void:
	var local := _local_at(screen, zones[zone_index])
	if not local.is_finite() or not _point_in_zone(zone_index, screen):
		return
	var previous := dragged.global_position
	dragged.global_position = desk.to_global(Vector3(local.x, desk.to_local(previous).y, local.z))
	var type_matches := ZONE_RULES.category_for(str(dragged.get_meta("planning_scene_path", "")).get_file().get_basename()) == str(zones[zone_index]["category"])
	if not type_matches or not ZONE_RULES.fits_zone(desk, zones[zone_index], dragged):
		dragged.global_position = previous
	else:
		var previous_slot := int(dragged.get_meta("planning_zone", -1))
		dragged.set_meta("planning_zone", zone_index)
		if previous_slot != zone_index:
			_refresh_zone_items()

func _orbit(relative: Vector2) -> void:
	markers.call("rotate_view", planner.camera, relative)

func _zoom_orbit(amount: float) -> void:
	markers.call("zoom_view", planner.camera, amount)

func _orbit_left() -> void:
	_orbit(Vector2(PI * 0.5 / 0.008, 0))

func _orbit_right() -> void:
	_orbit(Vector2(-PI * 0.5 / 0.008, 0))

func _reset_view() -> void:
	markers.call("reset_view", planner.camera)

func _project(screen: Vector2, height: float) -> Vector3:
	var origin: Vector3 = planner.camera.project_ray_origin(screen)
	var ray: Vector3 = planner.camera.project_ray_normal(screen)
	var plane := Plane(Vector3.UP, desk.to_global(Vector3.UP * height))
	var point: Variant = plane.intersects_ray(origin, ray)
	return point if point is Vector3 else Vector3(INF, INF, INF)

func _local_at(screen: Vector2, zone: Dictionary) -> Vector3:
	return desk.to_local(_project(screen, float(zone["height"])))

func _zone_at(screen: Vector2) -> int:
	for i in range(zones.size() - 1, -1, -1):
		if _point_in_zone(i, screen):
			return i
	return -1

func _point_in_zone(index: int, screen: Vector2) -> bool:
	var zone: Dictionary = zones[index]
	var local := _local_at(screen, zone)
	if not local.is_finite():
		return false
	var offset := Vector3(local.x - float(zone["x"]), 0, local.z - float(zone["z"])).rotated(Vector3.UP, -deg_to_rad(float(zone.get("angle", 0.0))))
	return absf(offset.x) <= float(zone["width"]) * 0.5 and absf(offset.z) <= float(zone["depth"]) * 0.5


func _desk_path() -> String:
	return str(desk.get_meta("planning_scene_path", ""))


func _desk_id() -> String:
	return str(desk.get_meta("planning_desk_id", ""))


func _place_model(model: String, local: Vector3) -> void:
	ZONE_ACTIONS.place_model(self, model, local)


func _attachments() -> Array[Node3D]:
	var attached: Array[Node3D] = []
	for object in planner.placed:
		if is_instance_valid(object) and str(object.get_meta("planning_attachment", "")) == _desk_id():
			attached.append(object)
	return attached


func _start_zone() -> void:
	placing_zone = true
	status.text = "Click the table or floor to set the zone centre."


func _toggle_surface_at(index: int) -> void:
	zone_index = index
	ZONE_ACTIONS.toggle_surface(self)
	_refresh_zones()

func _duplicate_zone_at(index: int) -> void:
	ZONE_ACTIONS.duplicate_zone(self, index)


func _start_item() -> void:
	if zone_index >= 0 and not model_list.get_selected_items().is_empty():
		model_list.set_meta("placing", true)
		status.text = "Click inside a highlighted zone to place the selected object."


func _remove_zone_at(index: int) -> void:
	if index < 0 or index >= zones.size():
		return
	zone_index = index
	_clear_zone()
	zones.remove_at(index)
	zone_index = mini(index, zones.size() - 1)
	for object in _attachments():
		if int(object.get_meta("planning_zone", -1)) > index:
			object.set_meta("planning_zone", int(object.get_meta("planning_zone")) - 1)
	_refresh_zones()


func _clear_zone() -> void:
	if zone_index >= 0:
		for object in ZONE_RULES.items_in_zone(desk, zones[zone_index], _attachments()):
			planner.placed.erase(object)
			object.queue_free()
	_refresh_zone_items()


func _randomize() -> void:
	ZONE_ACTIONS.randomize(self)


func _switch_front() -> void:
	front = 1 - front
	front_button.text = "Front: opposite side" if front else "Front: seated side"
	_refresh_markers()


func _select_zone(index: int) -> void:
	zone_index = index
	zone_form.show()
	model_list.mouse_filter = Control.MOUSE_FILTER_STOP
	for i in zone_list.get_child_count():
		var button := zone_list.get_child(i).get_child(0) as Button
		button.modulate = Color(1.0, 0.83, 0.48) if i == index else Color.WHITE
	var zone: Dictionary = zones[index]
	zone_form.call("display", zone)
	_collect_models()
	width_field.set_value_no_signal(float(zone["width"]))
	depth_field.set_value_no_signal(float(zone["depth"]))
	_refresh_zone_items()
	_refresh_markers()


func _on_zone_changed(zone_name: String, required: bool, angle: float, category: String) -> void:
	if zone_index < 0:
		return
	var zone: Dictionary = zones[zone_index]
	var previous_category := str(zone.get("category", "Другие"))
	if category != previous_category:
		for object in ZONE_RULES.items_in_zone(desk, zone, _attachments()):
			if ZONE_RULES.category_for(str(object.get_meta("planning_scene_path", "")).get_file().get_basename()) != category:
				status.text = "Remove incompatible items before changing the zone type."
				zone_form.call("display", zone)
				return
	var delta := angle - float(zone.get("angle", 0.0))
	if not is_zero_approx(delta):
		var proposed := zone.duplicate()
		proposed["angle"] = angle
		if not ZONE_RULES._inside_surface(Vector2(float(zone["x"]), float(zone["z"])), proposed, stations) or not ZONE_RULES.rotate_items(desk, zone, _attachments(), delta):
			status.text = "Zone or an item's centre would leave the surface."
			zone_form.call("display", zone)
			return
	zone["name"] = category if category != previous_category else (zone_name if not zone_name.is_empty() else "Zone %d" % (zone_index + 1))
	zone["required"] = required
	zone["angle"] = angle
	zone["category"] = category
	if category != previous_category:
		shown_category = ""
		_collect_models()
		zone_form.call("display", zone)
	(zone_list.get_child(zone_index).get_child(0) as Button).text = _zone_label(zone, zone_index)
	_refresh_zone_items()
	_refresh_markers()


func _resize_zone(_value: float) -> void:
	ZONE_ACTIONS.resize_zone(self)


func _refresh_zones() -> void:
	for child in zone_list.get_children():
		zone_list.remove_child(child)
		child.queue_free()
	for i in zones.size():
		zones[i]["slot"] = i
		var row := HBoxContainer.new()
		zone_list.add_child(row)
		var select := _button(row, _zone_label(zones[i], i), _select_zone.bind(i))
		select.clip_text = true
		select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		select.modulate = Color(1.0, 0.83, 0.48) if i == zone_index else Color.WHITE
		_button(row, "Копия", _duplicate_zone_at.bind(i))
		_button(row, "Пол" if bool(zones[i].get("floor", false)) else "Стол", _toggle_surface_at.bind(i))
		_button(row, "×", _remove_zone_at.bind(i))
	if zone_index >= 0:
		_select_zone(zone_index)
	else:
		_refresh_zone_items()
		_refresh_markers()


func _refresh_zone_items() -> void:
	ZONE_ACTIONS.refresh_items(self)


func _remove_zone_item(object: Node3D) -> void:
	if is_instance_valid(object):
		planner.placed.erase(object)
		object.queue_free()
	_refresh_zone_items()


func _zone_label(zone: Dictionary, index: int) -> String:
	var title := str(zone.get("name", "Zone %d" % (index + 1)))
	var category := str(zone.get("category", "Другие"))
	if title != category:
		title += " · " + category
	return "%s | %s | %d°" % [title, "обяз." if bool(zone.get("required", true)) else "необяз.", roundi(float(zone.get("angle", 0.0)))]


func _refresh_markers() -> void:
	markers.call("redraw", zones, zone_index, front)


func _save() -> void:
	TEMPLATE_ACTIONS.save(self)


func _refresh_templates() -> void:
	TEMPLATE_ACTIONS.refresh(self)


func _load() -> void:
	TEMPLATE_ACTIONS.load_selected(self)
