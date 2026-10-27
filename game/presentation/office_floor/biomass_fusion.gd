extends RefCounted
## Merges neighbouring biomass cells that lie on one surface into a single
## albedo + relief image (ADR-0061). Heights are joined with a smooth maximum so
## overlapping masses grow into each other, small gaps are closed by a blurred
## occupancy field, and the normals are recomputed from the merged height, so
## the result has no seams. Pure image maths: safe to run on a worker thread.

const ATLAS := preload("res://game/presentation/office_floor/biomass_atlas.gd")

const MAX_SIDE := 896.0
## Smooth-union width in height units (height spans 0..1).
const SOFT := 0.18
## Rim added around the union so bridges across edge gaps have room to grow.
const MARGIN := 0.06
## Veins grow between pieces whose masses stop this close (plane units) without meeting.
const BRIDGE_REACH := 0.2
const BRIDGE_MIN := 0.025
const BRIDGE_WIDTH := 0.011
const BRIDGE_HEIGHT := 0.4
const BLUR_DIVISOR := 8
const BRIDGE_LOW := 0.30
const BRIDGE_HIGH := 0.55
## The source relief maps one height unit to 18 source pixels of slope.
const SLOPE_PIXELS := 18.0
const SOURCE_PIXELS_PER_UNIT := 627.0


## members: [{cell: int, xform: Transform2D}] where xform maps the cell's local
## quad (x right, y up, FOOTPRINT centred on the origin) into the shared plane.
## Returns {albedo: Image, relief: Image, rect: Rect2, ppu: float} or {} when
## there is nothing to draw. `cancel` is a one-element array the caller sets to true to abandon a
## long fusion early; the result is then {}.
static func fuse(members: Array, albedo_data: PackedByteArray, relief_data: PackedByteArray, target_ppu: float, cancel: Array = [false]) -> Dictionary:
	if members.is_empty():
		return {}
	var half := ATLAS.FOOTPRINT * 0.5
	var corners := [Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y), Vector2(-half.x, half.y)]
	var bounds: Array[Rect2] = []
	var rect := Rect2()
	for index in members.size():
		var xform: Transform2D = members[index]["xform"]
		var box := Rect2(xform * corners[0], Vector2.ZERO)
		for corner: Vector2 in corners:
			box = box.expand(xform * corner)
		bounds.append(box)
		rect = box if index == 0 else rect.merge(box)
	rect = rect.grow(MARGIN)
	# A degenerate transform (NaN or infinity) would size the buffers from garbage and fail the allocation.
	if not (is_finite(rect.size.x) and is_finite(rect.size.y)) or not (is_finite(rect.position.x) and is_finite(rect.position.y)) or not is_finite(target_ppu) or target_ppu <= 0.0:
		return {}
	var ppu := minf(target_ppu, MAX_SIDE / maxf(rect.size.x, rect.size.y))
	var width := clampi(ceili(rect.size.x * ppu), 8, int(MAX_SIDE) + 1)
	var height := clampi(ceili(rect.size.y * ppu), 8, int(MAX_SIDE) + 1)
	rect.size = Vector2(width, height) / ppu
	var count := width * height
	var heights := PackedFloat32Array()
	var alphas := PackedFloat32Array()
	var reds := PackedFloat32Array()
	var greens := PackedFloat32Array()
	var blues := PackedFloat32Array()
	for plane: PackedFloat32Array in [heights, alphas, reds, greens, blues]:
		plane.resize(count)
	var planes := [heights, alphas, reds, greens, blues]
	var samples: Array[PackedVector2Array] = []
	for index in members.size():
		if cancel[0]:
			return {}
		samples.append(_draw_member(members[index], bounds[index], rect, ppu, width, height, albedo_data, relief_data, planes, cancel))
	if not _bridge(samples, rect, ppu, width, height, planes, cancel):
		return {}
	return _finish(rect, ppu, width, height, heights, alphas, reds, greens, blues, cancel)


