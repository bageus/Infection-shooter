extends RefCounted
## Versioned portable PNG pages, independent of engine resource imports.
const METERS := 8.0
const PIXELS := 512
const MAX_PAGES := 64
const MAX_ENCODED_BYTES := 96 * 1024 * 1024


static func valid(raw: Variant) -> bool:
	if not raw is Dictionary or raw.get("version") != 1 or not raw.get("pages") is Array:
		return false
	if not _number(raw.get("y")) or raw.pages.size() > MAX_PAGES:
		return false
	var total := 0
	var seen := {}
	for page: Variant in raw.pages:
		if not page is Dictionary or not _number(page.get("x")) or not _number(page.get("z")) or not page.get("png") is String:
			return false
		if float(page.x) != floorf(float(page.x)) or float(page.z) != floorf(float(page.z)) or absf(float(page.x)) > 10000 or absf(float(page.z)) > 10000:
			return false
		var cell := Vector2i(int(page.x), int(page.z))
		if seen.has(cell):
			return false
		seen[cell] = true
		total += page.png.length()
		if total > MAX_ENCODED_BYTES or not _base64(page.png) or not _png_header(Marshalls.base64_to_raw(page.png)) or image(page) == null:
			return false
	return true


static func image(page: Dictionary) -> Image:
	var bytes := Marshalls.base64_to_raw(page.png)
	if not _png_header(bytes):
		return null
	var result := Image.new()
	if result.load_png_from_buffer(bytes) != OK:
		return null
	result.convert(Image.FORMAT_RGBA8)
	return result


static func _png_header(bytes: PackedByteArray) -> bool:
	if bytes.size() < 33 or bytes.slice(0, 8) != PackedByteArray([137, 80, 78, 71, 13, 10, 26, 10]):
		return false
	return _be32(bytes, 16) == PIXELS and _be32(bytes, 20) == PIXELS


static func _be32(bytes: PackedByteArray, offset: int) -> int:
	return (int(bytes[offset]) << 24) | (int(bytes[offset + 1]) << 16) | (int(bytes[offset + 2]) << 8) | int(bytes[offset + 3])


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func _base64(value: String) -> bool:
	if value.is_empty() or value.length() % 4 != 0: return false
	var expression := RegEx.new()
	expression.compile("^[A-Za-z0-9+/]*={0,2}$")
	return expression.search(value) != null
