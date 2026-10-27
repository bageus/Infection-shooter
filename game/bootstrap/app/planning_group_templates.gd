extends Node
## Group templates: objects picked with Shift in template mode are saved under a name, and a saved group ghosts and places as one.
const KIND := "group_template"
const ROOT := "user://planner_templates"
const CAPTURE := preload("res://game/bootstrap/app/planning_layout_capture.gd")
const LOADER := preload("res://game/bootstrap/app/planning_layout_loader.gd")
const SAFE_NAME := preload("res://game/bootstrap/app/desk_setup_template_files.gd")
# Identity and desk links belong to the source map; a copy placed elsewhere must not claim them.
const DROPPED_FIELDS := ["object_id", "desk_id", "attachment", "zone", "blood_attachment", "auto_fixture"]
const HIGHLIGHT := "TemplatePickHighlight"
const HIGHLIGHT_COLOR := Color(1.0, 0.7, 0.1, 0.35)

var session: Variant
var objects: Variant
var tab: VBoxContainer
var list: ItemList
var name_edit: LineEdit
var create_button: Button
var edit_button: Button
var cancel_button: Button
var status: Label
var _recording := false
var _picked: Array[Node3D] = []
var _place_pending := false
var _template: Dictionary = {}


func setup(context: Variant, planner_objects: Variant) -> void:
	session = context
	objects = planner_objects


func build_tab() -> Control:
	tab = VBoxContainer.new()
	tab.name = "Шаблоны"
	var title := Label.new()
	title.text = "Шаблоны групп | Create: Shift+клик отмечает объекты | клик по шаблону + наведение на поле"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tab.add_child(title)
	list = ItemList.new()
	list.name = "GroupTemplateList"
	list.custom_minimum_size.y = 150
	list.item_selected.connect(_template_selected)
	tab.add_child(list)
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "Название шаблона"
	tab.add_child(name_edit)
	var buttons := HBoxContainer.new()
	tab.add_child(buttons)
	create_button = Button.new()
	create_button.text = "Create template"
	create_button.pressed.connect(_create_pressed)
	buttons.add_child(create_button)
	edit_button = Button.new()
	edit_button.text = "Edit"
	edit_button.pressed.connect(_edit_pressed)
	buttons.add_child(edit_button)
	cancel_button = Button.new()
	cancel_button.text = "Отмена записи"
	cancel_button.hide()
	cancel_button.pressed.connect(_cancel_recording)
	tab.add_child(cancel_button)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tab.add_child(status)
	_refresh_list()
	return tab


func recording() -> bool:
	return _recording


## Shift+click in template mode: the object joins the template, or leaves it when already picked.
func toggle_pick(node: Node3D) -> void:
	if node == null or node == objects.session.main_player or not objects.placed.has(node):
		return
	if not str(node.get_meta("planning_desk_id", "")).is_empty() or not str(node.get_meta("planning_attachment", "")).is_empty():
		status.text = "Мебель с рабочим местом не входит в шаблон"
		return
	if _picked.has(node):
		_unmark(node)
		_picked.erase(node)
	else:
		_mark(node)
		_picked.append(node)
	status.text = "В шаблоне объектов: %d" % _picked.size()


func move_ghost(screen_pos: Vector2) -> void:
	var ghost: Node3D = objects.preview
	var world: Vector3 = objects.geometry._screen_to_surface(screen_pos, ghost)
	if not world.is_finite():
		ghost.hide()
		return
	ghost.show()
	ghost.rotation.y = deg_to_rad(objects.rotation_y)
	ghost.global_position = _anchor(world)


func place(screen_pos: Vector2) -> void:
	var world: Vector3 = objects.geometry._screen_to_surface(screen_pos, objects.preview)
	if not world.is_finite():
		status.text = "Наведите на поле, чтобы разместить шаблон"
		return
	var anchor := _anchor(world)
	var records: Array = []
	for record: Dictionary in _template.objects:
		records.append(moved(record, anchor, objects.rotation_y))
	var before: int = objects.placed.size()
	var count: int = LOADER.new(objects).append(records)
	if count == 0:
		status.text = "Шаблон не удалось разместить"
		return
	var added: Array[Node3D] = []
	for node: Node3D in objects.placed.slice(before):
		added.append(node)
	objects.session.edit_history.record_added_group(added)
	status.text = "Шаблон «%s» размещён: %d объектов" % [_template.name, count]
	if _place_pending:
		# Edit places one copy, then the copy's objects are picked so more can be added with Shift.
		_place_pending = false
		_clear_ghost()
		for node in added:
			_mark(node)
			_picked.append(node)
		status.text = "Редактирование «%s»: Shift+клик добавляет объекты, затем Save template" % _template.name


