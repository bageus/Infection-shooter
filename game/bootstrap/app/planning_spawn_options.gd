extends Node
## Planner panel for spawn waves, on the right of the screen: the settings of the
## selected spawn point (or of the next one to place) and, for a selected infected,
## which spawn points its death starts. Links are drawn while one end is selected.

const SPAWN_CONFIG := preload("res://game/features/spawning/public/spawn_config.gd")
const QUEUE_EDITOR := preload("res://game/bootstrap/app/planning_spawn_queue_editor.gd")
const DIRECTOR := preload("res://game/features/spawning/public/wave_director.gd")
const LINK_COLOR := Color(0.25, 0.95, 1.0)
const LINK_LIFT := Vector3(0.0, 1.0, 0.0)

var session: Variant
var objects: Variant
var panel: PanelContainer
var title: Label
var hint: Label
var point_scroll: ScrollContainer
var point_box: VBoxContainer
var enemy_box: VBoxContainer
var editor: VBoxContainer
var link_note: Label
var link_list: VBoxContainer
var links: MeshInstance3D
# What the next placed spawn point starts with (kept between placements).
var spawn_defaults: Dictionary = {}
var _updating := false
var _loaded_point: Node3D


func setup(context: Variant, planner_objects: Variant) -> void:
	session = context
	objects = planner_objects
	panel = PanelContainer.new()
	panel.name = "SpawnWaves"
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	# Sits left of the planner's RightPanel (starts at x = -336) so the map HUD stays visible.
	panel.offset_left = -664.0
	panel.offset_right = -344.0
	panel.offset_top = 56.0
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.005, 0.035, 0.065, 0.95)
	style.border_color = Color(0.02, 0.72, 0.98)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	panel.add_child(column)
	title = Label.new()
	column.add_child(title)
	hint = Label.new()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = 300
	hint.text = "Выберите точку спавна (вкладка «Враги»), чтобы настроить волну, или врага, чтобы отметить волны, которые запускает его смерть."
	column.add_child(hint)
	point_box = VBoxContainer.new()
	point_scroll = ScrollContainer.new()
	point_scroll.custom_minimum_size = Vector2(320, 430)
	point_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	point_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	point_scroll.add_child(point_box)
	column.add_child(point_scroll)
	editor = QUEUE_EDITOR.new()
	editor.changed.connect(_changed)
	point_box.add_child(editor)
	link_note = Label.new()
	link_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	link_note.custom_minimum_size.x = 300
	point_box.add_child(link_note)
	enemy_box = VBoxContainer.new()
	column.add_child(enemy_box)
	var caption := Label.new()
	caption.text = "Смерть этого врага запускает точки:"
	enemy_box.add_child(caption)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(300, 150)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	enemy_box.add_child(scroll)
	link_list = VBoxContainer.new()
	link_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(link_list)
	session.ui.add_child(panel)
	panel.hide()
	links = MeshInstance3D.new()
	links.name = "WaveLinks"
	links.mesh = ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = LINK_COLOR
	material.no_depth_test = true
	links.material_override = material
	links.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	session.host.add_child(links)


func contains_point(screen_position: Vector2) -> bool:
	return panel != null and panel.is_visible_in_tree() and panel.get_global_rect().has_point(screen_position)


func _is_enemy(node: Node3D) -> bool:
	return node != null and str(node.get_meta("planning_actor_kind", "")) == "enemy"


func _point_target() -> Node3D:
	var target: Node3D = objects.selected if objects.selected != null else objects.preview
	return target if target != null and target.has_method("configure_spawn") else null


func _points() -> Array[Node3D]:
	var found: Array[Node3D] = []
	for node in objects.placed:
		if is_instance_valid(node) and node.has_method("configure_spawn"):
			found.append(node)
	return found


func _point_id(point: Node3D) -> String:
	return str(point.get_meta("planning_object_id", ""))


func _linked_keys(enemy: Node) -> Array:
	return Array(enemy.get_meta(DIRECTOR.TRIGGER_META, [])).map(func(key: Variant) -> String: return str(key))


## Infected whose death can start the queue with this link key.
func linked_enemies(point_id: String) -> Array[Node3D]:
	var found: Array[Node3D] = []
	for enemy in session.enemies_root.get_children():
		if enemy is Node3D and Array(enemy.get_meta(DIRECTOR.TRIGGER_META, [])).has(point_id):
			found.append(enemy)
	return found


func update() -> void:
	if panel == null:
		return
	var point := _point_target()
	var enemy: Node3D = objects.selected if _is_enemy(objects.selected) else null
	var actors: bool = session.catalog.active_catalog == session.catalog.actor_catalog
	panel.visible = actors or point != null or enemy != null
	if not panel.visible:
		return
	_updating = true
	point_box.visible = point != null
	point_scroll.visible = point != null
	enemy_box.visible = enemy != null
	hint.visible = point == null and enemy == null
	title.text = "ВОЛНЫ СПАВНА"
	if point != null:
		title.text = "ТОЧКА СПАВНА" + (" | размещение" if objects.selected == null else "")
		_load_point(point)
	elif enemy != null:
		title.text = "ВРАГ | запуск волн"
		_load_enemy(enemy)
	_updating = false


