extends RefCounted

# Present planner controls, selection and lighting feedback.
var planner: Variant


func _init(context: Node) -> void:
	planner = context


func _build_planning_toolbar() -> void:
	planner.edit_history = planner.EDIT_HISTORY.new()
	planner.edit_history.set("planner", planner)
	planner.planning_toolbar = PanelContainer.new()
	planner.planning_toolbar.set_anchors_preset(Control.PRESET_CENTER_TOP)
	planner.planning_toolbar.offset_left = -165
	planner.planning_toolbar.offset_right = 165
	planner.planning_toolbar.offset_top = 8
	planner.planning_toolbar.offset_bottom = 48
	planner.planning_toolbar.mouse_filter = Control.MOUSE_FILTER_STOP
	var toolbar_style = StyleBoxFlat.new()
	toolbar_style.bg_color = Color(0.005, 0.035, 0.065, 0.95)
	toolbar_style.border_color = Color(0.02, 0.72, 0.98)
	toolbar_style.set_border_width_all(2)
	toolbar_style.set_corner_radius_all(8)
	planner.planning_toolbar.add_theme_stylebox_override("panel", toolbar_style)
	planner.ui.add_child(planner.planning_toolbar)
	var toolbar_buttons = HBoxContainer.new()
	planner.planning_toolbar.add_child(toolbar_buttons)
	planner.undo_button = Button.new()
	planner.undo_button.text = "Undo last action"
	planner.undo_button.pressed.connect(func() -> void: planner.edit_history.call("undo"))
	toolbar_buttons.add_child(planner.undo_button)
	planner.duplicate_button = Button.new()
	planner.duplicate_button.text = "Duplicate selected"
	planner.duplicate_button.pressed.connect(func() -> void: planner.edit_history.call("duplicate_selected"))
	toolbar_buttons.add_child(planner.duplicate_button)
	_update_history_buttons()


func _text_field_has_focus() -> bool:
	var focused = planner.get_viewport().gui_get_focus_owner()
	if focused == planner.map_name_edit and focused != null:
		return true
	for field in [planner.default_light_height, planner.default_light_energy, planner.default_light_angle, planner.default_flicker_step, planner.selected_flicker_step]:
		if field != null and focused == (field as SpinBox).get_line_edit():
			return true
	return false


func _reset_selection() -> void:
	planner.selected_path = ""
	planner.selected_kind = ""
	planner.rotation_y = 0.0
	planner.objects._clear_preview()
	_select(null)
	planner.palette.deselect_all()
	planner.status.text = "Selection cleared"


func _set_light_markers_visible(value: bool) -> void:
	for light_node in planner.get_tree().get_nodes_in_group("planner_lights"):
		if light_node.has_method("set_planning_visual"):
			light_node.call("set_planning_visual", value)


func _show_planning_grid() -> void:
	if planner.planning_grid != null and is_instance_valid(planner.planning_grid):
		return
	planner.planning_grid = MeshInstance3D.new()
	var mesh = ImmediateMesh.new()
	var material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.1, 0.75, 1.0, 0.38)
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	for x in range(-int(planner.PLAN_HALF_WIDTH), int(planner.PLAN_HALF_WIDTH) + 1):
		mesh.surface_add_vertex(Vector3(x, 0.012, -planner.PLAN_HALF_DEPTH))
		mesh.surface_add_vertex(Vector3(x, 0.012, planner.PLAN_HALF_DEPTH))
	for z in range(-int(planner.PLAN_HALF_DEPTH), int(planner.PLAN_HALF_DEPTH) + 1):
		mesh.surface_add_vertex(Vector3(-planner.PLAN_HALF_WIDTH, 0.012, z))
		mesh.surface_add_vertex(Vector3(planner.PLAN_HALF_WIDTH, 0.012, z))
	mesh.surface_end()
	var red = StandardMaterial3D.new()
	red.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	red.cull_mode = BaseMaterial3D.CULL_DISABLED
	red.albedo_color = Color(1.0, 0.06, 0.06)
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, red)
	_add_grid_rectangle(mesh, Vector3(-planner.PLAN_HALF_WIDTH, 0.035, -0.045), Vector3(planner.PLAN_HALF_WIDTH, 0.035, 0.045))
	_add_grid_rectangle(mesh, Vector3(-0.045, 0.035, -planner.PLAN_HALF_DEPTH), Vector3(0.045, 0.035, planner.PLAN_HALF_DEPTH))
	_add_grid_marker(mesh, Vector2.ZERO, 0.7)
	for x in [-planner.PLAN_HALF_WIDTH * 0.5, planner.PLAN_HALF_WIDTH * 0.5]:
		for z in [-planner.PLAN_HALF_DEPTH * 0.5, planner.PLAN_HALF_DEPTH * 0.5]:
			_add_grid_marker(mesh, Vector2(x, z), 0.5)
	mesh.surface_end()
	planner.planning_grid.mesh = mesh
	planner.host.add_child(planner.planning_grid)


func _add_grid_rectangle(mesh: ImmediateMesh, minimum: Vector3, maximum: Vector3) -> void:
	var a = Vector3(minimum.x, minimum.y, minimum.z)
	var b = Vector3(maximum.x, minimum.y, minimum.z)
	var c = Vector3(maximum.x, minimum.y, maximum.z)
	var d = Vector3(minimum.x, minimum.y, maximum.z)
	for vertex in [a, b, c, a, c, d]:
		mesh.surface_add_vertex(vertex)


