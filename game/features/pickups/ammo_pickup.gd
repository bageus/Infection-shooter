extends Area3D

@export var ammo_amount: int = 36
var _consumed := false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if _consumed or body == null or not body.has_method("add_ammo_to_current_weapon"):
		return
	# Keep the latch during collector signals to prevent a second award.
	_consumed = true
	var accepted := int(body.call("add_ammo_to_current_weapon", ammo_amount)) > 0
	if not accepted:
		_consumed = false
		return
	queue_free()
