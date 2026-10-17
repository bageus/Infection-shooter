extends HBoxContainer
## Two explicit loadout choices above the active tree.
const TEXT := preload("res://game/bootstrap/app/mutation_text.gd")
const ICONS := preload("res://game/bootstrap/app/mutation_skill_icons.gd")
var runtime: Node
var labels: Array[String] = []


func configure(infection: Node, bindings: Array[String]) -> void:
	runtime = infection
	labels = bindings
	position = Vector2(320, 8)
	size = Vector2(490, 44)
	add_theme_constant_override("separation", 12)
	var equipped: Array = runtime.call("equipped_skills")
	var available: Array = runtime.call("assignable_skills")
	for index in 2:
		var button := MenuButton.new()
		button.name = "SkillSlot%d" % (index + 1)
		button.custom_minimum_size = Vector2(235, 44)
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", 13)
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.clip_text = true
		var id := str(equipped[index])
		button.text = labels[index] + " · " + (TEXT.t("mutationEmptySlot") if id.is_empty() else TEXT.skill_name(id))
		button.icon = ICONS.for_skill(id)
		button.add_theme_constant_override("icon_max_width", 28)
		button.disabled = available.is_empty()
		if not id.is_empty() and not runtime.call("has_skill", id):
			button.modulate = Color(0.45, 0.45, 0.45)
		add_child(button)
		var popup := button.get_popup()
		var choices: Array[String] = [""]
		popup.add_item(TEXT.t("mutationClearSlot"), 0)
		for candidate: String in available:
			if candidate == equipped[1 - index]:
				continue
			choices.append(candidate)
			popup.add_icon_item(ICONS.for_skill(candidate), TEXT.skill_name(candidate), choices.size() - 1)
		var slot := index
		popup.id_pressed.connect(func(item: int) -> void: runtime.call("assign_skill", slot, choices[item]))
