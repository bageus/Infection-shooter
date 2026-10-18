extends RefCounted
## Confirmed presentation facts; this helper never changes health or collision.
const GLASS_ATLAS := preload("res://game/core/vfx/public/surface_atlases.gd")
const RECEIVERS := preload("res://game/presentation/office_floor/receiver_decal_bake.gd")
const SETTINGS := preload("res://game/presentation/office_floor/public/surface_decal_config.gd")
var receivers := RECEIVERS.new()
var floor_view: Node3D
var settings: Dictionary = SETTINGS.normalized({})
var _step_frame := -1
var _steps := 0
var _corners: Dictionary = {}

func configure(host: Node3D, sources: RefCounted) -> void:
	floor_view = host
	receivers.sources = sources

func hit(collider: Node3D, point: Vector3, normal: Vector3, weapon: String, anchor: MeshInstance3D = null) -> bool:
	if not point.is_finite() or not normal.is_finite(): return false
	var local := floor_view.to_local(point)
	var floor_normal := floor_view.global_basis.transposed() * normal
	var frame := randi_range(5, 7) if weapon == "GRENADE" else randi_range(0, 4)
	var size := 1.2 if weapon == "GRENADE" else 0.18
	if floor_normal.y > 0.8 and absf(local.y) < 0.16:
		_floor_stamp(Vector2(local.x, local.z), "bullet", frame, size)
		if powerful(weapon) and randf() < 0.22:
			_floor_stamp(Vector2(local.x, local.z), "floor_damage", randi_range(0, 15), randf_range(0.35, 0.8))
		return true
	if not is_instance_valid(anchor): return false
	var label := (str(collider.name) + " " + str(anchor.name) + " " + str(collider.get_parent().name if collider.get_parent() else "")).to_lower()
	var wall := absf(normal.y) < 0.6 and ("wall" in label or "column" in label) and "wood" not in label
	_stamp(anchor, point, normal, "bullet", frame, size)
	# Heavy hits (shots and blasts) always chip the plaster; light rounds only sometimes.
	if wall and randf() < (1.0 if powerful(weapon) else 0.35):
		_stamp(anchor, point, normal, "wall_damage", randi_range(0, 15), randf_range(0.35, 0.85))
	if wall and randf() < 0.12:
		_stamp(anchor, point, normal, "wall_scuff", randi_range(0, 15), randf_range(0.25, 0.6))
	return true

static func powerful(weapon: String) -> bool:
	return weapon in ["SHOTGUN", "SNIPER", "AK", "AK_RIFLE", "M4", "M4_RIFLE", "MINIGUN", "GRENADE", "LAUNCHER"]

func glass_hit(anchor: MeshInstance3D, point: Vector3, normal: Vector3) -> bool:
	var id := anchor.get_instance_id()
	var pending := receivers.queue.any(func(request: Dictionary) -> bool: return request.anchor.get_ref() == anchor)
	if _corners.has(id) and not receivers.pages.has(id) and not pending: _corners.erase(id)
	var ok := _stamp(anchor, point, normal, "glass_impact", randi_range(0, 7), 0.48, 0, true)
	_stamp(anchor, point + anchor.global_basis.x.normalized() * randf_range(-0.2, 0.2), normal,
		"glass_fracture", [0, 1, 2, 12][randi_range(0, 3)], randf_range(0.4, 0.75), randi_range(0, 3), true)
	if randf() < 0.25:
		_stamp(anchor, point, normal, "glass_fracture", [3, 4, 5, 6, 7, 8, 9, 10, 11, 14, 15].pick_random(), 0.28, randi_range(0, 3), true)
	if not _corners.has(id) or _corners[id].get_ref() != anchor:
		_corners[id] = weakref(anchor)
		var bounds := anchor.get_aabb()
		var mapping := RECEIVERS.face_mapping(bounds, anchor.to_local(point), anchor.global_basis.transposed() * normal, true)
		var axis := int(mapping.face) / 2
		var pair: Vector2i = [Vector2i(2, 1), Vector2i(0, 2), Vector2i(0, 1)][axis]
		for index in 4:
			var corner := bounds.get_center()
			corner[pair.x] = bounds.position[pair.x] + bounds.size[pair.x] * (0.88 if index in [1, 2] else 0.12)
			corner[pair.y] = bounds.position[pair.y] + bounds.size[pair.y] * (0.88 if index in [2, 3] else 0.12)
			_stamp(anchor, anchor.to_global(corner), normal, "glass_fracture", 13, 0.35, index, true)
	if _corners.size() > 32: _corners.erase(_corners.keys()[0])
	return ok

func _stamp(anchor: MeshInstance3D, point: Vector3, normal: Vector3, kind: String, frame: int, size: float, turns: int = 0, glass: bool = false) -> bool:
	var config: Dictionary = settings["glass" if glass else kind]
	var center: Vector2 = GLASS_ATLAS.GLASS_CENTERS[frame] if kind == "glass_impact" else Vector2(0.5, 0.5)
	var ok := receivers.stamp(anchor, point, normal, kind, frame, size * float(config.size), float(config.opacity), turns, glass, center)
	if ok: floor_view.set_process(true)
	return ok

func _floor_stamp(at: Vector2, kind: String, frame: int, size: float) -> bool:
	return floor_view.call("stamp_floor_surface", at, kind, frame, size, randi_range(0, 3))

func step_at(point: Vector3, normal: Vector3) -> void:
	var frame := Engine.get_physics_frames()
	if _step_frame != frame:
		_step_frame = frame
		_steps = 0
	if _steps >= 2 or normal.y < 0.8 or randf() > 0.12: return
	_steps += 1
	var local := floor_view.to_local(point)
	if absf(local.y) > 0.16: return
	_floor_stamp(Vector2(local.x, local.z), "floor_scuff", randi_range(0, 15), randf_range(0.2, 0.45))

func clear() -> void:
	receivers.clear()
	_corners.clear()
