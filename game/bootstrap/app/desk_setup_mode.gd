extends Node

# Local desk coordinates are the single source of truth for zones and templates.
const WORKSTATIONS := preload("res://game/bootstrap/app/workstation_templates.gd")
const VISUALS := preload("res://game/bootstrap/app/desk_setup_visuals.gd")
const ZONE_RULES := preload("res://game/bootstrap/app/desk_setup_zone_rules.gd")
const TEMPLATE_FILES := preload("res://game/bootstrap/app/desk_setup_template_files.gd")
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
var next_zone_floor := false
var panel: PanelContainer
var scroll: ScrollContainer
var help_panel: PanelContainer
var zone_list: ItemList
var model_list: ItemList
var template_list: OptionButton
var template_name: LineEdit
var width_field: SpinBox
var depth_field: SpinBox
var status: Label
var front_button: Button
var markers: Node3D
var models: Array[String] = []


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
	zone_list = ItemList.new()
	zone_list.custom_minimum_size.y = 105
	zone_list.item_selected.connect(_select_zone)
	box.add_child(zone_list)
	_button(box, "Add zone (click table or floor)", _start_zone)
	_button(box, "Next zone: table / floor", _toggle_zone_surface)
	_button(box, "Selected zone: table / floor", _toggle_selected_surface)
	_button(box, "Remove selected zone", _remove_zone)
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
	template_name = LineEdit.new()
	template_name.placeholder_text = "Template name"
	box.add_child(template_name)
	_button(box, "Save template", _save)
	template_list = OptionButton.new()
	box.add_child(template_list)
	_button(box, "Apply selected template", _load)
	_button(box, "Back to level planner", close)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(status)
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
	instructions.text = "LMB drag zone  Move zone and contents\nArrows  Move selected zone (0.1 m)\nShift + LMB drag  Move one item\nDelete  Remove selected item\nRMB drag / Alt + LMB  Orbit table\nWheel  Zoom in or out"
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
	for group in ["03", "05", "06", "09", "11"]:
		var directory := DirAccess.open(MODEL_ROOT + group)
		if directory == null:
			continue
		for file in directory.get_files():
			if file.ends_with(".glb"):
				var name_part := file.get_basename()
				if group != "03" or name_part == "03_file_cabinet_smaller":
					models.append(name_part)
	models.sort()
	for model in models:
		model_list.add_item(model)


func open(target: Node3D) -> void:
	if active:
		close()
	desk = target
	dragged = null
	active = true
	placing_zone = false
	dragging_zone = false
	saved_camera = planner.camera.global_transform
	var profile: Dictionary = WORKSTATIONS._read("desks/" + WORKSTATIONS.desk_name(_desk_path()) + ".json")
	stations = profile.get("stations", [])
	zones.clear()
	for station_value in profile.get("stations", []):
		var station: Dictionary = station_value
		zones.append({"x": float(station.get("x", 0.0)), "z": float(station.get("z", 0.0)), "width": 1.5, "depth": 0.85, "height": float(profile.get("height", 0.89)), "floor": false})
	if zones.is_empty():
		zones.append({"x": 0.0, "z": 0.0, "width": 1.5, "depth": 0.85, "height": 0.89, "floor": false})
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
		if event.keycode == KEY_DELETE and dragged != null:
			planner.placed.erase(dragged)
			dragged.queue_free()
			dragged = null
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
	return template_name.has_focus() or width_field.get_line_edit().has_focus() or depth_field.get_line_edit().has_focus()


func _click_world(screen: Vector2, pick_item: bool) -> void:
	dragged = null
	if placing_zone:
		_add_zone_at(screen)
		return
	if pick_item and not model_list.has_meta("placing"):
		var hit := planner._planned_object_at(screen) as Node3D
		if hit != null and str(hit.get_meta("planning_attachment", "")) == _desk_id():
			dragged = hit
			var pivot := desk.to_local(hit.global_position)
			for i in zones.size():
				if absf(pivot.x - float(zones[i]["x"])) <= float(zones[i]["width"]) * 0.5 and absf(pivot.z - float(zones[i]["z"])) <= float(zones[i]["depth"]) * 0.5:
					zone_index = i
					_refresh_zones()
					break
			status.text = "Drag the item inside the zone; Delete removes it."
			return
	var zone := _zone_at(screen)
	if zone >= 0:
		zone_index = zone
		_refresh_zones()
		if model_list.has_meta("placing"):
			model_list.remove_meta("placing")
			var selected_items := model_list.get_selected_items()
			if not selected_items.is_empty():
				_place_model(models[selected_items[0]], _local_at(screen, zones[zone]))
		else:
			var local := _local_at(screen, zones[zone])
			zone_drag_offset = Vector2(float(zones[zone]["x"]) - local.x, float(zones[zone]["z"]) - local.z)
			dragging_zone = true


