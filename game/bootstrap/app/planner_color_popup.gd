extends RefCounted
## Keep every picker control accessible even below the viewport's minimum height.

static func bind(button: ColorPickerButton) -> void:
	var popup := button.get_popup()
	var picker := button.get_picker()
	picker.presets_visible = false
	picker.reparent(_scroll(popup))
	popup.about_to_popup.connect(func() -> void: fit.call_deferred(popup, button.get_viewport_rect().size))


static func _scroll(popup: PopupPanel) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(330, 360)
	popup.add_child(scroll)
	return scroll


static func fit(popup: PopupPanel, viewport_size: Vector2) -> void:
	var available := Vector2i(viewport_size) - Vector2i(24, 24)
	var scroll := popup.get_child(popup.get_child_count() - 1) as ScrollContainer
	scroll.custom_minimum_size = Vector2(mini(330, available.x), mini(480, available.y))
	popup.size = Vector2i(scroll.custom_minimum_size) + Vector2i(8, 8)
	@warning_ignore("integer_division")
	popup.position = (Vector2i(viewport_size) - popup.size) / 2
