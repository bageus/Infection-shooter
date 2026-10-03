extends Node3D

const LIBRARY := preload("res://game/presentation/office_floor/blood_texture_library.gd")
const SURFACES := preload("res://game/presentation/office_floor/blood_surface_query.gd")
const BUDGET := preload("res://game/presentation/office_floor/blood_mark_budget.gd")

@export_range(1, 320) var max_marks := 220
@export_range(1.0, 300.0) var mark_lifetime := 90.0
@export_range(0.1, 5.0) var fade_seconds := 1.2
@export var splatter_size := Vector2(0.3, 0.95)
@export var stain_size := Vector2(0.16, 0.50)
@export var drops_size := Vector2(0.25, 0.80)
@export var smear_size := Vector2(0.35, 1.20)
@export var pool_size := Vector2(0.65, 1.50)
@export var drop_spacing := Vector2(0.4, 0.5)
@export_range(1, 8) var splatters_per_hit := 5
@export var pool_delay := Vector2(0.3, 0.8)
@export var pool_growth := Vector2(1.0, 3.0)
@export_range(0.03, 0.15) var projection_depth := 0.08
@export_range(0.001, 0.03) var quad_surface_offset := 0.018
@export_range(0.02, 0.5) var hit_interval := 0.06
@export_flags_3d_physics var surface_collision_mask := 128
@export_flags_3d_render var receiver_visual_mask := 128
@export var distance_fade := true
@export var fade_begin := 24.0
@export var fade_length := 12.0
@export_range(1, 6) var mobile_per_surface_limit := 6
@export_range(128, 1024) var texture_max_dimension := 512
@export_range(0.8, 1.5) var blood_brightness := 1.18
@export var preload_textures := true

var _library := LIBRARY.new()
var _surfaces: Node3D
var _budget: Node3D
var _decal := false
var _hit_times: Dictionary = {}
var _effect_requests: Array[Dictionary] = []
var _diagnostics: Dictionary = {}


func _init() -> void:
	set_meta("blood_effect", true)


func _ready() -> void:
	set_physics_process(false)
	var method := RenderingServer.get_current_rendering_method()
	_diagnostics = {"version": 1, "engine": Engine.get_version_info().get("string", "unknown"), "renderer": method, "api_valid": _verify_engine_api()}
	_decal = method in ["forward_plus", "mobile"]
	if preload_textures:
		_library.load_assets(texture_max_dimension, blood_brightness)
	_surfaces = SURFACES.new() as Node3D
	_surfaces.set("collision_mask", surface_collision_mask)
	_surfaces.set("visual_mask", receiver_visual_mask)
	add_child(_surfaces)
	_budget = BUDGET.new() as Node3D
	_budget.name = "BloodMarkBudget"
	_budget.set("max_marks", max_marks)
	_budget.set("lifetime", mark_lifetime)
	_budget.set("fade_seconds", fade_seconds)
	_budget.set("per_surface_limit", mobile_per_surface_limit if method == "mobile" else 0)
	_budget.set("settings", {
		"decal": _decal, "depth": projection_depth, "quad_offset": quad_surface_offset,
		"visual_mask": receiver_visual_mask, "distance_fade": distance_fade,
		"fade_begin": fade_begin, "fade_length": fade_length, "growth_seconds": 2.0
	})
	add_child(_budget)


