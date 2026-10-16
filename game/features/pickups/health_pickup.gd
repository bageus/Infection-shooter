extends Area3D

@export var heal_amount: float = 35.0
var _consumed := false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if _consumed or body == null or not body.has_method("heal"):
		return
	# Keep the latch during collector signals to prevent a second award.
	_consumed = true
	var accepted := float(body.call("heal", heal_amount, &"medkit")) > 0.0
	if not accepted:
		_consumed = false
		return
	if body.has_method("play_item_sound"):
		body.call("play_item_sound", &"medkit_pickup")
		body.call("play_item_sound", &"medkit_use")
	queue_free()
