extends Area3D

enum PickupType { MEDKIT, AMMO_PISTOL, AMMO_UZI, AMMO_SHOTGUN, ANTIDOTE }

@export var pickup_type: PickupType = PickupType.MEDKIT
@export var amount: int = 20
var _consumed := false

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if _consumed or body == null:
		return
	var accepted := false
	match pickup_type:
		PickupType.MEDKIT:
			if body.has_method("heal"):
				accepted = float(body.call("heal", float(amount))) > 0.0
		PickupType.AMMO_PISTOL:
			if body.has_method("add_ammo_for_weapon"):
				accepted = int(body.call("add_ammo_for_weapon", "PISTOL", amount)) > 0
		PickupType.AMMO_UZI:
			if body.has_method("add_ammo_for_weapon"):
				accepted = int(body.call("add_ammo_for_weapon", "UZI", amount)) > 0
		PickupType.AMMO_SHOTGUN:
			if body.has_method("add_ammo_for_weapon"):
				accepted = int(body.call("add_ammo_for_weapon", "SHOTGUN", amount)) > 0
		PickupType.ANTIDOTE:
			if body.has_method("add_antidote"):
				accepted = bool(body.call("add_antidote", amount))
	if accepted:
		_consumed = true
		queue_free()
