extends Control
## Enemy animation page: pick an enemy, then play any clip it has in the game.
## Drag the view or hold Z/X to orbit, scroll to zoom. Run enemy_anim_viewer.tscn; it needs no game state.
## Zooming out switches mesh LODs the way the game does (same camera FOV); the panel shows the distance and
## the LOD Godot is drawing, read from the triangles the view rendered.

const CATALOG := preload("res://game/bootstrap/app/enemy_anim_viewer/enemy_anim_catalog.gd")
const ORBIT_SPEED := 1.6 # rad/s while Z or X is held
const FOV := 50.0 # the game camera's FOV, so LODs switch at the same distances as in play
const MAX_DISTANCE := 30.0 # past the game camera's 24 m
const FRAMING := 1.35 # room around the body so head and feet stay in view
const BLEND := 0.15

var _enemies: Array[String] = []
var _enemy_select: OptionButton
var _clip_list: ItemList
var _pause: Button
var _loop: CheckBox
var _info: Label
var _lod_info: Label
var _lod_triangles: Array[int] = [] # triangles drawn at LOD 0, 1, 2...
var _container: SubViewportContainer
var _view: SubViewport
var _camera: Camera3D
var _body: Node3D
var _player: AnimationPlayer
var _center := Vector3.ZERO
var _fit_distance := 4.0
var _distance := 4.0
var _yaw := 0.0
var _pitch := 0.15
var _dragging := false


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var split := HSplitContainer.new()
	split.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	split.split_offset = 280
	add_child(split)
	var panel := VBoxContainer.new()
	panel.custom_minimum_size.x = 260
	split.add_child(panel)
	_enemy_select = OptionButton.new()
	_enemy_select.item_selected.connect(_show_enemy)
	panel.add_child(_enemy_select)
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(_info)
	_lod_info = Label.new()
	panel.add_child(_lod_info)
	_clip_list = ItemList.new()
	_clip_list.size_flags_vertical = SIZE_EXPAND_FILL
	_clip_list.item_selected.connect(func(index: int) -> void: _play(_clip_list.get_item_metadata(index)))
	panel.add_child(_clip_list)
	_loop = CheckBox.new()
	_loop.text = "Зациклить"
	_loop.button_pressed = true
	panel.add_child(_loop)
	_pause = Button.new()
	_pause.text = "Пауза"
	_pause.toggle_mode = true
	_pause.toggled.connect(func(paused: bool) -> void: _set_speed(0.0 if paused else 1.0))
	panel.add_child(_pause)
	var reset := Button.new()
	reset.text = "Сбросить вид"
	reset.pressed.connect(_reset_view)
	panel.add_child(reset)
	_build_view(split)
	_enemies = CATALOG.enemy_scene_paths()
	for path in _enemies:
		_enemy_select.add_item(CATALOG.enemy_name(path))
	if not _enemies.is_empty():
		_show_enemy(0)


func _build_view(split: HSplitContainer) -> void:
	_container = SubViewportContainer.new()
	_container.size_flags_horizontal = SIZE_EXPAND_FILL
	_container.stretch = true
	split.add_child(_container)
	_view = SubViewport.new()
	_view.own_world_3d = true
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_container.add_child(_view)
	_view.add_child(_environment())
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, 30, 0)
	_view.add_child(light)
	_camera = Camera3D.new()
	_camera.fov = FOV
	_camera.current = true
	_view.add_child(_camera)


func _environment() -> WorldEnvironment:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.13, 0.14, 0.16)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.78, 0.78, 0.74)
	env.ambient_light_energy = 0.9
	var node := WorldEnvironment.new()
	node.environment = env
	return node


func _show_enemy(index: int) -> void:
	if _body != null:
		_body.free()
		_body = null
	_clip_list.clear()
	_player = null
	var body := CATALOG.load_body(_enemies[index])
	if body == null:
		_info.text = "У этого врага нет анимированного тела."
		return
	_body = body
	_view.add_child(body)
	_player = CATALOG.find_player(body)
	var clips := Array(_player.get_animation_list())
	clips.sort()
	for clip in clips:
		var i := _clip_list.add_item("%s (%.2f с)" % [clip, _player.get_animation(clip).length])
		_clip_list.set_item_metadata(i, clip)
	_info.text = "%s: клипов %d" % [CATALOG.enemy_name(_enemies[index]), clips.size()]
	_frame(body)
	_lod_triangles = _lod_levels(body)
	_reset_view()
	if clips.has("Idle"):
		_play("Idle")
	elif not clips.is_empty():
		_play(clips[0])