static func _draw_member(member: Dictionary, box: Rect2, rect: Rect2, ppu: float, width: int, height: int, albedo_data: PackedByteArray, relief_data: PackedByteArray, planes: Array, cancel: Array) -> PackedVector2Array:
	var solid := PackedVector2Array()
	var heights: PackedFloat32Array = planes[0]
	var alphas: PackedFloat32Array = planes[1]
	var reds: PackedFloat32Array = planes[2]
	var greens: PackedFloat32Array = planes[3]
	var blues: PackedFloat32Array = planes[4]
	var inverse: Transform2D = (member["xform"] as Transform2D).affine_inverse()
	var origin := Vector2(ATLAS.cell_origin(int(member["cell"])))
	var foot := ATLAS.FOOTPRINT
	var cell_size := Vector2(ATLAS.CELL)
	var stride := ATLAS.ATLAS.x
	var x0 := clampi(floori((box.position.x - rect.position.x) * ppu), 0, width - 1)
	var x1 := clampi(ceili((box.end.x - rect.position.x) * ppu), 0, width - 1)
	var y0 := clampi(floori((rect.end.y - box.end.y) * ppu), 0, height - 1)
	var y1 := clampi(ceili((rect.end.y - box.position.y) * ppu), 0, height - 1)
	var last_x := ATLAS.ATLAS.x - 1
	var last_y := ATLAS.ATLAS.y - 1
	for row in range(y0, y1 + 1):
		if cancel[0]:
			return solid
		var plane_y := rect.end.y - (row + 0.5) / ppu
		for column in range(x0, x1 + 1):
			var local := inverse * Vector2(rect.position.x + (column + 0.5) / ppu, plane_y)
			var u := local.x / foot.x + 0.5
			var v := 0.5 - local.y / foot.y
			if u < 0.0 or u >= 1.0 or v < 0.0 or v >= 1.0:
				continue
			var sx := origin.x + u * cell_size.x - 0.5
			var sy := origin.y + v * cell_size.y - 0.5
			var ix := floori(sx)
			var iy := floori(sy)
			var fx := sx - ix
			var fy := sy - iy
			var jx := mini(ix + 1, last_x)
			var jy := mini(iy + 1, last_y)
			ix = maxi(ix, 0)
			iy = maxi(iy, 0)
			var p00 := iy * stride + ix
			var p10 := iy * stride + jx
			var p01 := jy * stride + ix
			var p11 := jy * stride + jx
			var w00 := (1.0 - fx) * (1.0 - fy)
			var w10 := fx * (1.0 - fy)
			var w01 := (1.0 - fx) * fy
			var w11 := fx * fy
			var a00 := albedo_data[p00 * 4 + 3] * w00
			var a10 := albedo_data[p10 * 4 + 3] * w10
			var a01 := albedo_data[p01 * 4 + 3] * w01
			var a11 := albedo_data[p11 * 4 + 3] * w11
			var alpha := (a00 + a10 + a01 + a11) / 255.0
			if alpha < 0.004:
				continue
			var weight_sum := a00 + a10 + a01 + a11
			var red := (albedo_data[p00 * 4] * a00 + albedo_data[p10 * 4] * a10 + albedo_data[p01 * 4] * a01 + albedo_data[p11 * 4] * a11) / weight_sum / 255.0
			var green := (albedo_data[p00 * 4 + 1] * a00 + albedo_data[p10 * 4 + 1] * a10 + albedo_data[p01 * 4 + 1] * a01 + albedo_data[p11 * 4 + 1] * a11) / weight_sum / 255.0
			var blue := (albedo_data[p00 * 4 + 2] * a00 + albedo_data[p10 * 4 + 2] * a10 + albedo_data[p01 * 4 + 2] * a01 + albedo_data[p11 * 4 + 2] * a11) / weight_sum / 255.0
			var member_height := (relief_data[p00 * 3 + 2] * w00 + relief_data[p10 * 3 + 2] * w10 + relief_data[p01 * 3 + 2] * w01 + relief_data[p11 * 3 + 2] * w11) / 255.0
			var index := row * width + column
			if alpha > 0.6 and member_height > 0.15 and (row & 7) == 0 and (column & 7) == 0:
				solid.append(Vector2(rect.position.x + (column + 0.5) / ppu, plane_y))
			var old_alpha := alphas[index]
			if old_alpha < 0.004:
				heights[index] = member_height
				alphas[index] = alpha
				reds[index] = red
				greens[index] = green
				blues[index] = blue
				continue
			var old_height := heights[index]
			var mix := clampf(0.5 + (member_height - old_height) / (2.0 * SOFT), 0.0, 1.0) * alpha
			reds[index] = lerpf(reds[index], red, mix)
			greens[index] = lerpf(greens[index], green, mix)
			blues[index] = lerpf(blues[index], blue, mix)
			alphas[index] = 1.0 - (1.0 - old_alpha) * (1.0 - alpha)
			heights[index] = _smooth_max(old_height, member_height)
	return solid