func _verify_engine_api() -> bool:
	var required := {
		"Decal": ["texture_albedo", "texture_emission", "size", "cull_mask", "normal_fade", "modulate", "distance_fade_enabled", "distance_fade_begin", "distance_fade_length"],
		"StandardMaterial3D": ["albedo_texture", "albedo_color", "transparency", "billboard_mode", "emission_enabled", "distance_fade_mode", "distance_fade_min_distance", "distance_fade_max_distance"],
		"RemoteTransform3D": ["remote_path", "update_scale"],
		"PhysicsRayQueryParameters3D": ["collision_mask", "exclude"]
	}
	var valid := true
	for type in required:
		var names: Array[String] = []
		for property in ClassDB.class_get_property_list(type):
			names.append(str(property["name"]))
		for property in required[type]:
			if not names.has(property):
				push_error("BloodEffects3D: engine API missing %s.%s" % [type, property])
				valid = false
	for type in ["PhysicsDirectSpaceState3D", "RenderingServer"]:
		var method := "intersect_ray" if type == "PhysicsDirectSpaceState3D" else "get_current_rendering_method"
		if not ClassDB.class_has_method(type, method):
			push_error("BloodEffects3D: engine API missing %s.%s" % [type, method])
			valid = false
	return valid


func diagnostics() -> Dictionary:
	return _diagnostics.duplicate()


func configure_environment(roots: Array[Node]) -> void:
	for node in roots:
		_surfaces.call("watch_environment", node)


func movement_spacing() -> float:
	return randf_range(drop_spacing.x, drop_spacing.y)


func splatter_hit(position: Vector3, direction: Vector3, weapon: String, excluded: Array[RID], source_id: int) -> void:
	_queue_effect("_emit_splatter_hit", [position, direction, weapon, excluded, source_id])


# Public v1 addition (ADR-0017): a burst of blood where a limb came off.
func severed_burst(position: Vector3, direction: Vector3, excluded: Array[RID]) -> void:
	_queue_effect("_emit_severed_burst", [position, direction, excluded])


func small_stain(position: Vector3, excluded: Array[RID]) -> void:
	_queue_effect("_emit_small_stain", [position, excluded])


func drops_trail(previous: Vector3, current: Vector3, excluded: Array[RID]) -> void:
	_queue_effect("_emit_drops_trail", [previous, current, excluded])


func smear_drag(previous: Vector3, current: Vector3, excluded: Array[RID]) -> void:
	_queue_effect("_emit_smear_drag", [previous, current, excluded])


func death_pool(position: Vector3, excluded: Array[RID], death_id: int) -> void:
	_queue_effect("_emit_death_pool", [position, excluded, death_id])


func _queue_effect(method: String, arguments: Array) -> void:
	if _effect_requests.size() >= 64:
		# Preserve one-off deaths; discard excess transient hit/trail work.
		if method != "_emit_death_pool":
			return
		for request in _effect_requests:
			if request["method"] != "_emit_death_pool":
				_effect_requests.erase(request)
				break
	_effect_requests.append({"method": method, "arguments": arguments})
	set_physics_process(true)


func _physics_process(_delta: float) -> void:
	var requests := _effect_requests.slice(0, 32)
	_effect_requests = _effect_requests.slice(requests.size())
	for request in requests:
		callv(request["method"], request["arguments"])
	set_physics_process(not _effect_requests.is_empty())


func _emit_splatter_hit(position: Vector3, direction: Vector3, weapon: String, excluded: Array[RID], source_id: int) -> void:
	var now := Time.get_ticks_msec() * 0.001
	if now - float(_hit_times.get(source_id, -10.0)) < hit_interval:
		return
	_hit_times[source_id] = now
	if _hit_times.size() > 256:
		for id in _hit_times.keys():
			if now - _hit_times[id] > 5.0:
				_hit_times.erase(id)
	var surface: Dictionary = _surfaces.call("find_behind", position, direction, excluded)
	if surface.is_empty():
		surface = _surfaces.call("find_floor", position, excluded)
	for mark in range(splatters_per_hit):
		_submit("splatter", surface, direction, splatter_size, true, weapon == "SHOTGUN")


