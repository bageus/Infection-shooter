extends RefCounted
## Logical window sizes; fullscreen candidates keep the monitor's aspect ratio.
const DEFAULT := "1280x720"
const PRESETS := [Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1600, 900),
	Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160),
	Vector2i(1280, 800), Vector2i(1440, 900), Vector2i(1680, 1050),
	Vector2i(1920, 1200), Vector2i(2560, 1600), Vector2i(2880, 1800),
	Vector2i(2560, 1080), Vector2i(3440, 1440), Vector2i(5120, 1440)]


static func identifier(size: Vector2i) -> String:
	return "%dx%d" % [size.x, size.y]


static func parse(value: String) -> Vector2i:
	var parts := value.split("x")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return Vector2i.ZERO
	var size := Vector2i(int(parts[0]), int(parts[1]))
	if size.x < 320 or size.y < 200 or size.x > 16384 or size.y > 16384:
		return Vector2i.ZERO
	return size


static func available(native: Vector2i, fullscreen: bool) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if native.x <= 0 or native.y <= 0:
		native = Vector2i(1280, 720)
	for size: Vector2i in PRESETS:
		if size.x > native.x or size.y > native.y:
			continue
		if fullscreen and absf(float(size.x) / size.y - float(native.x) / native.y) > 0.02:
			continue
		result.append(size)
	if not result.has(native):
		result.append(native)
	result.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x * a.y < b.x * b.y)
	return result


## Changing screen/aspect keeps the closest affordable size, never supersamples.
static func resolve(value: String, native: Vector2i, fullscreen: bool) -> String:
	if value == "auto":
		return value
	var wanted := parse(value)
	if wanted == Vector2i.ZERO:
		wanted = parse(DEFAULT)
	var choices := available(native, fullscreen)
	if choices.has(wanted):
		return identifier(wanted)
	var best: Vector2i = choices[0]
	for size in choices:
		if size.x * size.y <= wanted.x * wanted.y:
			best = size
	return identifier(best)


static func fit_window(wanted: Vector2i, usable: Rect2i) -> Rect2i:
	var room := (usable.size - Vector2i(32, 64)).max(Vector2i(320, 200))
	var scale := minf(1.0, minf(float(room.x) / wanted.x, float(room.y) / wanted.y))
	var size := Vector2i(Vector2(wanted) * scale)
	return Rect2i(usable.position + (usable.size - size) / 2, size)


static func render_scale(wanted: Vector2i, actual: Vector2i) -> float:
	if wanted == Vector2i.ZERO or actual.x <= 0 or actual.y <= 0:
		return 1.0
	return minf(1.0, minf(float(wanted.x) / actual.x, float(wanted.y) / actual.y))
