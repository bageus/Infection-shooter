extends Control

# Combat HUD strip for mutation skills: a key badge that opens the tree, one
# icon circle per active skill (cooldown sweep while charging, green ring when
# ready) and a short feed above it naming passives as they fire. Hidden while
# the player has no active skill. Never wider than the vitals panel.

const SKILL_ICONS := preload("res://game/bootstrap/app/mutation_skill_icons.gd")
const BODY := preload("res://assets/interface/fonts/body.ttf")
const PANEL := Color("151a1ce0")
const BORDER := Color("646760b3")
const BORDER_DIM := Color("3b403fcc")
const ACCENT := Color("a52d30")
const INK := Color("e2dfd4")
const MUTED := Color("b7b6ad")
const FAINT := Color("7c7d76")
const READY := Color(0.42, 0.86, 0.25)
const TRACK := Color("0a0d0ee6")
## Matches the vitals panel (18..380) so the strip never sticks out past it.
const MAX_WIDTH := 362.0
const LEFT := 18.0
const BAR_BOTTOM := -122.0
const VITALS_TOP := -112.0
const CIRCLE := 40.0
const MIN_CIRCLE := 20.0
const GAP := 8.0
const PAD := 8.0
const BADGE := 22.0
const FEED_ICON := 26.0
const FEED_LIMIT := 4
const FEED_MIN_TIME := 2.4
const FEED_FADE := 0.5

var runtime: Node
var open_badge: Button
var circles: Array[SkillCircle] = []
var feed: VBoxContainer
var _strip: Panel
var _skills: Array[String] = []
var _bindings: Array[String] = []
var _feed_entries: Dictionary = {}


class SkillCircle extends Control:
	var skill_id := ""
	var binding := ""
	var icon: Texture2D
	var ratio := 0.0
	var remaining := 0.0
	var castable := false
	var _flash := 0.0
	var _font: Font

	func _init(id: String, key: String, texture: Texture2D, font: Font) -> void:
		skill_id = id
		binding = key
		icon = texture
		_font = font
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	func refresh(cooldown_ratio: float, seconds: float, can_cast: bool, delta: float) -> void:
		var was_ready := castable
		castable = can_cast
		if castable and not was_ready and ratio > 0.0:
			_flash = 0.6
		_flash = maxf(0.0, _flash - delta)
		ratio = cooldown_ratio
		remaining = seconds
		queue_redraw()

	func _draw() -> void:
		var center := size * 0.5
		var radius := minf(size.x, size.y) * 0.5 - 2.0
		draw_circle(center, radius, TRACK)
		if castable:
			draw_arc(center, radius + 1.0, 0.0, TAU, 48, Color(READY, 0.28 + _flash), 4.0, true)
		if icon != null:
			var side := radius * 1.25
			var tint := INK if castable else (MUTED if ratio > 0.0 else FAINT)
			draw_texture_rect(icon, Rect2(center - Vector2(side, side) * 0.5, Vector2(side, side)), false, tint)
		if ratio > 0.0:
			# Dark sweep shrinking clockwise from twelve o'clock as the skill recharges.
			var points := PackedVector2Array([center])
			var steps := maxi(2, ceili(48.0 * ratio))
			for i in steps + 1:
				var angle := -PI * 0.5 + TAU * ratio * float(i) / float(steps)
				points.append(center + Vector2(cos(angle), sin(angle)) * radius)
			draw_colored_polygon(points, Color(0, 0, 0, 0.62))
			var text := str(ceili(remaining))
			var font_size := roundi(radius * 0.8)
			var text_size := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
			draw_string(_font, center + Vector2(-text_size.x * 0.5, text_size.y * 0.32), text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, INK)
		draw_arc(center, radius, 0.0, TAU, 48, READY if castable else BORDER, 1.5 if castable else 1.0, true)
		if not binding.is_empty():
			var label_size := roundi(maxf(9.0, radius * 0.48))
			var width := _font.get_string_size(binding, HORIZONTAL_ALIGNMENT_LEFT, -1, label_size).x
			var box := Rect2(Vector2(size.x - width - 6.0, size.y - label_size - 3.0), Vector2(width + 6.0, label_size + 3.0))
			draw_rect(box, PANEL)
			draw_rect(box, FAINT, false, 1.0)
			draw_string(_font, box.position + Vector2(3.0, label_size), binding, HORIZONTAL_ALIGNMENT_LEFT, -1, label_size, MUTED)


