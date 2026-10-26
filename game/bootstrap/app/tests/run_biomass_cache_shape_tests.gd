extends SceneTree
## Real fixture capture must invalidate old pixels after an unsaved shape edit.
const BAKE := preload("res://game/bootstrap/app/planning_biomass_bake.gd")
const CAPTURE := preload("res://game/bootstrap/app/planning_layout_capture.gd")
const LOADER := preload("res://game/bootstrap/app/planning_layout_loader.gd")
const VIEW := preload("res://game/presentation/office_floor/public/baked_biomass_floor.gd")
const LAMP := preload("res://game/presentation/office_floor/public/props/planner_light.tscn")
var failures := 0
var session: Session
var editor: Editor
var fixture: Node3D
var source: Source
var png: String

class Session extends Node3D:
	var host: Node3D
	var root: Node3D
	var active := false
	var storage := {"authored_layout": {}}

class Editor extends Node:
	var session: Session
	var catalog := Catalog.new()
	var geometry: Variant
	var controls: Variant
	var keep_on_clear := {}
	var unresolved_records: Array = []
	var player_spawn_defined := false

class Catalog extends RefCounted:
	func _migrate_scene_path(path: String) -> String: return path
	func _create_asset(_path: String) -> Node3D: return LAMP.instantiate()

class Source extends Node3D:
	var baked := false
	func set_floor_biomass_baked(value: bool) -> void: baked = value


func _initialize() -> void: call_deferred("_run")


func _run() -> void:
	session = Session.new()
	session.host = session
	session.root = Node3D.new()
	session.add_child(session.root)
	root.add_child(session)
	editor = Editor.new()
	editor.session = session
	session.add_child(editor)
	fixture = LAMP.instantiate()
	fixture.set_meta("planning_scene_path", LAMP.resource_path)
	session.root.add_child(fixture)
	source = Source.new()
	session.root.add_child(source)
	var image := Image.create(512, 512, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.2, 0.3, 0.4, 1))
	png = Marshalls.raw_to_base64(image.save_png_to_buffer())
	for before in ["point", "linear", "rectangle"]:
		for after in ["point", "linear", "rectangle"]:
			if before != after: await _transition(before, after)
	_legacy_and_canonical()
	session.queue_free()
	await process_frame
	await process_frame
	print("Biomass cache shape tests: %d failures" % failures)
	quit(0 if failures == 0 else 1)


func _capture(shape: String) -> Dictionary:
	fixture.call("configure_fixture", shape, false)
	return CAPTURE.collect(editor, [fixture])


func _cache(records: Array) -> Dictionary:
	return {"version": 1, "y": 0.0, "pages": [{"x": 0, "z": 0, "png": png}],
		"source_signature": BAKE.signature(records)}


func _transition(before: String, after: String) -> void:
	var original := _capture(before)
	var cache := _cache(original.objects)
	BAKE.restore(session, cache)
	session.storage.authored_layout = original
	BAKE.editing(session, true)
	var view: Node3D = session.root.get_node("BakedFloorBiomass")
	_check(not view.visible and not source.baked, "Entering planner shows editable source")
	BAKE.editing(session, false)
	_check(view.visible and source.baked, "Unchanged fixture retains its cached page")
	BAKE.editing(session, true)
	var changed := _capture(after)
	_check(changed.objects[0].fixture_shape == after, "Real fixture shape is captured")
	_check(BAKE.signature(original.objects) != BAKE.signature(changed.objects), "Shape edit changes cache signature: %s -> %s" % [before, after])
	session.storage.authored_layout = changed
	BAKE.editing(session, false)
	_check(not view.visible and not source.baked, "Unsaved shape edit hides stale pixels and retains source")
	changed.floor_biomass_v1 = cache
	await _prepared(changed, false)
	# A subsequent save stamps the current signature and can display the new page.
	var refreshed := _cache(changed.objects)
	changed.floor_biomass_v1 = refreshed
	await _prepared(changed, true)
	BAKE.restore(session, refreshed)
	BAKE.editing(session, false)
	_check(session.root.get_node("BakedFloorBiomass").visible and source.baked, "Refreshed signature permits the saved page again")
	# Undoing to the original shape makes the original page applicable again.
	_capture(before)
	session.storage.authored_layout = original
	BAKE.restore(session, cache)
	BAKE.editing(session, false)
	_check(session.root.get_node("BakedFloorBiomass").visible, "Reverting the shape restores cache applicability")


func _prepared(data: Dictionary, accepted: bool) -> void:
	var roundtrip: Dictionary = JSON.parse_string(JSON.stringify(data))
	var loader := LOADER.new(editor)
	var sync: Dictionary = loader.prepare(roundtrip)
	_check(not sync.has("error") and not sync.floor_biomass_v1.is_empty() == accepted, "Sync loader filters stale shape cache without rejecting source map")
	loader._discard(sync)
	var async_plan: Dictionary = await loader.prepare_async(roundtrip, self, func(_ratio: float, _phase: String) -> void: pass)
	_check(not async_plan.has("error") and not async_plan.floor_biomass_v1.is_empty() == accepted, "Async loader uses the same cache applicability after JSON roundtrip")
	loader._discard(async_plan)


func _legacy_and_canonical() -> void:
	var data := _capture("rectangle")
	_check(BAKE.signature(data.objects) == BAKE.signature(JSON.parse_string(JSON.stringify(data.objects))), "Shape signature preserves JSON integer/float equivalence")
	data.objects[0].x = -0.0
	var signed := BAKE.signature(data.objects)
	data.objects[0].x = 0.0
	_check(signed == BAKE.signature(data.objects), "Signed zero remains canonical")
	data.objects[0].erase("fixture_shape")
	var loader := LOADER.new(editor)
	var plan: Dictionary = loader.prepare(data)
	_check(not plan.has("error"), "Legacy map without shape or cache still loads")
	loader._discard(plan)


func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
