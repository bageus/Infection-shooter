extends SceneTree
const FLOOR := preload("res://game/presentation/office_floor/public/base_floor_renderer.gd")
const OPTIONS := preload("res://game/bootstrap/app/planning_surface_decal_options.gd")
const SETTINGS := preload("res://game/bootstrap/app/planning_surface_decals.gd")
const CAPTURE := preload("res://game/bootstrap/app/planning_layout_capture.gd")
const VALIDATOR := preload("res://game/bootstrap/app/planning_layout_validator.gd")
const STORAGE := preload("res://game/bootstrap/app/planning_storage.gd")
const BAKE := preload("res://game/bootstrap/app/planning_scene_bake.gd")
class Session extends Node:
	var host: Node3D
	var root: Node3D
	var ui: Control
class Objects extends Node:
	var session: Node
	var player_spawn_defined := false
var failures := 0
func _init() -> void: call_deferred("_run")

func _run() -> void:
	var session := Session.new()
	root.add_child(session)
	session.host = Node3D.new()
	session.add_child(session.host)
	var floor_view := FLOOR.new()
	floor_view.name = "Floor"
	session.host.add_child(floor_view)
	session.root = Node3D.new()
	session.host.add_child(session.root)
	session.ui = Control.new()
	session.add_child(session.ui)
	var panel := PanelContainer.new()
	panel.name = "Panel"
	session.ui.add_child(panel)
	var box := VBoxContainer.new()
	box.name = "VBox"
	panel.add_child(box)
	var options := OPTIONS.new()
	session.add_child(options)
	options.setup(session)
	options._select()
	options.opacity.value = 27
	options.size.value = 1.55
	_check(is_equal_approx(floor_view.get_surface_decals().glass.opacity, 0.27), "Planner opacity updates owner")
	_check(is_equal_approx(floor_view.get_surface_decals().glass.size, 1.55), "Planner size updates owner")
	_check(options.preview.texture != null and is_equal_approx(options.preview.modulate.a, 0.27), "Atlas and opacity preview visible")
	var objects := Objects.new()
	objects.session = session
	var captured := CAPTURE.collect(objects, [])
	var decoded: Dictionary = JSON.parse_string(JSON.stringify(captured))
	_check(VALIDATOR.error(decoded).is_empty() and decoded.surface_decals_v1 == floor_view.get_surface_decals(), "Save Layout settings survive JSON round trip")
	SETTINGS.restore(session, {})
	SETTINGS.restore(session, decoded.surface_decals_v1)
	_check(floor_view.get_surface_decals() == captured.surface_decals_v1, "Loading restores authored settings")
	_check(STORAGE._signature(decoded) != STORAGE._signature({"version": 8, "objects": []}), "Settings-only edit affects authored restore signature")
	var bad := decoded.duplicate(true)
	bad.surface_decals_v1.glass.opacity = -1
	_check(not VALIDATOR.error(bad).is_empty(), "Invalid settings rejected before map replacement")
	_check(VALIDATOR.error({"version": 8, "objects": []}).is_empty(), "Old maps need no migration")
	var bake := BAKE.new(null)
	bake.surface_settings = SETTINGS.capture(session)
	var path := "user://surface_decal_scene_test.tscn"
	_check(bake._write(Node3D.new(), path) == OK, "Scene export stores settings metadata")
	var restored := (load(path) as PackedScene).instantiate()
	_check(restored.get_meta("surface_decals_v1") == floor_view.get_surface_decals(), "Scene bake and JSON preserve identical settings")
	restored.free()
	DirAccess.remove_absolute(path)
	objects.free()
	session.queue_free()
	await process_frame
	await process_frame
	print("Surface decal options tests: %d failures" % failures)
	quit(0 if failures == 0 else 1)

func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
