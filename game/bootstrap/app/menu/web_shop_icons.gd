extends RefCounted
## Shop icons cut out of the interface atlas (assets/icon_interface.png) by item id.

const ATLAS := preload("res://assets/icon_interface.png")
const REFERENCE_SIZE := Vector2(1774, 887)
const REGIONS := {
	"health": Rect2(56, 28, 204, 196),
	"antidote": Rect2(1528, 256, 192, 208),
	"armor": Rect2(1556, 24, 192, 204),
	"dna": Rect2(276, 688, 120, 188),
	"ad": Rect2(1536, 700, 212, 164),
	"pistol": Rect2(504, 260, 224, 200),
	"uzi": Rect2(790, 258, 280, 220),
	"shotgun": Rect2(1112, 258, 405, 212),
	"m16": Rect2(336, 468, 430, 200),
	"ak": Rect2(780, 472, 415, 190),
	"sniper": Rect2(1224, 472, 490, 200),
	"minigun": Rect2(64, 250, 400, 222),
	"launcher": Rect2(656, 10, 470, 240),
	# ammo packs, keyed "ammo_<pack>"
	"ammo_pistol": Rect2(656, 724, 148, 136),
	"ammo_uzi": Rect2(328, 40, 226, 194),
	"ammo_shotgun": Rect2(856, 708, 190, 150),
	"ammo_rifle": Rect2(460, 688, 140, 176),
	"ammo_sniper": Rect2(1212, 24, 306, 210),
	"ammo_minigun": Rect2(1304, 692, 198, 174),
}
static var _cache := {}


## Texture for an item id; null for an unknown id (callers show the text only).
static func texture(id: String) -> Texture2D:
	if not REGIONS.has(id):
		return null
	if not _cache.has(id):
		var atlas := AtlasTexture.new()
		atlas.atlas = ATLAS
		var ratio := Vector2(ATLAS.get_size()) / REFERENCE_SIZE
		var rect: Rect2 = REGIONS[id]
		atlas.region = Rect2(rect.position * ratio, rect.size * ratio)
		_cache[id] = atlas
	return _cache[id]


static func icon(id: String, size: Vector2) -> TextureRect:
	var view := TextureRect.new()
	view.texture = texture(id)
	view.custom_minimum_size = size
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return view
