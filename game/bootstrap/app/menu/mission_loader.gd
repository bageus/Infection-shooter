extends CanvasLayer
## Keep the previous scene until a threaded, staged mission is ready.
signal completed(success: bool)
const RESOURCE_PREPARATION := preload("res://game/bootstrap/app/scene_resource_preparation.gd")
const LAYOUT := preload("res://game/bootstrap/app/planning_layout_loader.gd")
const MATERIAL_WARMUP := preload("res://game/bootstrap/app/mission_material_warmup.gd")
var warmed_materials := 0
var completion_music: Node
## Props need ~160 physics ticks to fall asleep; a slow machine gets a wall-clock cap instead.
const SETTLE_MAX_TICKS := 240
const SETTLE_MAX_MSEC := 10000
const SETTLE_AWAKE_LIMIT := 600
const PHYSICS := preload("res://game/bootstrap/app/planning_physics.gd")
const PREFERENCES := preload("res://game/bootstrap/app/menu/menu_preferences.gd")
const MAIN_PATH := "res://game/bootstrap/app/main.tscn"
const FRONT_END_PATH := "res://game/bootstrap/app/menu/front_end.tscn"
var scene_path := MAIN_PATH
var label: Label
var progress: ProgressBar
var back: Button
var pending: Node3D
var _started := false
var _logged_phase := ""
var _previous_scene: Node3D
var _previous_visible := true
var _previous_collisions: Array[Dictionary] = []
var _previous_camera: Camera3D
var _previous_pause := false
var _previous_mouse := Input.MOUSE_MODE_VISIBLE
var _released_previous := false
var _ru := false
var _recovery_path := ""
var _level_name := ""
var _arrival := {}
var _carry := {}
var _recovery_requested := false
var _choices: VBoxContainer
var _column: VBoxContainer


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
	_column = column
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


## Loads one saved map of the level chain; `arrival` ({x, z}) moves the player to that entry point.
func start_map(path: String, level_name: String, arrival: Dictionary, carry: Dictionary = {}) -> void:
	_recovery_path = path
	_level_name = level_name
	_arrival = arrival
	_carry = carry
	start()


func start() -> void:
	if _started:
		return
	_started = true
	if is_instance_valid(completion_music):
		completion_music.call("to_loading")
	_log_begin()
	var tree := get_tree()
	var previous := tree.current_scene
	if previous is Node3D and previous.scene_file_path == MAIN_PATH:
		# A restart must not hold two missions at once: that doubles peak memory and
		# makes allocations fail on small machines. The mission is gone if loading fails.
		_released_previous = true
		_previous_mouse = Input.mouse_mode
		_previous_pause = tree.paused
		tree.paused = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		reparent(tree.root)
		tree.current_scene = null
		previous.queue_free()
		await tree.process_frame
		await tree.process_frame
		previous = null
	elif previous is Node3D:
		_previous_scene = previous
		_previous_visible = previous.visible
		# Retain rollback state, but do not render the old floor behind the overlay.
		previous.hide()
		_suspend_previous_collisions(previous)
	if not _released_previous:
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
	var read: Dictionary = storage.read_startup_layout(_recovery_path)
	if read.has("error"):
		_fail(str(read.error))
		_offer_recovery(read.get("recovery", []))
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
	_enter_level(planner)
	# Keep physics paused and cover the first real material draws with the overlay.
	pending.show()
	await _install_occlusion_walls(tree)
	var warmup := MATERIAL_WARMUP.new()
	await warmup.prepare(pending, pending.get_viewport().get_camera_3d(), tree, _set_progress)
	warmed_materials = warmup.material_count
	PHYSICS.resume(planner.get("objects").get("placed"))
	await _settle_props(tree)
	_set_progress(1.0, "ready")
	await tree.process_frame
	_activate_pending(tree, previous)


func _activate_pending(tree: SceneTree, previous: Node) -> void:
	tree.current_scene = pending
	pending.show()
	var preferences := PREFERENCES.new()
	preferences.load_settings()
	preferences.apply_to_game(tree)
	if is_instance_valid(completion_music):
		completion_music.call("release_to_mission")
		completion_music = null
	tree.paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	pending = null
	_previous_collisions.clear()
	_previous_scene = null
	completed.emit(true)
	if is_instance_valid(previous):
		previous.queue_free()
	queue_free()


func _log_begin() -> void:
	print("Mission begin: texture profile 1K; renderer %s; allocator %.1f MiB" % [
		RenderingServer.get_current_rendering_method(), float(OS.get_static_memory_usage()) / 1048576.0])


## Chain travel: the player appears at the entry point that leads back to the previous map.
func _enter_level(planner: Node) -> void:
	pending.set("current_level", _level_name)
	if not _carry.is_empty():
		pending.call("apply_carry", _carry)
	if _arrival.has("x"):
		(planner.get("main_player") as Node3D).position = Vector3(float(_arrival.x), 1.0, float(_arrival.z))


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
	if phase != _logged_phase:
		_logged_phase = phase
		print("Mission phase: %s; allocator %.1f MiB; video %.1f MiB" % [phase,
			float(OS.get_static_memory_usage()) / 1048576.0,
			float(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) / 1048576.0])
	progress.value = maxf(progress.value, value * 100.0)
	var names := {"resources": "Загрузка ресурсов…", "prepare": "Подготовка карты…", "objects": "Создание локации…", "materials": "Подготовка текстур…", "ready": "Готово"} if _ru else {"resources": "Loading resources…", "prepare": "Preparing map…", "objects": "Building location…", "materials": "Preparing textures…", "ready": "Ready"}
	label.text = names[phase]


