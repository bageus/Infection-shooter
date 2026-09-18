extends Area3D

@export var ammo_amount: int = 36
var _consumed := false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if _consumed or body == null or not body.has_method("add_ammo_to_current_weapon"):
		return
	_consumed = true
	body.call("add_ammo_to_current_weapon", ammo_amount)
	queue_free()
