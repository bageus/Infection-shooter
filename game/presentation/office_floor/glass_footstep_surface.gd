extends RefCounted
## Read-only animation-contact query; reuses existing bounded floor images.
const BAKE := preload("res://game/presentation/office_floor/glass_floor_bake.gd")
const FOOT_RADIUS := 0.18
const GRID := 4


static func has_glass_at(floor_view: Node3D, bake: RefCounted, world_position: Vector3) -> bool:
	if not world_position.is_finite() or not floor_view.is_inside_tree():
		return false
	if _physical_glass(floor_view, world_position):
		return true
	var local := floor_view.to_local(world_position)
	if absf(local.y - float(floor_view.get("tile_y"))) > 0.3:
		return false
	var center := Vector2(local.x, local.z)
	var size: Vector2 = floor_view.get("floor_size")
	for y in range(-GRID, GRID + 1):
		for x in range(-GRID, GRID + 1):
			var offset := Vector2(x, y) * (FOOT_RADIUS / GRID)
			if offset.length_squared() > FOOT_RADIUS * FOOT_RADIUS:
				continue
			var at := center + offset
			if not Rect2(-size * 0.5, size).has_point(at) or _in_opening(floor_view, at):
				continue
			var cell: Vector2i = bake.cell_at(at)
			if not bake.tiles.has(cell):
				continue
			var tile: Dictionary = bake.tiles[cell]
			if tile.texture == null:
				continue # This section is not visible yet.
			var pixel := Vector2i((((at - bake.origin) / BAKE.METERS - Vector2(cell)) * BAKE.PIXELS).floor())
			var color := (tile.image as Image).get_pixelv(pixel)
			# Glass alone has roughness < 0.2; paper/plastic/etc. stay quiet.
			if color.a > 0.1 and (tile.surface_image as Image).get_pixelv(pixel).r < 0.2:
				return true
	return false


static func _in_opening(floor_view: Node3D, at: Vector2) -> bool:
	for opening: Rect2 in floor_view.get("openings"):
		if opening.has_point(at):
			return true
	return false


static func _physical_glass(floor_view: Node3D, at: Vector3) -> bool:
	var shape := BoxShape3D.new()
	shape.size = Vector3(FOOT_RADIUS * 2.0, 0.25, FOOT_RADIUS * 2.0)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform.origin = at + Vector3.UP * 0.08
	query.collision_mask = 4 # Existing contactless fragment layer.
	for hit: Dictionary in floor_view.get_world_3d().direct_space_state.intersect_shape(query, 32):
		var body := hit.get("collider") as Node
		if body != null and bool(body.get_meta(&"glass_debris", false)):
			return true
	return false
