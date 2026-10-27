extends HBoxContainer
## Two explicit loadout choices above the active tree.
const TEXT := preload("res://game/bootstrap/app/mutation_text.gd")
const ICONS := preload("res://game/bootstrap/app/mutation_skill_icons.gd")
const INFO := preload("res://game/bootstrap/app/mutation_skill_info.gd")
const SFX := preload("res://game/core/audio/public/sound_events.gd")
const STYLE := preload("res://game/bootstrap/app/menu/menu_style.gd")
# Same glyph size as the tree circles, so hotbar and tree read as one system.
const ICON_SIZE := 42
const SLOT_SIZE := Vector2(260, 52)
const LIT := Color(0.3, 0.95, 0.1)
var runtime: Node
var labels: Array[String] = []


## show_card(id, info, target: Rect2) and hide_card() open and close the shared skill card.
func configure(infection: Node, bindings: Array[String], show_card: Callable, hide_card: Callable) -> void:
	runtime = infection
	labels = bindings
	size = Vector2(SLOT_SIZE.x * 2.0 + 12.0, SLOT_SIZE.y)
	position = Vector2((1200.0 - size.x) * 0.5, 4.0)
	add_theme_constant_override("separation", 12)
	var equipped: Array = runtime.call("equipped_skills")
	var available: Array = runtime.call("assignable_skills")
	for index in 2:
		var button := MenuButton.new()
		button.name = "SkillSlot%d" % (index + 1)
		button.custom_minimum_size = SLOT_SIZE
		# MenuButton is flat by default, which would hide the slot frame below.
		button.flat = false
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", 14)
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.clip_text = true
		var id := str(equipped[index])
		button.text = labels[index] + " · " + (TEXT.t("mutationEmptySlot") if id.is_empty() else TEXT.skill_name(id))
		button.icon = ICONS.for_skill(id)
		button.add_theme_constant_override("icon_max_width", ICON_SIZE)
		button.disabled = available.is_empty()
		_style_slot(button, not id.is_empty())
		if not id.is_empty() and not runtime.call("has_skill", id):
			button.modulate = Color(0.45, 0.45, 0.45)
		if not id.is_empty():
			button.mouse_entered.connect(func() -> void: show_card.call(id, INFO.for_skill(runtime, id), button.get_global_rect()))
			button.mouse_exited.connect(hide_card)
		add_child(button)
		var popup := button.get_popup()
		popup.add_theme_constant_override("icon_max_width", ICON_SIZE)
		var choices: Array[String] = [""]
		popup.add_item(TEXT.t("mutationClearSlot"), 0)
		for candidate: String in available:
			if candidate == equipped[1 - index]:
				continue
			choices.append(candidate)
			popup.add_icon_item(ICONS.for_skill(candidate), TEXT.skill_name(candidate), choices.size() - 1)
		var slot := index
		popup.id_pressed.connect(func(item: int) -> void:
			# Refused while the slot's effect runs (or the choice is invalid): audible denial.
			if choices[item] != equipped[slot] and not bool(runtime.call("assign_skill", slot, choices[item])):
				SFX.play_ui(self, &"access_denied"))
		# Items are numbered in list order, so the item id doubles as its row.
		popup.id_focused.connect(func(item: int) -> void:
			if choices[item].is_empty():
				return
			var row := popup.size.y / float(maxi(1, popup.item_count))
			var target := Rect2(popup.position.x, popup.position.y + row * item, popup.size.x, row)
			show_card.call(choices[item], INFO.for_skill(runtime, choices[item]), target))
		popup.popup_hide.connect(hide_card)


func _style_slot(button: Button, equipped: bool) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.2, 0.1) if equipped else Color("1c2225")
	style.border_color = LIT if equipped else Color("646760")
	style.set_border_width_all(2)
	style.set_corner_radius_all(int(SLOT_SIZE.y * 0.5))
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	var hover := style.duplicate() as StyleBoxFlat
	hover.border_color = STYLE.INK
	hover.bg_color = Color(0.16, 0.45, 0.06) if equipped else Color("262e32")
	for state in ["normal", "pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state, style)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_color_override("font_color", STYLE.INK)
	button.add_theme_color_override("font_disabled_color", STYLE.MUTED)