func _fail(reason: String) -> void:
	_recovery_requested = false
	_restore_previous_visual()
	if pending != null:
		pending.queue_free()
		pending = null
	if is_instance_valid(_previous_camera) and _previous_camera.is_inside_tree():
		_previous_camera.make_current()
	get_tree().paused = _previous_pause
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	label.text = ("Ошибка загрузки: " if _ru else "Loading failed: ") + reason
	if reason.to_lower().contains("cannot load") or reason.contains("Не удалось загрузить"):
		label.text += "\n" + ("Возможно, не хватает оперативной памяти: закройте другие программы и повторите." if _ru else "The computer may be out of memory: close other programs and try again.")
	progress.hide()
	back.show()
	back.grab_focus()


func _close_error() -> void:
	Input.mouse_mode = _previous_mouse
	completed.emit(false)
	if _released_previous or is_instance_valid(completion_music):
		preload("res://game/bootstrap/app/menu/music_navigation.gd").show_main(get_tree(), get_tree().current_scene, completion_music)
		completion_music = null
	queue_free()


func _suspend_previous_collisions(node: Node) -> void:
	if node is CollisionObject3D:
		var body := node as CollisionObject3D
		_previous_collisions.append({"node": weakref(body), "layer": body.collision_layer, "mask": body.collision_mask})
		body.collision_layer = 0
		body.collision_mask = 0
	for child in node.get_children():
		_suspend_previous_collisions(child)


func _restore_previous_visual() -> void:
	for saved in _previous_collisions:
		var body := (saved.node as WeakRef).get_ref() as CollisionObject3D
		if is_instance_valid(body):
			body.collision_layer = int(saved.layer)
			body.collision_mask = int(saved.mask)
	_previous_collisions.clear()
	if is_instance_valid(_previous_scene):
		_previous_scene.visible = _previous_visible


func _exit_tree() -> void:
	if is_instance_valid(completion_music):
		completion_music.call("dispose")
		completion_music = null
	_restore_previous_visual()
	if is_instance_valid(pending):
		pending.queue_free()


func _offer_recovery(choices: Array) -> void:
	if choices.is_empty():
		return
	label.text += "\n" + ("Сохранение не изменено. Выберите карту для запуска:" if _ru else "Your save is unchanged. Choose a map to start:")
	_choices = VBoxContainer.new()
	_column.add_child(_choices)
	for candidate: Dictionary in choices:
		var button := Button.new()
		button.text = ("Загрузить резервную копию" if _ru else "Load backup") if candidate.kind == "backup" else ("Загрузить штатную карту" if _ru else "Load shipped map")
		button.pressed.connect(_retry_recovery.bind(str(candidate.path)))
		_choices.add_child(button)


func _retry_recovery(path: String) -> void:
	if _recovery_requested:
		return
	_recovery_requested = true
	_recovery_path = path
	if is_instance_valid(_choices):
		_choices.queue_free()
	back.hide()
	progress.show()
	progress.value = 0
	_started = false
	start()


## Wall see-through materials are swapped in lazily; install them before the warm-up so it covers them.
## The saved mode is applied here, not after the overlay drops, or the queue would only fill during play.
func _install_occlusion_walls(tree: SceneTree) -> void:
	var occlusion := pending.get_node_or_null("OcclusionEffects")
	if occlusion == null:
		return
	var saved := PREFERENCES.new()
	saved.load_settings()
	occlusion.call("set_mode", int(saved.values.occlusion_mode))
	await occlusion.flush_wall_queue(tree)


## Props start awake and every one costs a physics tick until it sleeps, which showed as ~1 FPS right after
## the overlay dropped. Step only the physics server (nodes stay paused) until most props are asleep.
func _settle_props(tree: SceneTree) -> void:
	var bodies: Array[Node] = pending.find_children("*", "RigidBody3D", true, false)
	if bodies.all(func(body: Node) -> bool: return not is_instance_valid(body) or (body as RigidBody3D).freeze or bool(PhysicsServer3D.body_get_state(body.get_rid(), PhysicsServer3D.BODY_STATE_SLEEPING))):
		return
	var started := Time.get_ticks_msec()
	var first_tick := Engine.get_physics_frames()
	PhysicsServer3D.set_active(true)
	while Time.get_ticks_msec() - started < SETTLE_MAX_MSEC and Engine.get_physics_frames() - first_tick < SETTLE_MAX_TICKS:
		await tree.process_frame
		var awake := 0
		for body: Node in bodies:
			if is_instance_valid(body) and not (body as RigidBody3D).freeze and not (body as RigidBody3D).sleeping:
				awake += 1
		if awake <= SETTLE_AWAKE_LIMIT:
			break
	PhysicsServer3D.set_active(not tree.paused)
