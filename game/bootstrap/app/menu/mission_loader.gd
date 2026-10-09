extends CanvasLayer
## Keep the previous scene until a threaded, staged mission is ready.
signal completed(success: bool)
const RESOURCE_PREPARATION := preload("res://game/bootstrap/app/scene_resource_preparation.gd")
const LAYOUT := preload("res://game/bootstrap/app/planning_layout_loader.gd")
const PHYSICS := preload("res://game/bootstrap/app/planning_physics.gd")
const PREFERENCES := preload("res://game/bootstrap/app/menu/menu_preferences.gd")
const MAIN_PATH := "res://game/bootstrap/app/main.tscn"
var scene_path := MAIN_PATH
var label: Label
var progress: ProgressBar
var back: Button
var pending: Node3D
var _started := false
var _previous_scene: Node3D
var _previous_visible := true
var _previous_camera: Camera3D
var _previous_pause := false
var _previous_mouse := Input.MOUSE_MODE_VISIBLE
var _ru := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 250
	var preferences := PREFERENCES.new()
	preferences.load_settings()
	_ru = preferences.values.language == "ru"
	var shade := ColorRect.new()
	shade.color = Color("080b0e")
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	shade.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(440, 0)
	column.add_theme_constant_override("separation", 18)
	center.add_child(column)
	label = Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = "Загрузка миссии…" if _ru else "Loading mission…"
	column.add_child(label)
	progress = ProgressBar.new()
	progress.show_percentage = false
	column.add_child(progress)
	back = Button.new()
	back.text = "Назад" if _ru else "Back"
	back.hide()
	back.pressed.connect(_close_error)
	column.add_child(back)


func start() -> void:
	if _started:
		return
	_started = true
	var tree := get_tree()
	var previous := tree.current_scene
	if previous is Node3D:
		_previous_scene = previous
		_previous_visible = previous.visible
		# Retain rollback state, but do not render the old floor behind the overlay.
		previous.hide()
	_previous_camera = get_viewport().get_camera_3d()
	_previous_pause = tree.paused
	_previous_mouse = Input.mouse_mode
	tree.paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Render the overlay before any foreground instantiation.
	await tree.process_frame
	await tree.process_frame
	var scripts := RESOURCE_PREPARATION.new()
	if not await scripts.prepare(scene_path, tree):
		_fail("Cannot prepare mission scripts")
		return
	var packed := await _request_scene(tree)
	if packed == null:
		return
	_set_progress(0.15, "prepare")
	await tree.process_frame
	var instance := packed.instantiate()
	if not instance is Node3D:
		instance.free()
		_fail("Invalid mission root")
		return
	pending = instance as Node3D
	pending.set("defer_layout_loading", true)
	pending.hide()
	tree.root.add_child(pending)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await tree.process_frame
	var planner: Node = pending.get("planning_mode")
	var storage: Variant = planner.get("storage")
	var read: Dictionary = storage.read_startup_layout()
	if read.has("error"):
		_fail(str(read.error))
		return
	var layout := LAYOUT.new(planner.get("objects"))
	var prepared := await layout.prepare_async(read.data, tree, _set_progress)
	if prepared.has("error"):
		_fail(str(prepared.error))
		return
	var report := await layout.commit_async(prepared, tree, _set_progress)
	if int(report.skipped) > 0:
		push_warning("Planned layout: %d missing object(s) skipped: %s" % [report.skipped, ", ".join(report.missing)])
	storage.snapshot_authored()
	PHYSICS.resume(planner.get("objects").get("placed"))
	_set_progress(1.0, "ready")
	await tree.process_frame
	tree.current_scene = pending
	pending.show()
	var preferences := PREFERENCES.new()
	preferences.load_settings()
	preferences.apply_to_game(tree)
	tree.paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	pending = null
	_previous_scene = null
	completed.emit(true)
	if is_instance_valid(previous):
		previous.queue_free()
	queue_free()


func _request_scene(tree: SceneTree) -> PackedScene:
	if ResourceLoader.load_threaded_request(scene_path, "PackedScene", false) != OK:
		_fail("Не удалось открыть миссию." if _ru else "Cannot open mission.")
		return null
	var status := ResourceLoader.load_threaded_get_status(scene_path)
	while status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		var fraction: Array = []
		status = ResourceLoader.load_threaded_get_status(scene_path, fraction)
		_set_progress(0.15 * float(fraction[0]) if not fraction.is_empty() else 0.0, "resources")
		await tree.process_frame
	if status != ResourceLoader.THREAD_LOAD_LOADED:
		_fail("Не удалось загрузить миссию." if _ru else "Cannot load mission.")
		return null
	var packed := ResourceLoader.load_threaded_get(scene_path) as PackedScene
	if packed == null:
		_fail("Invalid mission scene")
	return packed


func _set_progress(value: float, phase: String) -> void:
	progress.value = maxf(progress.value, value * 100.0)
	var names := {"resources": "Загрузка ресурсов…", "prepare": "Подготовка карты…", "objects": "Создание локации…", "ready": "Готово"} if _ru else {"resources": "Loading resources…", "prepare": "Preparing map…", "objects": "Building location…", "ready": "Ready"}
	label.text = names[phase]


func _fail(reason: String) -> void:
	_restore_previous_visual()
	if pending != null:
		pending.queue_free()
		pending = null
	if is_instance_valid(_previous_camera) and _previous_camera.is_inside_tree():
		_previous_camera.make_current()
	get_tree().paused = _previous_pause
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	label.text = ("Ошибка загрузки: " if _ru else "Loading failed: ") + reason
	progress.hide()
	back.show()
	back.grab_focus()


func _close_error() -> void:
	Input.mouse_mode = _previous_mouse
	completed.emit(false)
	queue_free()


func _restore_previous_visual() -> void:
	if is_instance_valid(_previous_scene):
		_previous_scene.visible = _previous_visible


func _exit_tree() -> void:
	_restore_previous_visual()
	if is_instance_valid(pending):
		pending.queue_free()