func configure(infection: Node, open_tree: Callable) -> void:
	runtime = infection
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strip = Panel.new()
	_strip.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	var frame := StyleBoxFlat.new()
	frame.bg_color = PANEL
	frame.border_color = BORDER
	frame.set_border_width_all(1)
	frame.shadow_color = Color(0, 0, 0, 0.35)
	frame.shadow_size = 8
	_strip.add_theme_stylebox_override("panel", frame)
	add_child(_strip)
	var accent := ColorRect.new()
	accent.color = ACCENT
	accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	accent.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	accent.offset_right = 3.0
	_strip.add_child(accent)
	open_badge = Button.new()
	open_badge.focus_mode = Control.FOCUS_NONE
	open_badge.tooltip_text = "Mutation tree"
	open_badge.add_theme_font_override("font", BODY)
	open_badge.add_theme_font_size_override("font_size", 13)
	var outline := StyleBoxFlat.new()
	outline.bg_color = Color.TRANSPARENT
	outline.border_color = FAINT
	outline.set_border_width_all(1)
	outline.content_margin_left = 4
	outline.content_margin_right = 4
	var filled := outline.duplicate() as StyleBoxFlat
	filled.bg_color = ACCENT
	filled.border_color = ACCENT
	for state in ["normal", "focus", "disabled"]:
		open_badge.add_theme_stylebox_override(state, outline)
	open_badge.add_theme_stylebox_override("hover", filled)
	open_badge.add_theme_stylebox_override("pressed", filled)
	for state in ["font_color", "font_focus_color"]:
		open_badge.add_theme_color_override(state, MUTED)
	open_badge.add_theme_color_override("font_hover_color", INK)
	open_badge.add_theme_color_override("font_pressed_color", INK)
	open_badge.pressed.connect(open_tree)
	_strip.add_child(open_badge)
	feed = VBoxContainer.new()
	feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	feed.add_theme_constant_override("separation", 4)
	feed.alignment = BoxContainer.ALIGNMENT_END
	feed.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	add_child(feed)
	if runtime.has_signal("passive_triggered"):
		runtime.connect("passive_triggered", show_passive)


## Rebuilds the circles; `bindings[i]` is the key label for skills[i] ("" for none).
func rebuild(skills: Array[String], bindings: Array[String], open_binding: String) -> void:
	open_badge.text = open_binding
	if skills == _skills and bindings == _bindings and not circles.is_empty():
		_layout()
		return
	_skills = skills.duplicate()
	_bindings = bindings.duplicate()
	for circle in circles:
		_strip.remove_child(circle)
		circle.queue_free()
	circles.clear()
	for index in skills.size():
		var circle := SkillCircle.new(skills[index], bindings[index], SKILL_ICONS.for_skill(skills[index]), BODY)
		circle.tooltip_text = _skill_name(skills[index])
		var skill_id := skills[index]
		circle.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				runtime.call("cast_skill", skill_id)
				circle.accept_event())
		_strip.add_child(circle)
		circles.append(circle)
	_layout()
	_update_circles(0.0)


func has_skills() -> bool:
	return not circles.is_empty()


func _layout() -> void:
	var badge_width := maxf(BADGE, open_badge.get_combined_minimum_size().x)
	var count := circles.size()
	var room := MAX_WIDTH - PAD * 2.0 - 3.0 - badge_width - GAP
	var circle := CIRCLE
	var gap := GAP
	if count > 0:
		circle = minf(CIRCLE, (room - gap * float(count - 1)) / float(count))
		if circle < CIRCLE * 0.75:
			# Crowded: tighten spacing before shrinking the circles further.
			gap = GAP * 0.5
			circle = clampf((room - gap * float(count - 1)) / float(count), MIN_CIRCLE, CIRCLE)
	var height := circle + PAD * 2.0
	var width := minf(MAX_WIDTH, PAD * 2.0 + 3.0 + badge_width + GAP + float(count) * (circle + gap) - gap)
	_strip.offset_left = LEFT
	_strip.offset_right = LEFT + width
	_strip.offset_bottom = BAR_BOTTOM
	_strip.offset_top = BAR_BOTTOM - height
	open_badge.position = Vector2(PAD + 3.0, (height - BADGE) * 0.5)
	open_badge.size = Vector2(badge_width, BADGE)
	var x := PAD + 3.0 + badge_width + GAP
	for item in circles:
		item.position = Vector2(x, PAD)
		item.size = Vector2(circle, circle)
		x += circle + gap
	_strip.visible = count > 0
	_place_feed()


