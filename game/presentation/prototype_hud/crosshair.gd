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


var _system_cursor_hidden := false


func _process(_delta: float) -> void:
	crosshair.position = get_viewport().get_mouse_position()
	# This drawn reticle is the aim cursor: an OS pointer trailing it by a frame reads as a separate cursor.
	if not _system_cursor_hidden and Input.mouse_mode != Input.MOUSE_MODE_HIDDEN:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
		_system_cursor_hidden = true
	if scope == null or not is_instance_valid(player):
		return
	scope.position = crosshair.position
	scope.call("update_view", player.call("get_weapon_view"))
	crosshair.visible = not scope.visible


# Menus, planning, death and the mutation tree all pause the tree and need the OS pointer back.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED or what == NOTIFICATION_EXIT_TREE:
		_restore_system_cursor()


func _restore_system_cursor() -> void:
	if _system_cursor_hidden:
		_system_cursor_hidden = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