func _emit_severed_burst(position: Vector3, direction: Vector3, excluded: Array[RID]) -> void:
	var flat := Vector3(direction.x, 0.0, direction.z)
	for index in range(6):
		var spread := Vector3(randf_range(-0.9, 0.9), 0.0, randf_range(-0.9, 0.9)) + flat.normalized() * randf_range(0.2, 1.2)
		var surface: Dictionary = _surfaces.call("find_floor", position + spread, excluded)
		_submit("splatter", surface, spread if spread.length_squared() > 0.01 else flat, splatter_size * 1.2, true, true)
	var behind: Dictionary = _surfaces.call("find_behind", position, direction, excluded)
	if not behind.is_empty():
		_submit("splatter", behind, direction, splatter_size * 1.3, true, true)
	_submit("stain", _surfaces.call("find_floor", position, excluded), Vector3.ZERO, stain_size * 1.6)


func _emit_small_stain(position: Vector3, excluded: Array[RID]) -> void:
	_submit("stain", _surfaces.call("find_floor", position, excluded), Vector3.ZERO, stain_size)


func _emit_drops_trail(previous: Vector3, current: Vector3, excluded: Array[RID]) -> void:
	if previous.distance_to(current) < 0.05:
		return
	_submit("drops", _surfaces.call("find_floor", (previous + current) * 0.5, excluded), current - previous, drops_size, true)


func _emit_smear_drag(previous: Vector3, current: Vector3, excluded: Array[RID]) -> void:
	var motion := current - previous
	var distance := motion.length()
	if distance < 0.05:
		return
	var count := mini(8, maxi(1, ceili(distance / 0.55)))
	for index in range(count):
		var location := previous.lerp(current, (index + 0.5) / count)
		var surface: Dictionary = _surfaces.call("find_floor", location, excluded)
		_submit("smear", surface, motion, smear_size, true)


func _emit_death_pool(position: Vector3, excluded: Array[RID], death_id: int) -> void:
	var surface: Dictionary = _surfaces.call("find_floor", position, excluded)
	var definition := _definition("pool", surface, Vector3.ZERO, pool_size, false)
	if definition.is_empty():
		_budget.call("schedule_pool", death_id, {}, {}, 0.0)
		return
	definition["pool"] = true
	definition["growth_seconds"] = randf_range(pool_growth.x, pool_growth.y)
	_budget.call("schedule_pool", death_id, definition, surface, randf_range(pool_delay.x, pool_delay.y))


func _submit(category: String, surface: Dictionary, direction: Vector3, sizes: Vector2, directed: bool = false, heavy: bool = false) -> void:
	surface = _surfaces.call("jitter_surface", surface, 0.12 if category == "splatter" else 0.025)
	var definition := _definition(category, surface, direction, sizes, directed, heavy)
	_budget.call("submit", definition, surface)


func _definition(category: String, surface: Dictionary, direction: Vector3, sizes: Vector2, directed: bool, heavy: bool = false) -> Dictionary:
	var hit := SURFACES.resolve(surface)
	if hit.is_empty():
		return {}
	var entry: Dictionary = _library.choose(category)
	if entry.is_empty():
		return {}
	var length := randf_range(sizes.x, sizes.y)
	if heavy:
		length = maxf(length, sizes.y * 0.75)
	var aspect: float = entry["aspect"]
	var footprint := Vector2(length, length / aspect) if aspect >= 1.0 else Vector2(length * aspect, length)
	var angle := randf_range(-0.14, 0.14) if directed else randf_range(0.0, TAU)
	var basis := SURFACES.surface_basis(hit["normal"], direction, aspect >= 1.0, angle)
	if not _decal:
		footprint = _surfaces.call("fit_quad", surface, basis, footprint)
		if footprint == Vector2.ZERO:
			return {}
	return {"texture": entry["texture"], "footprint": footprint, "basis": basis, "local_basis": (hit["collider"] as Node3D).global_basis.inverse() * basis, "tint": Color(1.0, randf_range(0.90, 1.0), randf_range(0.90, 1.0), randf_range(0.96, 1.0))}


func clear_marks() -> void:
	_effect_requests.clear()
	set_physics_process(false)
	_budget.call("clear_marks")
	_hit_times.clear()


func statistics() -> Dictionary:
	return _budget.call("statistics")
