extends SpotLight3D
## Private native transform observer; no per-frame callback or extra scene node.
var changed: Callable


func _ready() -> void:
	set_notify_transform(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and changed.is_valid():
		changed.call()


func _exit_tree() -> void:
	if changed.is_valid():
		changed.call()
