extends Node
## Autoload "Platform": which store the build is for and what that store offers.
## The id comes from the export preset custom feature tag, so a fix in shared code reaches every build.

signal ad_finished(shown: bool)

const BASE := preload("res://game/infrastructure/platform/public/platform_adapter.gd")
const YANDEX := preload("res://game/infrastructure/platform/yandex_adapter.gd")

var id := "desktop"
var adapter: RefCounted = BASE.new()
var _ad_open := false


static func detect_id() -> String:
	if OS.has_feature("yandex"):
		return "yandex"
	return "itch" if OS.has_feature("itch") else "desktop"


func _ready() -> void:
	setup(detect_id(), YANDEX.new() if detect_id() == "yandex" else BASE.new())


func setup(platform_id: String, platform_adapter: RefCounted) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # ads end while the defeat screen holds the tree paused
	id = platform_id
	adapter = platform_adapter
	adapter.start()
	set_process(false)


func is_yandex() -> bool:
	return id == "yandex"


## Fullscreen advertisement; ad_finished fires once with whether the player saw it.
func show_ad() -> void:
	if _ad_open:
		return
	_ad_open = true
	adapter.request_ad()
	set_process(true)


func _process(_delta: float) -> void:
	var state: String = adapter.poll_ad()
	if state == BASE.AD_PENDING:
		return
	_ad_open = false
	set_process(false)
	ad_finished.emit(state == BASE.AD_CLOSED)