func _add_grid_marker(mesh: ImmediateMesh, center: Vector2, radius: float) -> void:
	for sector in 16:
		var first = TAU * float(sector) / 16.0
		var second = TAU * float(sector + 1) / 16.0
		mesh.surface_add_vertex(Vector3(center.x, 0.045, center.y))
		mesh.surface_add_vertex(Vector3(center.x + cos(first) * radius, 0.045, center.y + sin(first) * radius))
		mesh.surface_add_vertex(Vector3(center.x + cos(second) * radius, 0.045, center.y + sin(second) * radius))


func _hide_planning_grid() -> void:
	if planner.planning_grid != null and is_instance_valid(planner.planning_grid):
		planner.planning_grid.queue_free()
	planner.planning_grid = null


func _select(node: Node3D) -> void:
	_clear_selection_highlight()
	planner.selected = node
	planner.desk_setup_button.visible = planner.selected != null and not planner.WORKSTATIONS.desk_name(str(planner.selected.get_meta("planning_scene_path", ""))).is_empty()
	if planner.selected != null:
		_show_selection_highlight(planner.selected)
	_update_light_ui()
	_update_status()
	_update_history_buttons()


func _update_history_buttons() -> void:
	if planner.undo_button != null:
		planner.undo_button.disabled = (planner.edit_history.get("stack") as Array).is_empty()
	if planner.duplicate_button != null:
		planner.duplicate_button.disabled = planner.selected == null or planner.selected == planner.main_player


func _open_desk_setup() -> void:
	if planner.selected != null and planner.desk_setup_button.visible:
		planner.desk_setup.open(planner.selected)


func _toggle_help() -> void:
	var overlay = planner.help.get_parent().get_parent() as Control
	overlay.visible = not overlay.visible


func _update_light_ui() -> void:
	var target = planner.selected
	if target == null and planner.preview != null and planner.objects._selected_kind() == "light":
		target = planner.preview
	var light: Light3D
	if target != null:
		light = target.find_child("Light", true, false) as Light3D
	var show_light = light != null and target.has_method("get_authored_energy")
	planner.light_info.visible = show_light
	planner.light_level.visible = show_light
	planner.light_angle_info.visible = show_light and light is SpotLight3D
	planner.light_angle.visible = show_light and light is SpotLight3D
	planner.ui.get_node("Panel/VBox/SelectedFlicker").visible = show_light and planner.selected != null
	planner.ui.get_node("Panel/VBox/SelectedFlickerStep").visible = show_light and planner.selected != null
	if show_light:
		planner.light_info.text = "LIGHT %.2f / 16.00" % float(target.call("get_authored_energy"))
		planner.light_level.value = float(target.call("get_authored_energy"))
		if light is SpotLight3D:
			var spot = light as SpotLight3D
			planner.light_angle_info.text = "CONE %.0f°" % spot.spot_angle
			planner.light_angle.value = spot.spot_angle
		if planner.selected != null:
			planner.editing_flicker = true
			planner.selected_flicker_mode.select(int(target.get_meta("planning_flicker_mode", 0)))
			planner.selected_flicker_step.value = float(target.get_meta("planning_flicker_step", 0.2))
			planner.editing_flicker = false


func _on_selected_flicker_changed(_index: int) -> void:
	if not planner.editing_flicker:
		planner.selected_flicker_step.value = _recommended_flicker_step(planner.selected_flicker_mode.get_selected_id())
	_apply_selected_flicker()


func _on_default_flicker_mode_changed(_index: int) -> void:
	planner.default_flicker_step.value = _recommended_flicker_step(planner.default_flicker_mode.get_selected_id())


func _recommended_flicker_step(mode: int) -> float:
	match mode:
		1: return 0.12
		2: return 0.75
		3: return 1.5
	return 0.2


func _on_selected_flicker_step_changed(_value: float) -> void:
	_apply_selected_flicker()


func _apply_selected_flicker() -> void:
	if planner.editing_flicker or planner.selected == null or not planner.selected.has_method("configure_flicker"):
		return
	planner.selected.call("configure_flicker", planner.selected_flicker_mode.get_selected_id(), planner.selected_flicker_step.value)


func _show_selection_highlight(node: Node3D) -> void:
	var aabb = planner.geometry._combined_aabb(node, true)
	planner.selection_source_aabb = aabb
	if aabb.size.length_squared() <= 0.0001:
		return
	planner.selection_box = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = aabb.size + Vector3(0.08, 0.08, 0.08)
	var material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.1, 0.85, 1.0, 0.16)
	material.no_depth_test = true
	box.material = material
	planner.selection_box.mesh = box
	planner.selection_box.set_meta("planning_selection_highlight", true)
	node.add_child(planner.selection_box)
	planner.selection_box.position = aabb.get_center()


func _clear_selection_highlight() -> void:
	if planner.selection_box != null and is_instance_valid(planner.selection_box):
		planner.selection_box.queue_free()
	planner.selection_box = null
	planner.selection_source_aabb = AABB()


func _update_status() -> void:
	if planner.selected == null:
		planner.status.text = "%d objects | select palette or object" % planner.placed.size()
		return
	if planner.selected.is_in_group("darkness_zone"):
		planner.status.text = "DARKNESS | scale X/Z changes covered area | Delete removes"
		return
	planner.status.text = "SELECTED | pos %.1f %.1f | rot %.0f | scale %.2f %.2f %.2f" % [
		planner.selected.position.x, planner.selected.position.z, planner.selected.rotation_degrees.y,
		planner.selected.scale.x, planner.selected.scale.y, planner.selected.scale.z
	]
