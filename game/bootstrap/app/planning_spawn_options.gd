extends Node
## Planner panel for spawn waves, on the right of the screen: the settings of the
## selected spawn point (or of the next one to place) and, for a selected infected,
## which spawn points its death starts. Links are drawn while one end is selected.

const SPAWN_CONFIG := preload("res://game/features/spawning/public/spawn_config.gd")
const DIRECTOR := preload("res://game/features/spawning/public/wave_director.gd")
const LINK_COLOR := Color(0.25, 0.95, 1.0)
const LINK_LIFT := Vector3(0.0, 1.0, 0.0)

var session: Variant
var objects: Variant
var panel: PanelContainer
var title: Label
var hint: Label
var point_box: VBoxContainer
var enemy_box: VBoxContainer
var enemy_option: OptionButton
var count_spin: SpinBox
var interval_spin: SpinBox
var rule_option: OptionButton
var batch_row: HBoxContainer
var batch_label: Label
var batch_spin: SpinBox
var trigger_option: OptionButton
var health_spin: SpinBox
var damage_spin: SpinBox
var link_note: Label
var link_list: VBoxContainer
var links: MeshInstance3D
# What the next placed spawn point starts with (kept between placements).
var spawn_defaults: Dictionary = {}
var _updating := false


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
	column.add_child(point_box)
	enemy_option = _option_row(point_box, "Враг", SPAWN_CONFIG.ENEMY_LABELS)
	count_spin = _spin_row(point_box, "Количество", 1, SPAWN_CONFIG.COUNT_MAX, 1)
	interval_spin = _spin_row(point_box, "Интервал, сек", SPAWN_CONFIG.INTERVAL_MIN, SPAWN_CONFIG.INTERVAL_MAX, 0.1)
	rule_option = _option_row(point_box, "Правило", SPAWN_CONFIG.RULE_LABELS)
	batch_row = HBoxContainer.new()
	point_box.add_child(batch_row)
	batch_label = Label.new()
	batch_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	batch_row.add_child(batch_label)
	batch_spin = _spin(1, SPAWN_CONFIG.BATCH_MAX, 1)
	batch_row.add_child(batch_spin)
	trigger_option = _option_row(point_box, "Запуск", SPAWN_CONFIG.TRIGGER_LABELS)
	health_spin = _spin_row(point_box, "Живучесть, %", SPAWN_CONFIG.STAT_MIN, SPAWN_CONFIG.STAT_MAX, 5.0)
	damage_spin = _spin_row(point_box, "Урон, %", SPAWN_CONFIG.STAT_MIN, SPAWN_CONFIG.STAT_MAX, 5.0)
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


func _option_row(parent: Control, text: String, labels: Array[String]) -> OptionButton:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var option := OptionButton.new()
	option.custom_minimum_size.x = 170
	for entry in labels:
		option.add_item(entry)
	option.item_selected.connect(_changed)
	row.add_child(option)
	parent.add_child(row)
	return option


func _spin_row(parent: Control, text: String, low: float, high: float, step: float) -> SpinBox:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	row.add_child(_spin(low, high, step))
	parent.add_child(row)
	return row.get_child(1) as SpinBox


func _spin(low: float, high: float, step: float) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = low
	spin.max_value = high
	spin.step = step
	spin.value_changed.connect(_changed)
	return spin


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
	var config: Dictionary = point.call("get_spawn_config")
	enemy_option.select(maxi(SPAWN_CONFIG.ENEMIES.find(str(config["enemy"])), 0))
	count_spin.set_value_no_signal(float(config["count"]))
	interval_spin.set_value_no_signal(float(config["interval"]))
	rule_option.select(maxi(SPAWN_CONFIG.RULES.find(str(config["rule"])), 0))
	batch_spin.set_value_no_signal(float(config["batch"]))
	var rule := str(config["rule"])
	batch_row.visible = rule != "stream"
	batch_label.text = "Размер пачки" if rule == "burst" else "Держать рядом, не более"
	trigger_option.select(maxi(SPAWN_CONFIG.TRIGGERS.find(str(config["trigger"])), 0))
	health_spin.set_value_no_signal(float(config["health"]))
	damage_spin.set_value_no_signal(float(config["damage"]))
	if objects.selected == null:
		link_note.text = "После размещения выберите врага и отметьте эту точку."
		return
	var count := linked_enemies(_point_id(point)).size()
	link_note.text = "Связано врагов: %d" % count if count > 0 else "Нет связанных врагов: волна не запустится. Выберите врага и отметьте эту точку."


func _load_enemy(enemy: Node3D) -> void:
	for child in link_list.get_children():
		link_list.remove_child(child)
		child.queue_free()
	var ids := Array(enemy.get_meta(DIRECTOR.TRIGGER_META, []))
	var points := _points()
	if points.is_empty():
		var empty := Label.new()
		empty.text = "На карте нет точек спавна."
		link_list.add_child(empty)
	for index in points.size():
		var id := _point_id(points[index])
		var box := CheckBox.new()
		box.text = "Точка %d: %s (%.0f, %.0f)" % [index + 1, SPAWN_CONFIG.summary(points[index].call("get_spawn_config")), points[index].position.x, points[index].position.z]
		box.button_pressed = ids.has(id)
		box.toggled.connect(_toggle_link.bind(id))
		link_list.add_child(box)


func _toggle_link(on: bool, point_id: String) -> void:
	var enemy: Node3D = objects.selected
	if _updating or not _is_enemy(enemy):
		return
	session.edit_history.call("record_transform", enemy)
	var ids := Array(enemy.get_meta(DIRECTOR.TRIGGER_META, []))
	if on and not ids.has(point_id):
		ids.append(point_id)
	elif not on:
		ids.erase(point_id)
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


func _read_config() -> Dictionary:
	return {
		"enemy": SPAWN_CONFIG.ENEMIES[enemy_option.selected], "count": int(count_spin.value),
		"interval": interval_spin.value, "rule": SPAWN_CONFIG.RULES[rule_option.selected],
		"batch": int(batch_spin.value), "trigger": SPAWN_CONFIG.TRIGGERS[trigger_option.selected],
		"health": health_spin.value, "damage": damage_spin.value,
	}


func _changed(_value: Variant = null) -> void:
	if _updating:
		return
	var point := _point_target()
	if point == null:
		return
	if objects.selected != null:
		session.edit_history.call("record_transform", point)
	var config := _read_config()
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
			if Array(selected.get_meta(DIRECTOR.TRIGGER_META, [])).has(_point_id(point)):
				pairs.append([selected.global_position, point.global_position])
	elif selected != null and selected.has_method("configure_spawn"):
		for enemy in linked_enemies(_point_id(selected)):
			pairs.append([enemy.global_position, selected.global_position])
	if pairs.is_empty():
		return
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for pair in pairs:
		mesh.surface_add_vertex(pair[0] + LINK_LIFT)
		mesh.surface_add_vertex(pair[1] + LINK_LIFT)
	mesh.surface_end()
