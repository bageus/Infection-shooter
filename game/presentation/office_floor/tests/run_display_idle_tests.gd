extends SceneTree
## Real DisplayView lifecycle and a bounded CPU-only registry callback fixture.
const WALL := preload("res://game/presentation/office_floor/public/display_wall.gd")
const VIEW := preload("res://game/presentation/office_floor/display_view.gd")
const CONTENT := preload("res://game/presentation/office_floor/display_content.gd")
const MODEL := "res://models/objects/enviroments/05/05_monitor2_destructible.glb"
var failures := 0
var stage: Node3D
var camera: Camera3D
var wall: Node
var views: Array[Node3D] = []

class ObservedWall extends WALL:
	var refreshes := 0
	func _refresh_lights(capture_inputs: bool = true) -> void:
		refreshes += 1
		super._refresh_lights(capture_inputs)

class ObservedContent extends CONTENT:
	var frame_reads := 0
	func frame_rect(index: int, seconds: float) -> Vector4:
		frame_reads += 1
		return super.frame_rect(index, seconds)

class ObservedView extends VIEW:
	var ticks := 0
	func tick(seconds: float, frames: Array[Vector4]) -> void:
		ticks += 1
		super.tick(seconds, frames)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	camera = Camera3D.new()
	stage.add_child(camera)
	camera.position = Vector3(0, 20, 0)
	camera.rotation_degrees.x = -90
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 100
	camera.current = true
	wall = ObservedWall.new()
	wall.content = ObservedContent.new()
	stage.add_child(wall)
	wall.set_process(false)
	for index in 180:
		var holder := Node3D.new()
		stage.add_child(holder)
		holder.position = Vector3(index * .15, 1, 0)
		var view := ObservedView.new()
		holder.add_child(view)
		view.setup(holder, MODEL, {"power": "on", "content": "static", "seed": 2}, wall)
		views.append(view)
	await _flush()
	_benchmark()
	if not "--bench-only" in OS.get_cmdline_user_args():
		print("DISPLAY_POLLED_INPUTS ", wall._light_inputs.size())
		_check(wall._light_inputs.is_empty(), "Managed idle displays need no polled transform/light snapshots")
		await _exercise_changes()
		await _exercise_motion_cadence()
		await _exercise_animation()
		await _exercise_rebind()
	stage.free()
	await process_frame
	print("Display idle tests: %d failure(s)." % failures)
	quit(failures)


func _benchmark() -> void:
	var result := {"displays": views.size(), "polls": 200}
	for moving: bool in [false, true]:
		var samples: Array[int] = []
		for index in 200:
			if moving:
				camera.position.x += .02
			var started := Time.get_ticks_usec()
			wall._process(.2)
			samples.append(Time.get_ticks_usec() - started)
		var total := 0
		for value in samples:
			total += value
		samples.sort()
		result["moving" if moving else "idle"] = {"total_usec": total, "p95_usec": samples[189]}
	print("DISPLAY_IDLE_METRICS ", JSON.stringify(result))
	camera.position.x = 0


func _flush() -> void:
	# Native inherited transform/visibility notifications are delivered before processing.
	await process_frame
	await process_frame
	wall._process(.2)
	wall._process(.2)
	var lit := 0
	var shadows := 0
	for view in views:
		if not is_instance_valid(view):
			continue
		for screen: Dictionary in view.screens:
			lit += int(screen.light.visible)
			shadows += int(screen.light.shadow_enabled)
	_check(lit <= 16 and shadows <= 4, "Real views keep glow16/shadow4 budgets")


func _exercise_changes() -> void:
	await _flush()
	wall.refreshes = 0
	for index in 60:
		wall._process(.2)
	_check(wall.refreshes == 0, "Idle real views do not rerank lights")
	var view: Node3D = views[0]
	var light: SpotLight3D = view.screens[0].light
	_check(light.visible, "Nearest real monitor is lit")
	paused = true
	view.get_parent().position.x = 1000
	await _flush()
	_check(not light.visible, "Inherited movement invalidates glow selection")
	view.get_parent().position.x = 0
	view.get_parent().hide()
	await _flush()
	_check(not light.visible, "Ancestor visibility disables glow")
	view.get_parent().show()
	await _flush()
	_check(light.visible, "Showing the ancestor restores glow")
	light.position.x = 1000
	await _flush()
	_check(not light.visible, "Independent real glow movement invalidates selection")
	light.position.x = 0
	paused = false
	view.powered = false
	await _flush()
	_check(not light.visible, "Direct real power assignment invalidates selection")
	view.configure({"power": "on", "content": "static", "seed": 3})
	await _flush()
	_check(light.visible, "Configure restores powered glow")
	view._build_screen(view.screens[0].profile)
	await _flush()
	_check(view.screens.size() == 2, "Rebuilding a real screen invalidates its topology")
	wall.set_shadows_allowed(false)
	await _flush()
	_check(not light.shadow_enabled, "Shadow settings still apply")


func _exercise_motion_cadence() -> void:
	var view: Node3D = views[0]
	wall.refreshes = 0
	for index in 60:
		view.position.x += .001
		await process_frame
		wall._process(1.0 / 60.0)
	print("DISPLAY_MOTION_REFRESHES ", wall.refreshes)
	_check(wall.refreshes > 0 and wall.refreshes <= 6, "Continuous display motion keeps the .2s budget cadence")
	view.position.x = 0
	await _flush()


func _exercise_animation() -> void:
	var view: Node3D = views[0]
	view.configure({"power": "on", "content": "dynamic", "seed": 2})
	await _flush()
	var before: int = view.ticks
	wall._process(1)
	_check(view.ticks > before, "Visible real displays continue animating")
	camera.position.x = 1000
	await _flush()
	wall.content.frame_reads = 0
	before = view.ticks
	for index in 60:
		wall._process(.2)
	_check(view.ticks == before, "Offscreen real displays receive no ticks")
	print("DISPLAY_OFFSCREEN_FRAME_READS ", wall.content.frame_reads)
	_check(wall.content.frame_reads == 0, "All-offscreen animation skips timeline calculations")
	camera.position.x = 0
	await _flush()
	_check(view.ticks > before, "Returning display catches up to the shared clock")
	var material: ShaderMaterial = view.screens[0].mesh.material_override
	_check(material.get_shader_parameter("atlas_rect") == wall.content.frame_rect(2, wall.elapsed), "Returning screen shows the current authored GIF frame")


func _exercise_rebind() -> void:
	var view: Node3D = views[0]
	var replacement := ObservedWall.new()
	stage.add_child(replacement)
	replacement.set_process(false)
	view.set_registry(replacement)
	_check(not wall.displays.has(view) and replacement.displays.has(view), "Rebinding transfers the registry")
	view.position.x = 1000
	await process_frame
	replacement._process(.2)
	_check(not view.screens[0].light.visible, "Movement invalidates the replacement registry")
	view.set_registry(wall)
	view.position.x = 0
	await _flush()
	var holder := view.get_parent()
	holder.remove_child(view)
	_check(not wall.displays.has(view), "Tree removal unregisters the display")
	holder.add_child(view)
	await _flush()
	_check(wall.displays.has(view), "Tree reentry registers the existing display")
	holder.free()
	views.remove_at(0)
	await _flush()
	_check(wall.displays.size() == views.size(), "Freed views leave no stale registry entry")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