func _ghost() -> Node3D:
	var ghost := Node3D.new()
	ghost.name = "GroupTemplateGhost"
	ghost.set_meta("planning_preview", true)
	ghost.process_mode = Node.PROCESS_MODE_DISABLED
	for record: Dictionary in _template.objects:
		var node := objects.catalog._instantiate_asset(str(record.scene)) as Node3D
		if node == null:
			continue
		node.position = Vector3(float(record.x), float(record.y), float(record.z))
		node.rotation_degrees = Vector3(float(record.get("rotation_x", 0.0)), float(record.get("rotation_y", 0.0)), float(record.get("rotation_z", 0.0)))
		node.scale = Vector3(float(record.get("scale_x", 1.0)), float(record.get("scale_y", 1.0)), float(record.get("scale_z", 1.0)))
		objects.geometry._set_preview_collision(node, true)
		ghost.add_child(node)
	return ghost


func _anchor(world: Vector3) -> Vector3:
	var anchor: Vector3 = objects.geometry._snap(world)
	anchor.y = world.y
	return anchor


func _template_selected(index: int) -> void:
	_template = load_template(str(list.get_item_metadata(index)))
	if _template.is_empty():
		status.text = "Шаблон не читается"
		return
	_show_ghost()
	status.text = "Наведите на поле и кликните. RMB — отмена"


func _show_ghost() -> void:
	objects._clear_preview()
	objects.selected_path = ""
	objects.selected_kind = KIND
	objects.selected_entry = {}
	objects.rotation_y = 0.0
	objects.pose = Basis.IDENTITY
	objects._select(null)
	objects.controls.palette.deselect_all()
	objects.preview = _ghost()
	objects.session.host.add_child(objects.preview)


func _clear_ghost() -> void:
	objects._clear_preview()
	objects.selected_kind = ""


func _create_pressed() -> void:
	if _recording:
		_save_recording()
		return
	if SAFE_NAME.safe_name(name_edit.text).is_empty():
		status.text = "Сначала введите название шаблона"
		return
	_start_recording()
	status.text = "Запись: Shift+клик отмечает объекты, затем нажмите Save template"


## Edit loads a saved template as a ghost; its first placed copy becomes the picked set to extend.
func _edit_pressed() -> void:
	if _recording:
		status.text = "Сначала сохраните или отмените запись"
		return
	var selected := list.get_selected_items()
	if selected.is_empty():
		status.text = "Выберите шаблон в списке"
		return
	_template = load_template(str(list.get_item_metadata(selected[0])))
	if _template.is_empty():
		status.text = "Шаблон не читается"
		return
	name_edit.text = _template.name
	_start_recording()
	_place_pending = true
	_show_ghost()
	status.text = "Наведите на поле и кликните, чтобы разместить «%s» для правки" % _template.name


func _start_recording() -> void:
	_clear_picks()
	_clear_ghost()
	objects._select(null)
	objects.controls.palette.deselect_all()
	_recording = true
	create_button.text = "Save template"
	cancel_button.show()


func _cancel_recording() -> void:
	_end_recording()
	status.text = "Запись шаблона отменена"


func _end_recording() -> void:
	_clear_picks()
	_clear_ghost()
	_recording = false
	_place_pending = false
	create_button.text = "Create template"
	cancel_button.hide()


func _save_recording() -> void:
	var nodes: Array[Node3D] = []
	for node in _picked:
		if is_instance_valid(node) and objects.placed.has(node):
			nodes.append(node)
	if nodes.is_empty():
		status.text = "Отметьте хотя бы один объект Shift+кликом"
		return
	var template := make_template(name_edit.text.strip_edges(), CAPTURE.collect(objects, nodes, false).objects)
	if not write(SAFE_NAME.safe_name(name_edit.text), template):
		status.text = "Не удалось записать шаблон в user://planner_templates"
		return
	_end_recording()
	_refresh_list()
	status.text = "Сохранён шаблон «%s»: %d объектов" % [template.name, nodes.size()]