func _add_zone_at(screen: Vector2) -> void:
	var point := _project(screen, 0.0 if next_zone_floor else 0.89)
	if not point.is_finite():
		return
	var local: Vector3 = desk.to_local(point)
	zones.append({"x": local.x, "z": local.z, "width": 0.65, "depth": 0.45, "height": 0.0 if next_zone_floor else 0.89, "floor": next_zone_floor})
	zone_index = zones.size() - 1
	placing_zone = false
	_refresh_zones()


func _move_zone(index: int, target: Vector2) -> void:
	if ZONE_RULES.move_zone(desk, zones, index, target, stations, _attachments()):
		_refresh_zones()


func _drag_item(screen: Vector2) -> void:
	var local := _local_at(screen, zones[zone_index])
	if not local.is_finite() or _zone_at(screen) != zone_index:
		return
	var previous := dragged.global_position
	dragged.global_position = desk.to_global(Vector3(local.x, desk.to_local(previous).y, local.z))
	if _overlaps_attached(dragged):
		dragged.global_position = previous


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
		var zone: Dictionary = zones[i]
		var local := _local_at(screen, zone)
		if local.is_finite() and absf(local.x - float(zone["x"])) <= float(zone["width"]) * 0.5 and absf(local.z - float(zone["z"])) <= float(zone["depth"]) * 0.5:
			return i
	return -1


func _desk_path() -> String:
	return str(desk.get_meta("planning_scene_path", ""))


func _desk_id() -> String:
	return str(desk.get_meta("planning_desk_id", ""))


func _place_model(model: String, local: Vector3) -> void:
	var zone := zones[zone_index]
	var group := model.substr(0, 2)
	var path := MODEL_ROOT + group + "/" + model + ".glb"
	if not FileAccess.file_exists(path):
		return
	var existing: Array[Node3D] = []
	for object in planner.placed:
		if is_instance_valid(object) and object != desk and object.get_meta("planning_attachment", "") != _desk_id():
			existing.append(object)
	var occupied: Array[Rect2] = []
	for object in _attachments():
		var bounds: AABB = WORKSTATIONS._bounds(object)
		occupied.append(Rect2(Vector2(bounds.position.x, bounds.position.z), Vector2(bounds.size.x, bounds.size.z)).grow(0.025))
	var created: Array[Node3D] = []
	var random := RandomNumberGenerator.new()
	random.randomize()
	var entry := {"model": model, "x": local.x, "z": local.z, "jitter": 0.0, "floor": bool(zone["floor"])}
	WORKSTATIONS._add_item(entry, {"x": 0.0, "z": 0.0, "angle": 0.0}, float(zone["height"]), desk, planner.root, existing, created, occupied, random, Callable(planner, "_instantiate_asset"))
	for object in created:
		object.set_meta("planning_attachment", _desk_id())
		object.set_meta("planning_zone", zone_index)
		planner.placed.append(object)
	status.text = "Placed " + model if not created.is_empty() else "No room here; move the zone or choose a smaller item."


func _attachments() -> Array[Node3D]:
	var attached: Array[Node3D] = []
	for object in planner.placed:
		if is_instance_valid(object) and str(object.get_meta("planning_attachment", "")) == _desk_id():
			attached.append(object)
	return attached


func _overlaps_attached(object: Node3D) -> bool:
	var bounds: AABB = WORKSTATIONS._bounds(object)
	var rectangle := Rect2(Vector2(bounds.position.x, bounds.position.z), Vector2(bounds.size.x, bounds.size.z)).grow(0.025)
	for other in _attachments():
		if other == object:
			continue
		var other_bounds: AABB = WORKSTATIONS._bounds(other)
		if other_bounds.position.y < bounds.end.y and other_bounds.end.y > bounds.position.y:
			if rectangle.intersects(Rect2(Vector2(other_bounds.position.x, other_bounds.position.z), Vector2(other_bounds.size.x, other_bounds.size.z))):
				return true
	return false


func _start_zone() -> void:
	placing_zone = true
	status.text = "Click to set the %s zone centre." % ("floor" if next_zone_floor else "table")


func _toggle_zone_surface() -> void:
	next_zone_floor = not next_zone_floor
	status.text = "New zones will be on the floor." if next_zone_floor else "New zones will be on the tabletop."


func _toggle_selected_surface() -> void:
	if zone_index < 0:
		return
	var floor_zone := not bool(zones[zone_index]["floor"])
	zones[zone_index]["floor"] = floor_zone
	zones[zone_index]["height"] = 0.0 if floor_zone else 0.89
	_refresh_markers()


func _start_item() -> void:
	if zone_index >= 0 and not model_list.get_selected_items().is_empty():
		model_list.set_meta("placing", true)
		status.text = "Click inside a highlighted zone to place the selected object."


func _remove_zone() -> void:
	if zone_index < 0:
		return
	_clear_zone()
	zones.remove_at(zone_index)
	zone_index = mini(zone_index, zones.size() - 1)
	_refresh_zones()


