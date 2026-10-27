extends SceneTree
## Per-platform campaign config and the Platform autoload driven by a mock adapter.

const CONFIG := preload("res://game/bootstrap/app/campaign_config.gd")
const PLATFORM := preload("res://game/infrastructure/platform/public/platform.gd")
const MOCK := preload("res://game/infrastructure/platform/public/mock_platform_adapter.gd")
var failures := 0
var _shown: Array[bool] = []


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + what)


func _init() -> void:
	var config := CONFIG.new()
	_check(config.load_file(), "shipped config loads")
	_check(config.mode("itch") == "campaign" and config.levels("itch").size() == 3, "itch is a short campaign")
	_check(config.mode("yandex") == "endless" and config.levels("yandex") == ["tutorial", "endless"], "yandex is tutorial plus endless")
	_check(config.levels("unknown") == config.levels("desktop"), "unknown platform falls back to desktop")
	_check(config.endless_level("yandex") == "endless" and config.endless_level("itch") == "", "only the endless platform has an endless level")
	_check(config.map_paths("yandex") == ["res://content/levels/tutorial.json", "res://content/levels/endless.json"], "map paths follow the level list")
	_check(config.first_shipped_map("yandex") == "", "no shipped map yet, the default map plays")
	_check(PLATFORM.detect_id() == "desktop", "editor run is desktop")
	var platform: Node = PLATFORM.new()
	var mock := MOCK.new()
	mock.polls_until_done = 2
	platform.setup("yandex", mock)
	platform.ad_finished.connect(func(shown: bool) -> void: _shown.append(shown))
	_check(platform.is_yandex(), "yandex id")
	platform.show_ad()
	platform.show_ad()
	_check(mock.requests == 1, "second request while open is ignored")
	for i in 3:
		platform._process(0.0)
	_check(_shown == [true], "ad finished once as shown")
	mock.result = mock.AD_FAILED
	platform.show_ad()
	platform._process(0.0)
	platform._process(0.0)
	platform._process(0.0)
	_check(_shown == [true, false], "failed ad reports not shown")
	var plain: Node = PLATFORM.new()
	plain.setup("desktop", PLATFORM.BASE.new())
	plain.ad_finished.connect(func(shown: bool) -> void: _shown.append(shown))
	plain.show_ad()
	plain._process(0.0)
	_check(_shown == [true, false, false], "no-ads platform finishes at once")
	platform.free()
	plain.free()
	if failures > 0:
		quit(1)
		return
	print("campaign config tests passed")
	quit(0)