func _mark(node: Node3D) -> void:
	var aabb: AABB = objects.geometry._combined_aabb(node, true)
	if aabb.size.length_squared() <= 0.0001:
		return
	var box := MeshInstance3D.new()
	box.name = HIGHLIGHT
	box.set_meta("planning_selection_highlight", true)
	var mesh := BoxMesh.new()
	mesh.size = aabb.size + Vector3.ONE * 0.08
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = HIGHLIGHT_COLOR
	material.no_depth_test = true
	mesh.material = material
	box.mesh = mesh
	box.position = aabb.get_center()
	node.add_child(box)


func _unmark(node: Node3D) -> void:
	var box := node.get_node_or_null(HIGHLIGHT)
	if box != null:
		box.queue_free()


func _clear_picks() -> void:
	for node in _picked:
		if is_instance_valid(node):
			_unmark(node)
	_picked.clear()


func _refresh_list() -> void:
	list.clear()
	# A folder is created on the first save; listing it before then logs an engine error.
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(ROOT)):
		return
	var found: Array[Dictionary] = []
	for file in DirAccess.get_files_at(ROOT):
		if file.ends_with(".json"):
			var path := ROOT + "/" + file
			var template := load_template(path)
			if not template.is_empty():
				found.append({"name": template.name, "path": path})
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.name).naturalnocasecmp_to(str(b.name)) < 0)
	for item in found:
		var index := list.add_item(str(item.name))
		list.set_item_metadata(index, item.path)


## Positions become offsets from the group's centre (x, z) and its lowest floor level (y).
static func make_template(name_text: String, records: Array) -> Dictionary:
	var center := Vector2.ZERO
	var floor_y := INF
	for record: Dictionary in records:
		center += Vector2(float(record.x), float(record.z))
		floor_y = minf(floor_y, float(record.y))
	center /= float(maxi(records.size(), 1))
	var local: Array = []
	for record: Dictionary in records:
		var entry := record.duplicate(true)
		for field in DROPPED_FIELDS:
			entry.erase(field)
		entry.x = float(record.x) - center.x
		entry.z = float(record.z) - center.y
		entry.y = float(record.y) - floor_y
		if record.has("spawn_x"):
			entry.spawn_x = float(record.spawn_x) - center.x
			entry.spawn_y = float(record.spawn_y) - floor_y
			entry.spawn_z = float(record.spawn_z) - center.y
		local.append(entry)
	return {"version": 1, "name": name_text, "objects": local}


## A stored offset record placed at anchor and turned by yaw_degrees around the anchor.
static func moved(record: Dictionary, anchor: Vector3, yaw_degrees: float) -> Dictionary:
	var angle := deg_to_rad(yaw_degrees)
	var entry := record.duplicate(true)
	var point := anchor + Vector3(float(record.x), float(record.y), float(record.z)).rotated(Vector3.UP, angle)
	entry.x = point.x
	entry.y = point.y
	entry.z = point.z
	entry.rotation_y = float(record.get("rotation_y", 0.0)) + yaw_degrees
	if record.has("spawn_x"):
		var spawn := anchor + Vector3(float(record.spawn_x), float(record.spawn_y), float(record.spawn_z)).rotated(Vector3.UP, angle)
		entry.spawn_x = spawn.x
		entry.spawn_y = spawn.y
		entry.spawn_z = spawn.z
	return entry


static func write(file_name: String, template: Dictionary) -> bool:
	if file_name.is_empty() or DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ROOT)) != OK:
		return false
	var path := ROOT + "/" + file_name + ".json"
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(template, "\t"))
	file.flush()
	var written := file.get_error() == OK
	file.close()
	if not written:
		DirAccess.remove_absolute(temporary)
		return false
	return DirAccess.rename_absolute(temporary, path) == OK


static func load_template(path: String) -> Dictionary:
	if not path.begins_with(ROOT + "/") or not path.ends_with(".json"):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var data: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not data is Dictionary or not data.get("name") is String or not data.get("objects") is Array or (data.objects as Array).is_empty():
		return {}
	for record: Variant in data.objects:
		if not record is Dictionary or not record.get("scene") is String:
			return {}
	return data