func _clear_zone() -> void:
	for object in _attachments():
		var local := desk.to_local(object.global_position)
		var zone: Dictionary = zones[zone_index] if zone_index >= 0 else {}
		if zone.is_empty():
			continue
		if absf(local.x - float(zone["x"])) < float(zone["width"]) * 0.5 and absf(local.z - float(zone["z"])) < float(zone["depth"]) * 0.5:
			planner.placed.erase(object)
			object.queue_free()


func _randomize() -> void:
	if zone_index < 0:
		return
	_clear_zone()
	var zone: Dictionary = zones[zone_index]
	var random := RandomNumberGenerator.new()
	random.randomize()
	var choices := ["05_computer_mouse", "05_desk_phone", "05_laptop_destructible", "05_monitor_destructible", "05_keyboard", "09_notepad", "09_mug", "09_stapler", "11_plant_small"]
	var count := random.randi_range(1, 3)
	for _i in count:
		var model: String = choices[random.randi_range(0, choices.size() - 1)]
		var x_offset := random.randf_range(-float(zone["width"]) * 0.33, float(zone["width"]) * 0.33)
		var z_offset := random.randf_range(-float(zone["depth"]) * 0.33, float(zone["depth"]) * 0.33)
		var local := Vector3(float(zone["x"]) + x_offset, float(zone["height"]), float(zone["z"]) + z_offset)
		_place_model(model, local)
	status.text = "Random preview for zone %d" % (zone_index + 1)


func _switch_front() -> void:
	front = 1 - front
	front_button.text = "Front: opposite side" if front else "Front: seated side"
	_refresh_markers()


func _select_zone(index: int) -> void:
	zone_index = index
	var zone: Dictionary = zones[index]
	width_field.set_value_no_signal(float(zone["width"]))
	depth_field.set_value_no_signal(float(zone["depth"]))
	_refresh_markers()


func _resize_zone(_value: float) -> void:
	if zone_index >= 0:
		zones[zone_index]["width"] = width_field.value
		zones[zone_index]["depth"] = depth_field.value
		_refresh_markers()


func _refresh_zones() -> void:
	zone_list.clear()
	for i in zones.size():
		zone_list.add_item("Zone %d  (%.2f, %.2f)" % [i + 1, zones[i]["x"], zones[i]["z"]])
	if zone_index >= 0:
		zone_list.select(zone_index)
		_select_zone(zone_index)
	else:
		_refresh_markers()


func _refresh_markers() -> void:
	markers.call("redraw", zones, zone_index, front)


func _save() -> void:
	if TEMPLATE_FILES.safe_name(template_name.text).is_empty():
		status.text = "Enter a template name first."
		return
	var items: Array[Dictionary] = []
	for object in _attachments():
		var local := desk.to_local(object.global_position)
		items.append({"path": str(object.get_meta("planning_scene_path", "")), "x": local.x, "y": local.y, "z": local.z, "yaw": object.rotation.y - desk.rotation.y})
	if not TEMPLATE_FILES.save(WORKSTATIONS.desk_name(_desk_path()), template_name.text, {"version": 1, "desk": WORKSTATIONS.desk_name(_desk_path()), "front": front, "zones": zones, "items": items}):
		status.text = "Could not save the template."
		return
	_refresh_templates()
	status.text = "Saved: " + template_name.text


func _refresh_templates() -> void:
	template_list.clear()
	for item in TEMPLATE_FILES.list_for(WORKSTATIONS.desk_name(_desk_path())):
		template_list.add_item(str(item["name"]))
		template_list.set_item_metadata(template_list.item_count - 1, item["path"])


func _load() -> void:
	if template_list.selected < 0:
		return
	var path: String = template_list.get_item_metadata(template_list.selected)
	var data := TEMPLATE_FILES.load(path, WORKSTATIONS.desk_name(_desk_path())) as Dictionary
	if data.is_empty():
		status.text = "Template does not match this desk."
		return
	for object in _attachments():
		planner.placed.erase(object)
		object.queue_free()
	zones.clear()
	for value in data.get("zones", []):
		if value is Dictionary:
			zones.append(value)
	front = int(data.get("front", 0))
	front_button.text = "Front: opposite side" if front else "Front: seated side"
	zone_index = 0 if not zones.is_empty() else -1
	_refresh_zones()
	for entry_value in data.get("items", []):
		if not entry_value is Dictionary:
			continue
		var entry: Dictionary = entry_value
		var asset_path := str(entry.get("path", ""))
		if not asset_path.begins_with(MODEL_ROOT) or not FileAccess.file_exists(asset_path):
			continue
		var object := planner._instantiate_asset(asset_path) as Node3D
		if object == null:
			continue
		planner.root.add_child(object)
		object.global_position = desk.to_global(Vector3(float(entry.get("x", 0)), float(entry.get("y", 0)), float(entry.get("z", 0))))
		object.rotation.y = desk.rotation.y + float(entry.get("yaw", 0))
		object.set_meta("planning_scene_path", asset_path)
		object.set_meta("planning_attachment", _desk_id())
		planner.placed.append(object)
	status.text = "Template applied to this desk. Save the map to keep it."