func _place_feed() -> void:
	var bottom := (_strip.offset_top if _strip.visible else VITALS_TOP) - 8.0
	feed.offset_left = LEFT
	feed.offset_right = LEFT + MAX_WIDTH
	feed.offset_bottom = bottom
	feed.offset_top = bottom - (FEED_ICON + 4.0) * FEED_LIMIT


func _process(delta: float) -> void:
	if runtime == null:
		return
	_update_circles(delta)
	_update_feed(delta)


func _update_circles(delta: float) -> void:
	for circle in circles:
		circle.refresh(
			float(runtime.call("skill_cooldown_ratio", circle.skill_id)),
			float(runtime.call("skill_cooldown_remaining", circle.skill_id)),
			bool(runtime.call("can_cast_skill", circle.skill_id)), delta)


func show_passive(skill_id: String, duration: float = 0.0) -> void:
	var lifetime := maxf(FEED_MIN_TIME, duration)
	if _feed_entries.has(skill_id):
		var entry: Dictionary = _feed_entries[skill_id]
		entry["left"] = lifetime
		entry["total"] = lifetime
		(entry["row"] as Control).modulate.a = 1.0
		feed.move_child(entry["row"], feed.get_child_count() - 1)
		return
	if _feed_entries.size() >= FEED_LIMIT:
		_drop_entry(str(feed.get_child(0).get_meta("skill_id")))
	var row := HBoxContainer.new()
	row.set_meta("skill_id", skill_id)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	var ring := FeedIcon.new(SKILL_ICONS.for_skill(skill_id))
	ring.custom_minimum_size = Vector2(FEED_ICON, FEED_ICON)
	row.add_child(ring)
	var label := Label.new()
	label.text = _skill_name(skill_id).to_upper()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", BODY)
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", INK)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	row.add_child(label)
	feed.add_child(row)
	_feed_entries[skill_id] = {"row": row, "ring": ring, "left": lifetime, "total": lifetime}


func _update_feed(delta: float) -> void:
	for skill_id in _feed_entries.keys():
		var entry: Dictionary = _feed_entries[skill_id]
		entry["left"] = float(entry["left"]) - delta
		var left := float(entry["left"])
		if left <= 0.0:
			_drop_entry(skill_id)
			continue
		(entry["row"] as Control).modulate.a = clampf(left / FEED_FADE, 0.0, 1.0)
		(entry["ring"] as FeedIcon).set_progress(left / float(entry["total"]))


func _drop_entry(skill_id: String) -> void:
	var entry: Dictionary = _feed_entries.get(skill_id, {})
	_feed_entries.erase(skill_id)
	if not entry.is_empty():
		var row := entry["row"] as Control
		feed.remove_child(row)
		row.queue_free()


func feed_skills() -> Array[String]:
	var result: Array[String] = []
	for row in feed.get_children():
		result.append(str(row.get_meta("skill_id")))
	return result


func _skill_name(skill_id: String) -> String:
	for row in runtime.call("skill_catalog"):
		if str(row[0]) == skill_id:
			return str(row[1])
	return skill_id


class FeedIcon extends Control:
	var icon: Texture2D
	var progress := 1.0

	func _init(texture: Texture2D) -> void:
		icon = texture
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

	func set_progress(value: float) -> void:
		if not is_equal_approx(value, progress):
			progress = value
			queue_redraw()

	func _draw() -> void:
		var center := size * 0.5
		var radius := minf(size.x, size.y) * 0.5 - 2.0
		draw_circle(center, radius, TRACK)
		if icon != null:
			var side := radius * 1.25
			draw_texture_rect(icon, Rect2(center - Vector2(side, side) * 0.5, Vector2(side, side)), false, INK)
		draw_arc(center, radius, 0.0, TAU, 40, BORDER_DIM, 1.0, true)
		# Ring drains with the effect's remaining time.
		draw_arc(center, radius, -PI * 0.5, -PI * 0.5 + TAU * progress, 40, READY, 2.0, true)
