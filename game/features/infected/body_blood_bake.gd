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
const SPREAD_MARGIN := 3.5


static func create_mask() -> Image:
	return Image.create(SIZE, SIZE, false, Image.FORMAT_RG8)


## Paints one wound. `surface` holds "vertices" (rest space), "uvs" and "indices"
## as built by body_part_mesh.gd. Returns true when any texel changed.
static func paint(image: Image, surface: Dictionary, center: Vector3, radius: float) -> bool:
	var vertices: PackedVector3Array = surface.vertices
	var uvs: PackedVector2Array = surface.uvs
	var indices: PackedInt32Array = surface.indices
	if radius <= 0.0 or uvs.size() != vertices.size() or indices.size() < 3:
		return false
	var reach := radius * SPREAD_MARGIN
	var changed := false
	for tri in range(0, indices.size() - 2, 3):
		var ia := indices[tri]
		var ib := indices[tri + 1]
		var ic := indices[tri + 2]
		if not _near(vertices[ia], vertices[ib], vertices[ic], center, reach):
			continue
		if _paint_triangle(image, [vertices[ia], vertices[ib], vertices[ic]], [uvs[ia], uvs[ib], uvs[ic]], center, radius):
			changed = true
	return changed


static func _near(a: Vector3, b: Vector3, c: Vector3, center: Vector3, reach: float) -> bool:
	var low := a.min(b).min(c) - Vector3.ONE * reach
	var high := a.max(b).max(c) + Vector3.ONE * reach
	return center.x >= low.x and center.x <= high.x and center.y >= low.y and center.y <= high.y and center.z >= low.z and center.z <= high.z


static func _paint_triangle(image: Image, rest: Array, uv: Array, center: Vector3, radius: float) -> bool:
	var a: Vector2 = uv[0] * SIZE
	var b: Vector2 = uv[1] * SIZE
	var c: Vector2 = uv[2] * SIZE
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
		for x in range(x0, x1 + 1):
			var p := Vector2(x + 0.5, y + 0.5) - a
			var d20 := p.dot(v0)
			var d21 := p.dot(v1)
			var v := (d11 * d20 - d01 * d21) / denom
			var w := (d00 * d21 - d01 * d20) / denom
			var u := 1.0 - v - w
			if u < -0.0001 or v < -0.0001 or w < -0.0001:
				continue
			var point: Vector3 = rest[0] * u + rest[1] * v + rest[2] * w
			var value := _mask_at(point, center, radius)
			var old := image.get_pixel(x, y)
			if value.x <= old.r and value.y <= old.g:
				continue
			image.set_pixel(x, y, Color(maxf(old.r, value.x), maxf(old.g, value.y), 0.0, 1.0))
			# The image stores 8-bit channels: a change only counts when a byte moved.
			if image.get_pixel(x, y) != old:
				changed = true
	return changed


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