# Joins pieces whose masses stop just short of each other with a short vein, so
# neighbours that were placed edge to edge still read as one connected body.
# Returns false when `cancel` was set before all pairs were joined.
static func _bridge(samples: Array[PackedVector2Array], rect: Rect2, ppu: float, width: int, height: int, planes: Array, cancel: Array) -> bool:
	for i in samples.size():
		for j in range(i + 1, samples.size()):
			var best := BRIDGE_REACH * BRIDGE_REACH
			var from := Vector2.ZERO
			var to := Vector2.ZERO
			var found := false
			var closest_overall := INF
			for a in samples[i]:
				if cancel[0]:
					return false
				for b in samples[j]:
					var gap := a.distance_squared_to(b)
					closest_overall = minf(closest_overall, gap)
					if gap < best:
						best = gap
						from = a
						to = b
						found = true
			if found and closest_overall > BRIDGE_MIN * BRIDGE_MIN:
				_stamp_vein(from, to, rect, ppu, width, height, planes)
	return true


static func _stamp_vein(from: Vector2, to: Vector2, rect: Rect2, ppu: float, width: int, height: int, planes: Array) -> void:
	var heights: PackedFloat32Array = planes[0]
	var alphas: PackedFloat32Array = planes[1]
	var reds: PackedFloat32Array = planes[2]
	var greens: PackedFloat32Array = planes[3]
	var blues: PackedFloat32Array = planes[4]
	var length := from.distance_to(to)
	var side := (to - from).orthogonal().normalized()
	var steps := maxi(ceili(length * ppu * 1.5), 2)
	for step in steps + 1:
		var t := float(step) / steps
		var centre := from.lerp(to, t) + side * sin(t * PI) * length * 0.1
		var radius := BRIDGE_WIDTH * (0.45 + 0.55 * sin(t * PI))
		var reach := ceili(radius * ppu) + 1
		var cx := floori((centre.x - rect.position.x) * ppu)
		var cy := floori((rect.end.y - centre.y) * ppu)
		for row in range(maxi(cy - reach, 0), mini(cy + reach, height - 1) + 1):
			for column in range(maxi(cx - reach, 0), mini(cx + reach, width - 1) + 1):
				var offset := Vector2(column + 0.5 - (centre.x - rect.position.x) * ppu, row + 0.5 - (rect.end.y - centre.y) * ppu).length() / ppu
				if offset >= radius:
					continue
				var index := row * width + column
				var lift := BRIDGE_HEIGHT * sqrt(1.0 - (offset / radius) * (offset / radius))
				var coverage := clampf((radius - offset) * ppu, 0.0, 1.0)
				if coverage <= alphas[index] and lift <= heights[index]:
					continue
				reds[index] = lerpf(reds[index], 0.30, coverage * (1.0 - alphas[index] * 0.5))
				greens[index] = lerpf(greens[index], 0.03, coverage * (1.0 - alphas[index] * 0.5))
				blues[index] = lerpf(blues[index], 0.04, coverage * (1.0 - alphas[index] * 0.5))
				alphas[index] = maxf(alphas[index], coverage)
				heights[index] = _smooth_max(heights[index], lift) if heights[index] > 0.02 else lift


static func _smooth_max(a: float, b: float) -> float:
	var top := maxf(a, b)
	if minf(a, b) < 0.02:
		return top
	var gap := maxf(SOFT - absf(a - b), 0.0)
	return top + gap * gap / (4.0 * SOFT)


