extends RefCounted
## Web arena progress kept across runs: coins (global, a death never takes them) and the arenas already
## beaten. A kill pays by enemy kind. Saved in user://web_progress.json, at most every SAVE_GAP seconds
## while playing and always on flush().

const SHOP := preload("res://game/bootstrap/app/web_shop.gd")
const PATH := "user://web_progress.json"
const VERSION := 1
const SAVE_GAP := 2.0
## Coins for one kill: hunger 1, each next kind one more, the Horde 100.
const PRICES := {"hunger": 1, "revenant": 2, "brute": 3, "titan": 4, "colossus": 5, "horde": 100}

static var path := PATH # tests point it at a scratch file
static var _loaded := false
static var _profile := SHOP.new_profile() ## coins, ammo, supplies and weapons of the shop
static var _beaten: Array[String] = []
static var _dirty := false
static var _saved_at := 0.0


static func reset_cache() -> void:
	_loaded = false
	_dirty = false


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_profile = SHOP.new_profile()
	_beaten.clear()
	if not FileAccess.file_exists(path):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary or int(data.get("version", 0)) != VERSION:
		return
	_profile = SHOP.sanitize(data)
	if data.get("beaten") is Array:
		for name: Variant in data["beaten"]:
			_beaten.append(str(name))


static func coins() -> int:
	return int(profile()["coins"])


## The live shop profile; call mark_dirty() after changing it so it is saved.
static func profile() -> Dictionary:
	_load()
	return _profile


static func mark_dirty() -> void:
	_dirty = true
	flush()


static func price(enemy_kind: String) -> int:
	return int(PRICES.get(enemy_kind, 1))


## Pays the kill of `enemy_kind`; returns the new total.
static func add_kill(enemy_kind: String) -> int:
	_load()
	_profile["coins"] = int(_profile["coins"]) + price(enemy_kind)
	_dirty = true
	if Time.get_ticks_msec() / 1000.0 - _saved_at >= SAVE_GAP:
		flush()
	return coins()


static func is_beaten(arena: String) -> bool:
	_load()
	return arena in _beaten


static func mark_beaten(arena: String) -> void:
	_load()
	if not arena.is_empty() and arena not in _beaten:
		_beaten.append(arena)
		_dirty = true
		flush()


static func flush() -> void:
	if not _loaded or not _dirty:
		return
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(_profile.merged({"version": VERSION, "beaten": _beaten})))
	file.close()
	_dirty = false
	_saved_at = Time.get_ticks_msec() / 1000.0
