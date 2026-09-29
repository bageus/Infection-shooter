extends RefCounted

var _button: Button
var _player: Node
var _weapon: Node


func configure(button: Button, player: Node) -> void:
	_button = button
	_player = player
	_button.pressed.connect(_on_pressed)
	_button.mouse_entered.connect(_on_mouse_entered)
	_button.mouse_exited.connect(_on_mouse_exited)
	update(true)


func update(gameplay_active: bool) -> void:
	var current := _player.call("get_current_weapon") as Node
	var supported := gameplay_active and current != null and current.has_method("toggle_explosion_variant")
	if _weapon != current or not supported:
		_clear_hover()
	_weapon = current if supported else null
	_button.visible = supported
	if not supported:
		return
	_button.text = "Explosion: %d  |  Switch" % int(_weapon.call("get_explosion_variant"))
	var hovered := _button.is_visible_in_tree() and _button.get_global_rect().has_point(_button.get_global_mouse_position())
	_weapon.call("set_test_controls_hovered", hovered)


func _on_pressed() -> void:
	if _button.get_tree().paused or not _button.is_visible_in_tree():
		return
	var current := _player.call("get_current_weapon") as Node
	if current != null and current.has_method("toggle_explosion_variant"):
		current.call("toggle_explosion_variant")
		update(true)


func _on_mouse_entered() -> void:
	if is_instance_valid(_weapon):
		_weapon.call("set_test_controls_hovered", true)


func _on_mouse_exited() -> void:
	_clear_hover()


func _clear_hover() -> void:
	if is_instance_valid(_weapon):
		_weapon.call("set_test_controls_hovered", false)