# Fits the camera distance to the body's mesh bounds at rest, the same way the tutorial preview does.
func _frame(body: Node3D) -> void:
	var box := AABB(Vector3(-0.5, 0.0, -0.5), Vector3(1.0, 2.0, 1.0))
	var found := false
	for mesh: MeshInstance3D in body.find_children("*", "MeshInstance3D", true, false):
		var local := mesh.global_transform * mesh.get_aabb()
		box = local if not found else box.merge(local)
		found = true
	_center = box.get_center()
	_fit_distance = box.size.y * 0.5 / tan(deg_to_rad(FOV) * 0.5) * FRAMING


# Triangles of every LOD level of the body meshes (a surface without that level keeps its last one).
static func _lod_levels(body: Node3D) -> Array[int]:
	var surfaces: Array = []
	var levels := 1
	for mesh_instance: MeshInstance3D in body.find_children("*", "MeshInstance3D", true, false):
		if mesh_instance.mesh == null:
			continue
		for surface in mesh_instance.mesh.get_surface_count():
			var stored := RenderingServer.mesh_get_surface(mesh_instance.mesh.get_rid(), surface)
			var stride := RenderingServer.mesh_surface_get_format_index_stride(stored.format, stored.vertex_count)
			var counts: Array[int] = [stored.index_count / 3]
			for lod: Dictionary in stored.get("lods", []):
				counts.append((lod.index_data as PackedByteArray).size() / stride / 3)
			surfaces.append(counts)
			levels = maxi(levels, counts.size())
	var result: Array[int] = []
	for level in levels:
		var total := 0
		for counts: Array[int] in surfaces:
			total += counts[mini(level, counts.size() - 1)]
		result.append(total)
	return result


# The LOD whose triangle count is closest to what the view drew last frame.
static func current_lod(levels: Array[int], drawn: int) -> int:
	var best := 0
	for level in levels.size():
		if absi(levels[level] - drawn) < absi(levels[best] - drawn):
			best = level
	return best


func _update_lod_info() -> void:
	if _body == null or _lod_triangles.is_empty():
		_lod_info.text = ""
		return
	var drawn := RenderingServer.viewport_get_render_info(_view.get_viewport_rid(), RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)
	var lod := current_lod(_lod_triangles, drawn)
	_lod_info.text = "Дистанция %.1f м, LOD%d (%d треуг., уровней %d)" % [_distance, lod, drawn, _lod_triangles.size()]


func _play(clip: String) -> void:
	if _player == null:
		return
	_player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR if _loop.button_pressed else Animation.LOOP_NONE
	_player.play(clip, BLEND)
	_set_speed(0.0 if _pause.button_pressed else 1.0)


func _set_speed(speed: float) -> void:
	if _player != null:
		_player.speed_scale = speed


func _reset_view() -> void:
	_yaw = 0.0
	_pitch = 0.15
	_distance = _fit_distance
	_update_camera()


func _update_camera() -> void:
	if _body == null:
		return
	var direction := Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch))
	_camera.position = _center + direction * _distance
	_camera.look_at(_center)


func _process(delta: float) -> void:
	_update_lod_info()
	var turn := (1.0 if Input.is_key_pressed(KEY_X) else 0.0) - (1.0 if Input.is_key_pressed(KEY_Z) else 0.0)
	if turn != 0.0 and _body != null:
		_yaw += turn * ORBIT_SPEED * delta
		_update_camera()


# Input is read before the GUI so the orbit works over the 3D view, while the panel keeps its own clicks.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		var inside := _container.get_global_rect().has_point(button.position)
		if button.button_index == MOUSE_BUTTON_LEFT:
			_dragging = button.pressed and inside
		elif inside and button.pressed and button.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var zoom := 0.9 if button.button_index == MOUSE_BUTTON_WHEEL_UP else 1.1
			_distance = clampf(_distance * zoom, 0.8, MAX_DISTANCE)
			_update_camera()
	elif event is InputEventMouseMotion and _dragging:
		var motion := event as InputEventMouseMotion
		_yaw -= motion.relative.x * 0.01
		_pitch = clampf(_pitch + motion.relative.y * 0.01, -0.3, 1.2)
		_update_camera()
