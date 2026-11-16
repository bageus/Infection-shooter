extends RefCounted
## Bakes a bullet wound into a per-surface blood mask in UV space (ADR-0017).
## The mask is written once per hit on the CPU, so the skin shader samples one
## texture instead of looping over a limited list of wound uniforms. Wounds never
## fall off the list. Red channel: blood; green channel: dark wound core.
## Rest-space positions are taken from the surface vertices, so the mask follows
## the skin through any animation.

const SIZE := 128
# Matches the drip shape in body_wound.gdshader; blood runs down from the wound.
const DOWN := Vector3(0.0, -1.0, 0.0)
const CELL_SIZE := 0.15
const PAINT_BUDGET_USEC := 3000
const PAINT_CHUNK := 24


static func create_mask() -> Image:
	return Image.create(SIZE, SIZE, false, Image.FORMAT_RG8)


## Paints one wound. `surface` holds "vertices" (rest space), "uvs" and "indices"
## as built by body_part_mesh.gd. Returns true when any texel changed.
static func paint(image: Image, surface: Dictionary, center: Vector3, radius: float) -> bool:
	var tris := candidates(surface, center, radius)
	return paint_triangles(image, surface, tris, 0, tris.size(), center, radius)


## Indices (into surface.indices, multiples of 3) of the triangles the wound can reach.
static func candidates(surface: Dictionary, center: Vector3, radius: float) -> PackedInt32Array:
	var result := PackedInt32Array()
	var vertices: PackedVector3Array = surface.vertices
	var uvs: PackedVector2Array = surface.uvs
	var indices: PackedInt32Array = surface.indices
	if radius <= 0.0 or uvs.size() != vertices.size() or indices.size() < 3:
		return result
	# The wound reaches r sideways, 2.9 r down (blood runs) and 0.7 r up; see _mask_at.
	var box_low := center - Vector3(radius, radius * 2.9, radius)
	var box_high := center + Vector3(radius, radius * 0.7, radius)
	var grid := _grid(surface)
	var seen := {}
	var low := Vector3i(floor_vec(box_low / CELL_SIZE))
	var high := Vector3i(floor_vec(box_high / CELL_SIZE))
	for x in range(low.x, high.x + 1):
		for y in range(low.y, high.y + 1):
			for z in range(low.z, high.z + 1):
				for tri: int in grid.get(Vector3i(x, y, z), []):
					if seen.has(tri):
						continue
					seen[tri] = true
					if _near(vertices[indices[tri]], vertices[indices[tri + 1]], vertices[indices[tri + 2]], box_low, box_high):
						result.append(tri)
	return result


## Paints tris[from..to): lets a caller spread one wound over several frames.
static func paint_triangles(image: Image, surface: Dictionary, tris: PackedInt32Array, from: int, to: int, center: Vector3, radius: float) -> bool:
	var vertices: PackedVector3Array = surface.vertices
	var uvs: PackedVector2Array = surface.uvs
	var indices: PackedInt32Array = surface.indices
	var changed := false
	for at in range(from, to):
		var tri := tris[at]
		var ia := indices[tri]
		var ib := indices[tri + 1]
		var ic := indices[tri + 2]
		if _paint_triangle(image, vertices[ia], vertices[ib], vertices[ic], uvs[ia], uvs[ib], uvs[ic], center, radius):
			changed = true
	return changed


## Triangles by rest-space cell, built once per surface: a hit then visits the
## few triangles around it instead of scanning the whole body (a sever froze the game).
static func _grid(surface: Dictionary) -> Dictionary:
	if surface.has("tri_grid"):
		return surface.tri_grid
	var vertices: PackedVector3Array = surface.vertices
	var indices: PackedInt32Array = surface.indices
	var grid := {}
	for tri in range(0, indices.size() - 2, 3):
		var a := vertices[indices[tri]]
		var b := vertices[indices[tri + 1]]
		var c := vertices[indices[tri + 2]]
		var low := Vector3i(floor_vec(a.min(b).min(c) / CELL_SIZE))
		var high := Vector3i(floor_vec(a.max(b).max(c) / CELL_SIZE))
		for x in range(low.x, high.x + 1):
			for y in range(low.y, high.y + 1):
				for z in range(low.z, high.z + 1):
					var key := Vector3i(x, y, z)
					if not grid.has(key):
						grid[key] = PackedInt32Array()
					grid[key].append(tri)
	surface["tri_grid"] = grid
	return grid


static func floor_vec(v: Vector3) -> Vector3:
	return v.floor()


static func _near(a: Vector3, b: Vector3, c: Vector3, box_low: Vector3, box_high: Vector3) -> bool:
	var low := a.min(b).min(c)
	var high := a.max(b).max(c)
	return high.x >= box_low.x and low.x <= box_high.x and high.y >= box_low.y and low.y <= box_high.y and high.z >= box_low.z and low.z <= box_high.z