func _load_point(point: Node3D) -> void:
	editor.load_config(point.call("get_spawn_config"), editor.current if point == _loaded_point else 0)
	_loaded_point = point
	if objects.selected == null:
		link_note.text = "После размещения выберите врага и отметьте эту очередь."
		return
	var point_id := _point_id(point)
	var lines: Array[String] = []
	var queues: Array = point.call("get_spawn_config")["queues"]
	for index in queues.size():
		if index == 0 or str(queues[index]["start"]) == "trigger":
			lines.append("Очередь %d: связано врагов %d" % [index + 1, linked_enemies(SPAWN_CONFIG.link_key(point_id, index)).size()])
		else:
			lines.append("Очередь %d: через %.1f с после предыдущей" % [index + 1, float(queues[index]["delay"])])
	link_note.text = "\n".join(lines)
	if linked_enemies(point_id).is_empty():
		link_note.text += "\nУ первой очереди нет связанных врагов: она не запустится. Выберите врага и отметьте эту точку."


func _load_enemy(enemy: Node3D) -> void:
	for child in link_list.get_children():
		link_list.remove_child(child)
		child.queue_free()
	var ids := Array(enemy.get_meta(DIRECTOR.TRIGGER_META, []))
	var points := _points()
	var shown := 0
	for index in points.size():
		var config: Dictionary = points[index].call("get_spawn_config")
		var queues: Array = config["queues"]
		for queue_index in queues.size():
			if queue_index > 0 and str(queues[queue_index]["start"]) != "trigger":
				continue
			var key := SPAWN_CONFIG.link_key(_point_id(points[index]), queue_index)
			var box := CheckBox.new()
			box.text = "Точка %d, очередь %d: %s (%.0f, %.0f)" % [index + 1, queue_index + 1, SPAWN_CONFIG.queue_summary(queues[queue_index]), points[index].position.x, points[index].position.z]
			box.button_pressed = ids.has(key)
			box.toggled.connect(_toggle_link.bind(key))
			link_list.add_child(box)
			shown += 1
	if shown == 0:
		var empty := Label.new()
		empty.text = "На карте нет точек спавна."
		link_list.add_child(empty)


func _toggle_link(on: bool, key: String) -> void:
	var enemy: Node3D = objects.selected
	if _updating or not _is_enemy(enemy):
		return
	session.edit_history.call("record_transform", enemy)
	var ids := Array(enemy.get_meta(DIRECTOR.TRIGGER_META, []))
	if on and not ids.has(key):
		ids.append(key)
	elif not on:
		ids.erase(key)
	if ids.is_empty():
		enemy.remove_meta(DIRECTOR.TRIGGER_META)
	else:
		enemy.set_meta(DIRECTOR.TRIGGER_META, ids)


func hide() -> void:
	if panel != null:
		panel.hide()


## A freshly created spawn point starts with the options last chosen in the panel
## and gets the id that enemies use to link to it.
func configure_new(node: Node3D) -> void:
	if not node.has_method("configure_spawn"):
		return
	if not spawn_defaults.is_empty():
		node.call("configure_spawn", spawn_defaults)
	if str(node.get_meta("planning_object_id", "")).is_empty():
		node.set_meta("planning_object_id", "spawn_%d" % Time.get_ticks_usec())


func _changed(config: Dictionary) -> void:
	if _updating:
		return
	var point := _point_target()
	if point == null:
		return
	if objects.selected != null:
		session.edit_history.call("record_transform", point)
	point.call("configure_spawn", config)
	if objects.selected == null:
		spawn_defaults = config
	update()


func _process(_delta: float) -> void:
	if panel == null:
		return
	var mesh := links.mesh as ImmediateMesh
	mesh.clear_surfaces()
	if not panel.is_visible_in_tree():
		return
	var pairs: Array[Array] = []
	var selected: Node3D = objects.selected
	if _is_enemy(selected):
		for point in _points():
			if _linked_keys(selected).any(func(key: String) -> bool: return SPAWN_CONFIG.split_link(key)[0] == _point_id(point)):
				pairs.append([selected.global_position, point.global_position])
	elif selected != null and selected.has_method("configure_spawn"):
		for enemy in session.enemies_root.get_children():
			if enemy is Node3D and _linked_keys(enemy).any(func(key: String) -> bool: return SPAWN_CONFIG.split_link(key)[0] == _point_id(selected)):
				pairs.append([enemy.global_position, selected.global_position])
	if pairs.is_empty():
		return
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for pair in pairs:
		mesh.surface_add_vertex(pair[0] + LINK_LIFT)
		mesh.surface_add_vertex(pair[1] + LINK_LIFT)
	mesh.surface_end()
