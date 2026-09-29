extends RefCounted

var _button: Button
var _player: Node
var _weapon: Node
var _pointer_down := false
var _block_until_physics_frame := -1
var _gameplay_active := true


func configure(button: Button, player: Node) -> void:
	_button = button
	_player = player
	_button.pressed.connect(_on_pressed)
	_button.mouse_entered.connect(_on_mouse_entered)
	_button.mouse_exited.connect(_on_mouse_exited)
	update(true)


func update(gameplay_active: bool) -> void:
	_gameplay_active = gameplay_active
	var current := _player.call("get_current_weapon") as Node
	var supported := gameplay_active and current != null and current.has_method("toggle_explosion_variant")
	if _weapon != current or not supported:
		_clear_hover()
		_pointer_down = false
		_button.set_pressed_no_signal(false)
	_weapon = current if supported else null
	_button.visible = supported
	if not supported:
		return
	_button.text = "Explosion: %d  |  Switch" % int(_weapon.call("get_explosion_variant"))
	var hovered := _pointer_inside(_button.get_viewport().get_mouse_position()) or _pointer_down or Engine.get_physics_frames() <= _block_until_physics_frame
	_weapon.call("set_test_controls_hovered", hovered)


func handle_input(event: InputEvent) -> bool:
	if _button.get_tree().paused or not _button.is_visible_in_tree():
		return false
	if event is InputEventMouseMotion:
		update(true)
		return false
	var click := event as InputEventMouseButton
	if click == null or click.button_index != MOUSE_BUTTON_LEFT:
		return false
	var inside := _pointer_inside(click.position)
	if click.pressed and inside:
		_pointer_down = true
		_block_until_physics_frame = Engine.get_physics_frames() + 1
		_button.set_pressed_no_signal(true)
		_on_pressed()
		return true
	if not click.pressed and (_pointer_down or inside):
		_pointer_down = false
		_button.set_pressed_no_signal(false)
		update(true)
		return true
	return false


func _pointer_inside(viewport_position: Vector2) -> bool:
	if not _button.is_visible_in_tree():
		return false
	var local := _button.get_global_transform_with_canvas().affine_inverse() * viewport_position
	return Rect2(Vector2.ZERO, _button.size).has_point(local)


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
	update(_gameplay_active)


func _clear_hover() -> void:
	if is_instance_valid(_weapon):
		_weapon.call("set_test_controls_hovered", false)
