extends RefCounted
## One named-map transaction: covered, non-editable preparation and staged replacement.
const LOADER := preload("res://game/bootstrap/app/planning_layout_loader.gd")
const MAP_FILE := preload("res://game/bootstrap/app/planning_map_file.gd")
var _session: Node
var _objects: Node
var _cover: CanvasLayer
var _label: Label
var _bar: ProgressBar
var _focus: WeakRef
var _ui_mode: int
var _phase := ""


func _init(session: Node, objects: Node) -> void:
	_session = session
	_objects = objects


func run(path: String, storage: RefCounted) -> Dictionary:
	var tree := _session.get_tree()
	_show_cover()
	# Let the cover render before file parsing and foreground scene construction.
	await tree.process_frame
	await tree.process_frame
	if not _alive():
		_close_cover()
		return {"error": "loading cancelled"}
	var read := MAP_FILE.read(path)
	var report := read
	if not read.has("error"):
		var loader := LOADER.new(_objects)
		var prepared := await loader.prepare_async(read.data, tree, _progress, _alive)
		report = prepared
		if not prepared.has("error"):
			_progress(0.6, "free")
			if await loader.clear_async(tree, _progress, _alive):
				report = await loader.commit_async(prepared, tree, _progress, _alive, true)
			else:
				loader._discard(prepared)
				report = {"error": "loading cancelled"}
	if _alive() and not report.has("error"):
		_progress(0.95, "snapshot")
		if not await storage.snapshot_authored_async(tree, _progress, _alive):
			report = {"error": "loading cancelled"}
	if _alive():
		_progress(1.0, "ready")
	_close_cover()
	return report


func _alive() -> bool:
	return is_instance_valid(_session) and _session.is_inside_tree() and not _session.is_queued_for_deletion() \
		and is_instance_valid(_objects) and _objects.is_inside_tree() and not _objects.is_queued_for_deletion()


func _show_cover() -> void:
	_ui_mode = _session.ui.process_mode
	_session.ui.process_mode = Node.PROCESS_MODE_DISABLED
	var focused := _session.get_viewport().gui_get_focus_owner()
	if focused != null:
		_focus = weakref(focused)
		focused.release_focus()
	_cover = CanvasLayer.new()
	_cover.layer = 250
	_cover.process_mode = Node.PROCESS_MODE_ALWAYS
	_session.add_child(_cover)
	var shade := ColorRect.new()
	shade.color = Color("080b0e")
	shade.focus_mode = Control.FOCUS_ALL
	_cover.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.grab_focus()
	var center := CenterContainer.new()
	shade.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(420, 0)
	center.add_child(column)
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_label)
	_bar = ProgressBar.new()
	column.add_child(_bar)
	_progress(0.0, "read")


func _progress(value: float, phase: String) -> void:
	if not _alive():
		return
	if phase != _phase:
		_phase = phase
		print("Named map phase: %s; allocator %.3f MiB" % [phase, float(OS.get_static_memory_usage()) / 1048576.0])
	_bar.value = maxf(_bar.value, value * 100.0)
	var names := {"read": "Reading map…", "resources": "Loading resources…", "prepare": "Preparing map…", "free": "Releasing previous map…", "objects": "Building map…", "ready": "Ready", "attachments": "Restoring attachments…", "snapshot": "Capturing authored map…"}
	_label.text = names[phase]


func _close_cover() -> void:
	if is_instance_valid(_cover):
		_cover.queue_free()
	if not is_instance_valid(_session) or not is_instance_valid(_session.ui):
		return
	_session.ui.process_mode = _ui_mode
	if _focus != null:
		var focused := _focus.get_ref() as Control
		if is_instance_valid(focused) and focused.is_visible_in_tree():
			focused.grab_focus()