static func _finish(rect: Rect2, ppu: float, width: int, height: int, heights: PackedFloat32Array, alphas: PackedFloat32Array, reds: PackedFloat32Array, greens: PackedFloat32Array, blues: PackedFloat32Array, cancel: Array) -> Dictionary:
	var count := width * height
	# Premultiplied occupancy, colour and height, blurred by a down/up resize.
	var field := PackedByteArray()
	field.resize(count * 4)
	var field_height := PackedByteArray()
	field_height.resize(count)
	for index in count:
		if (index & 8191) == 0 and cancel[0]:
			return {}
		var alpha := alphas[index]
		field[index * 4] = int(reds[index] * alpha * 255.0)
		field[index * 4 + 1] = int(greens[index] * alpha * 255.0)
		field[index * 4 + 2] = int(blues[index] * alpha * 255.0)
		field[index * 4 + 3] = int(alpha * 255.0)
		field_height[index] = int(minf(heights[index], 1.0) * alpha * 255.0)
	var blurred := _blur(Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, field)).get_data()
	var blurred_height := _blur(Image.create_from_data(width, height, false, Image.FORMAT_L8, field_height)).get_data()
	var final_height := PackedFloat32Array()
	final_height.resize(count)
	var albedo := PackedByteArray()
	albedo.resize(count * 4)
	for index in count:
		if (index & 8191) == 0 and cancel[0]:
			return {}
		var alpha := alphas[index]
		var occupancy := blurred[index * 4 + 3] / 255.0
		if alpha < 0.02 and occupancy > BRIDGE_LOW:
			var fill := smoothstep(BRIDGE_LOW, BRIDGE_HIGH, occupancy)
			final_height[index] = blurred_height[index] / 255.0 / occupancy
			albedo[index * 4] = clampi(int(blurred[index * 4] / occupancy), 0, 255)
			albedo[index * 4 + 1] = clampi(int(blurred[index * 4 + 1] / occupancy), 0, 255)
			albedo[index * 4 + 2] = clampi(int(blurred[index * 4 + 2] / occupancy), 0, 255)
			albedo[index * 4 + 3] = int(fill * 255.0)
		else:
			final_height[index] = heights[index]
			albedo[index * 4] = int(reds[index] * 255.0)
			albedo[index * 4 + 1] = int(greens[index] * 255.0)
			albedo[index * 4 + 2] = int(blues[index] * 255.0)
			albedo[index * 4 + 3] = int(alpha * 255.0)
	var relief := PackedByteArray()
	relief.resize(count * 3)
	var slope := SLOPE_PIXELS * 0.5 * ppu / SOURCE_PIXELS_PER_UNIT
	for row in height:
		if cancel[0]:
			return {}
		var up := maxi(row - 1, 0) * width
		var down := mini(row + 1, height - 1) * width
		var here := row * width
		for column in width:
			var left := maxi(column - 1, 0)
			var right := mini(column + 1, width - 1)
			# Same channel convention as the authored maps: R = -dh/dx, G = +dh/dy (y up).
			var nx := -(final_height[here + right] - final_height[here + left]) * slope
			var ny := -(final_height[down + column] - final_height[up + column]) * slope
			var inverse_length := 1.0 / sqrt(nx * nx + ny * ny + 1.0)
			var index := (here + column) * 3
			relief[index] = int((nx * inverse_length * 0.5 + 0.5) * 255.0)
			relief[index + 1] = int((ny * inverse_length * 0.5 + 0.5) * 255.0)
			relief[index + 2] = int(minf(final_height[here + column], 1.0) * 255.0)
	var albedo_image := Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, albedo)
	var relief_image := Image.create_from_data(width, height, false, Image.FORMAT_RGB8, relief)
	albedo_image.generate_mipmaps()
	relief_image.generate_mipmaps()
	return {"albedo": albedo_image, "relief": relief_image, "rect": rect, "ppu": ppu}


static func _blur(image: Image) -> Image:
	var width := image.get_width()
	var height := image.get_height()
	image.resize(maxi(floori(float(width) / BLUR_DIVISOR), 2), maxi(floori(float(height) / BLUR_DIVISOR), 2), Image.INTERPOLATE_TRILINEAR)
	image.resize(width, height, Image.INTERPOLATE_BILINEAR)
	return image