static func _paint_triangle(image: Image, ra: Vector3, rb: Vector3, rc: Vector3, uv_a: Vector2, uv_b: Vector2, uv_c: Vector2, center: Vector3, radius: float) -> bool:
	var a: Vector2 = uv_a * SIZE
	var b: Vector2 = uv_b * SIZE
	var c: Vector2 = uv_c * SIZE
	var v0 := b - a
	var v1 := c - a
	var d00 := v0.dot(v0)
	var d01 := v0.dot(v1)
	var d11 := v1.dot(v1)
	var denom := d00 * d11 - d01 * d01
	if absf(denom) < 1e-12:
		return false
	var low := a.min(b).min(c)
	var high := a.max(b).max(c)
	var x0 := clampi(floori(low.x), 0, SIZE - 1)
	var x1 := clampi(ceili(high.x), 0, SIZE - 1)
	var y0 := clampi(floori(low.y), 0, SIZE - 1)
	var y1 := clampi(ceili(high.y), 0, SIZE - 1)
	var changed := false
	for y in range(y0, y1 + 1):
		# Only the columns the triangle covers on this row (its UV box can be mostly empty).
		var span := _row_span(a, b, c, y + 0.5)
		if span.x > span.y:
			continue
		for x in range(maxi(x0, floori(span.x) - 1), mini(x1, ceili(span.y) + 1) + 1):
			var p := Vector2(x + 0.5, y + 0.5) - a
			var d20 := p.dot(v0)
			var d21 := p.dot(v1)
			var v := (d11 * d20 - d01 * d21) / denom
			var w := (d00 * d21 - d01 * d20) / denom
			var u := 1.0 - v - w
			if u < -0.0001 or v < -0.0001 or w < -0.0001:
				continue
			var point: Vector3 = ra * u + rb * v + rc * w
			var value := _mask_at(point, center, radius)
			var old := image.get_pixel(x, y)
			if value.x <= old.r and value.y <= old.g:
				continue
			var painted := Color(maxf(old.r, value.x), maxf(old.g, value.y), 0.0, 1.0)
			image.set_pixel(x, y, painted)
			# The image stores 8-bit channels: a change only counts when a byte moved.
			if not changed and image.get_pixel(x, y) != old:
				changed = true
	return changed


# Left and right x of the triangle on the horizontal line `row`; x > y when the line misses it.
static func _row_span(a: Vector2, b: Vector2, c: Vector2, row: float) -> Vector2:
	var low := INF
	var high := -INF
	for edge in [[a, b], [b, c], [c, a]]:
		var p: Vector2 = edge[0]
		var q: Vector2 = edge[1]
		if (p.y - row) * (q.y - row) > 0.0 or is_equal_approx(p.y, q.y):
			continue
		var x := p.x + (q.x - p.x) * (row - p.y) / (q.y - p.y)
		low = minf(low, x)
		high = maxf(high, x)
	return Vector2(low, high)


# Same shape as body_wound.gdshader without the grain: x = blood, y = core.
static func _mask_at(point: Vector3, center: Vector3, radius: float) -> Vector2:
	var offset := point - center
	var along := offset.dot(DOWN)
	var lateral := offset - DOWN * along
	var stretched := along * 0.32 if along > 0.0 else along * 1.4
	var distance_to := (lateral + DOWN * stretched).length()
	var edge := radius * 0.9
	var blood := 1.0 - smoothstep(edge * 0.55, edge, distance_to)
	var core := 1.0 - smoothstep(radius * 0.12, radius * 0.3, offset.length())
	return Vector2(blood, core)


## A wound of `owner` (a body_parts node) painted at most PAINT_BUDGET_USEC per frame,
## the budget shared by all wounds of that body, so shooting a corpse apart costs no hitch.
## Does nothing once the body is gone.
static func paint_sliced(owner: Node, rest_position: Vector3, rest_radius: float) -> void:
	for entry: Dictionary in owner._entries:
		if not owner.enabled:
			return
		if not entry.has("masks"):
			owner._create_masks(entry)
		for surface in entry.masks.size():
			var mask: Dictionary = entry.masks[surface]
			var tris := candidates(entry.data.surfaces[surface], rest_position, rest_radius)
			var changed := false
			var at := 0
			while at < tris.size():
				var stop := mini(at + PAINT_CHUNK, tris.size())
				var started := Time.get_ticks_usec()
				changed = paint_triangles(mask.image, entry.data.surfaces[surface], tris, at, stop, rest_position, rest_radius) or changed
				at = stop
				if owner.spent_frame != Engine.get_process_frames():
					owner.spent_frame = Engine.get_process_frames()
					owner.spent_usec = 0
				owner.spent_usec += Time.get_ticks_usec() - started
				while owner.spent_usec > PAINT_BUDGET_USEC and at < tris.size():
					await owner.get_tree().process_frame
					if not owner.enabled or not owner.is_inside_tree():
						return
					if owner.spent_frame != Engine.get_process_frames():
						owner.spent_frame = Engine.get_process_frames()
						owner.spent_usec = 0
			if changed:
				entry.lease.page.textures[surface].update_layer(mask.image, entry.lease.layer)
