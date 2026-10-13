extends Node3D
## Permanent floor stains. Floor marks leaving the budget are blitted into small CPU
## tiles (128x128 RGBA8 covering 4x4 m, 64 KB each). At most MAX_LIVE tiles are shown,
## one Decal each, and at most one GPU texture upload happens per 0.1 s physics tick.
## Tiles beyond MAX_LIVE (or MAX_TILES) are kept as images only, then dropped farthest-first.

const STAMP := preload("res://game/presentation/office_floor/blood_floor_stamp.gd")
const MAX_LIVE := 16
const MAX_TILES := 64
const MAX_QUEUE := 64
const STAMPS_PER_TICK := 2
const SWAP_MARGIN := 4.0

var settings: Dictionary = {}
var _stamp := STAMP.new()
var _tiles: Dictionary = {}
var _queue: Array[Dictionary] = []
var _timer: Timer
var _camera_point := Vector3.ZERO
var _has_camera := false


func _ready() -> void:
	_timer = Timer.new()
	_timer.wait_time = 0.1
	_timer.process_callback = Timer.TIMER_PROCESS_PHYSICS
	_timer.timeout.connect(_tick)
	add_child(_timer)


## Queues a stain; the pixels are written on a later tick.
func stamp(texture: Texture2D, tint: Color, footprint: Vector2, position: Vector3, mark_basis: Basis) -> bool:
	if texture == null or footprint.x <= 0.0 or footprint.y <= 0.0:
		return false
	if _queue.size() >= MAX_QUEUE:
		_queue.pop_front()
	_queue.append({"texture": texture, "tint": tint, "footprint": footprint, "position": position, "basis": mark_basis.orthonormalized()})
	if _timer != null and _timer.is_stopped():
		_timer.start()
	return true


func _tick() -> void:
	_read_camera()
	for count in STAMPS_PER_TICK:
		if _queue.is_empty():
			break
		_apply(_queue.pop_front())
	_demote_surplus()
	_gpu_step()
	if _queue.is_empty() and _pending_gpu() == null and _tiles.size() <= _live_cells().size() and _timer != null:
		_timer.stop()


func _apply(request: Dictionary) -> void:
	var source := _stamp.source_image(request["texture"])
	if source == null:
		return
	var position: Vector3 = request["position"]
	for cell in STAMP.cells_touched(position, request["basis"], request["footprint"]):
		var tile := _tile_for(cell, position.y)
		if tile.is_empty():
			continue
		STAMP.blit(tile["image"], cell, source, position, request["basis"], request["footprint"], request["tint"])
		tile["dirty"] = true


func _tile_for(cell: Vector2i, height: float) -> Dictionary:
	if _tiles.has(cell):
		return _tiles[cell]
	if _tiles.size() >= MAX_TILES:
		var farthest := _farthest(_tiles.keys())
		if _distance(farthest) <= _distance(cell):
			return {}
		_drop(farthest)
	var image := Image.create(STAMP.TILE_PIXELS, STAMP.TILE_PIXELS, false, Image.FORMAT_RGBA8)
	_tiles[cell] = {"image": image, "height": height, "dirty": false, "visual": null, "texture": null}
	return _tiles[cell]


func _demote_surplus() -> void:
	var live := _live_cells()
	while live.size() > MAX_LIVE:
		var farthest := _farthest(live)
		_hide(farthest)
		live.erase(farthest)


# One upload per tick: refresh a live dirty tile, otherwise show the nearest hidden one.
func _gpu_step() -> void:
	var cell: Variant = _pending_gpu()
	if cell == null:
		return
	var tile: Dictionary = _tiles[cell]
	if tile["visual"] == null:
		var live := _live_cells()
		if live.size() >= MAX_LIVE:
			var worst := _farthest(live)
			if _distance(worst) - _distance(cell) < SWAP_MARGIN:
				return
			_hide(worst)
		_show(cell, tile)
	else:
		(tile["texture"] as ImageTexture).update(tile["image"])
	tile["dirty"] = false


# Hidden tiles are shown when they are non-empty and nearer; live ones when dirty.
func _pending_gpu() -> Variant:
	var best: Variant = null
	var live_count := _live_cells().size()
	var worst_live := _distance(_farthest(_live_cells())) if live_count > 0 else INF
	for cell in _tiles:
		var tile: Dictionary = _tiles[cell]
		var wanted: bool = tile["dirty"] if tile["visual"] != null else (live_count < MAX_LIVE or worst_live - _distance(cell) >= SWAP_MARGIN) and _has_pixels(tile)
		if wanted and (best == null or _distance(cell) < _distance(best)):
			best = cell
	return best


func _has_pixels(tile: Dictionary) -> bool:
	return tile["dirty"] or tile.get("shown_before", false)


func _show(cell: Vector2i, tile: Dictionary) -> void:
	var texture := ImageTexture.create_from_image(tile["image"])
	tile["texture"] = texture
	var center := Vector3((cell.x + 0.5) * STAMP.TILE_METERS, tile["height"], (cell.y + 0.5) * STAMP.TILE_METERS)
	if settings.get("decal", true):
		var decal := Decal.new()
		decal.size = Vector3(STAMP.TILE_METERS, 0.5, STAMP.TILE_METERS)
		decal.texture_albedo = texture
		decal.upper_fade = 0.0
		decal.lower_fade = 0.0
		decal.normal_fade = 0.8
		decal.cull_mask = settings.get("visual_mask", 128)
		tile["visual"] = decal
		add_child(decal)
		decal.global_position = center
	else:
		var quad := QuadMesh.new()
		quad.size = Vector2(STAMP.TILE_METERS, STAMP.TILE_METERS)
		var material := StandardMaterial3D.new()
		material.albedo_texture = texture
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		quad.material = material
		var visual := MeshInstance3D.new()
		visual.mesh = quad
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		visual.layers = 1
		tile["visual"] = visual
		add_child(visual)
		visual.global_position = center + Vector3.UP * settings.get("quad_offset", 0.018)
		visual.rotation.x = -PI * 0.5
	tile["shown_before"] = true


func _hide(cell: Vector2i) -> void:
	var tile: Dictionary = _tiles[cell]
	if tile["visual"] != null:
		(tile["visual"] as Node).queue_free()
	tile["visual"] = null
	tile["texture"] = null
	tile["dirty"] = false


func _drop(cell: Vector2i) -> void:
	_hide(cell)
	_tiles.erase(cell)


func _live_cells() -> Array:
	var live: Array = []
	for cell in _tiles:
		if _tiles[cell]["visual"] != null:
			live.append(cell)
	return live


func _farthest(cells: Array) -> Vector2i:
	var result: Vector2i = cells[0]
	for cell in cells:
		if _distance(cell) > _distance(result):
			result = cell
	return result


func _distance(cell: Vector2i) -> float:
	if not _has_camera:
		return 0.0
	var center := Vector2((cell.x + 0.5) * STAMP.TILE_METERS, (cell.y + 0.5) * STAMP.TILE_METERS)
	return Vector2(_camera_point.x, _camera_point.z).distance_to(center)


func _read_camera() -> void:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	_has_camera = camera != null
	if _has_camera:
		_camera_point = camera.global_position


func tile_image(cell: Vector2i) -> Image:
	return _tiles[cell]["image"] if _tiles.has(cell) else null


func clear() -> void:
	_queue.clear()
	for cell in _tiles.keys():
		_hide(cell)
	_tiles.clear()
	if _timer != null:
		_timer.stop()


func statistics() -> Dictionary:
	return {"tiles": _tiles.size(), "live": _live_cells().size(), "queued": _queue.size()}
