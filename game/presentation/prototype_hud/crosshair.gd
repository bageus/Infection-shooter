extends CanvasLayer

const SCOPE := preload("res://game/presentation/prototype_hud/sniper_scope.gd")
@onready var crosshair: Control = $Crosshair
var player: Node
var scope: Control


# Public crosshair scene wiring: injected by the composition root.
func configure(actor: Node) -> void:
	player = actor
	if scope == null:
		scope = SCOPE.new()
		scope.name = "SniperScope"
		add_child(scope)


func _process(_delta: float) -> void:
	crosshair.position = get_viewport().get_mouse_position()
	if scope == null or not is_instance_valid(player):
		return
	scope.position = crosshair.position
	scope.call("update_view", player.call("get_weapon_view"))
	crosshair.visible = not scope.visible
