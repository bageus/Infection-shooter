extends Control

signal action_requested(action: String)

const STYLE := preload("res://game/bootstrap/app/menu/menu_style.gd")
const PREFERENCES := preload("res://game/bootstrap/app/menu/menu_preferences.gd")
const DIALOG := preload("res://game/bootstrap/app/menu/menu_dialog.gd")
const BACKGROUNDS := {
	"main": preload("res://assets/interface/backgrounds/main.png"),
	"pause": preload("res://assets/interface/backgrounds/pause.png"),
	"failed": preload("res://assets/interface/backgrounds/game_over.png"),
	"complete": preload("res://assets/interface/backgrounds/mission_complete.png")}

@export_enum("main", "pause", "failed", "complete") var screen_kind := "main"
var preferences = PREFERENCES.new()
var translations: Dictionary
var modal: Control
var buttons: Array[Button] = []
var background: TextureRect
var content: VBoxContainer
var footer: Label
var keyboard: Label
var reason_key := ""
var _click_player: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	translations = JSON.parse_string(FileAccess.get_file_as_string("res://assets/interface/translations.json"))
	preferences.load_settings()
	_click_player = AudioStreamPlayer.new()
	_click_player.stream = _click_stream()
	add_child(_click_player)
	background = TextureRect.new()
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := TextureRect.new()
	shade.texture = STYLE.gradient(Color("080b0edd"), Color("080b0e00"))
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	add_child(content)
	footer = STYLE.label("", 10)
	add_child(footer)
	keyboard = STYLE.label("", 10)
	add_child(keyboard)
	resized.connect(_layout)
	visibility_changed.connect(_focus_first)
	refresh()


func text(key: String) -> String:
	return str(translations[preferences.values.language].get(key, key))


func show_screen(kind: String, reason: String = "") -> void:
	screen_kind = kind
	reason_key = reason
	preferences.load_settings()
	refresh()
	show()
	_focus_first()


func refresh() -> void:
	theme = STYLE.make_theme(preferences.values.text_scale)
	background.texture = BACKGROUNDS[screen_kind]
	background.modulate = Color(preferences.values.brightness, preferences.values.brightness, preferences.values.brightness)
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	buttons.clear()
	_build_content()
	footer.text = "━━   " + text({"main": "quarantine", "pause": "floor", "failed": "lastSignal", "complete": "evac"}[screen_kind]).to_upper()
	keyboard.text = text("keys")
	_layout()
	_focus_first()


func _build_content() -> void:
	var factor: float = preferences.values.text_scale
	if screen_kind != "main":
		content.add_child(STYLE.label(text("suspended") if screen_kind == "pause" else ("GAME OVER" if screen_kind == "failed" else "MISSION COMPLETE"), 11))
	var headline: String = {"main": "INFECTION\nSHOOTER", "pause": text("pause"),
		"failed": text("signal") + "\n" + text("lost"), "complete": text("samples") + "\n" + text("extracted")}[screen_kind]
	var title := STYLE.label(headline.to_upper(), 62, true)
	title.add_theme_constant_override("line_spacing", -10)
	content.add_child(title)
	var subtitle := STYLE.label(text({"main": "patient", "pause": "alpha", "failed": "failed", "complete": "notCured"}[screen_kind]).to_upper(), roundi(12 * factor))
	subtitle.add_theme_color_override("font_color", STYLE.MUTED)
	content.add_child(subtitle)
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 16
	content.add_child(spacer)
	match screen_kind:
		"main":
			_add_button("new", "briefing")
			_add_button("continue", "continue", true).tooltip_text = text("noSave")
			_add_button("settings", "settings")
			_add_button("about", "about")
			_add_button("exit", "quit")
		"pause":
			_add_button("continue", "resume")
			_add_button("planning", "planning")
			_add_button("settings", "settings")
			_add_button("restart", "restart")
			_add_button("toMain", "main")
		"failed":
			_add_button("checkpoint", "continue", true)
			_add_button("restart", "restart")
			_add_button("toMain", "main")
		"complete":
			_add_button("toMain", "main")
			_add_button("new", "restart")
	var note := STYLE.label(text(_note_key()), roundi(11 * factor))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override("font_color", STYLE.MUTED)
	note.custom_minimum_size.y = 35
	content.add_child(note)


func _note_key() -> String:
	if not reason_key.is_empty():
		return reason_key
	return {"main": "noSave", "pause": "pauseNote", "failed": "noSave", "complete": "successNote"}[screen_kind]


func _add_button(key: String, action: String, disabled: bool = false) -> Button:
	var button := STYLE.button(text(key), activate.bind(action), disabled)
	button.name = action.to_pascal_case()
	if is_instance_valid(modal):
		button.focus_mode = Control.FOCUS_NONE
	content.add_child(button)
	buttons.append(button)
	return button


func activate(action: String) -> void:
	play_click()
	if action in ["settings", "about", "briefing", "quit", "restart", "main"]:
		_open_dialog(action)
	else:
		dispatch(action)


func dispatch(action: String) -> void:
	close_dialog()
	action_requested.emit(action)


func _open_dialog(kind: String) -> void:
	close_dialog()
	for button in buttons:
		button.focus_mode = Control.FOCUS_NONE
	modal = DIALOG.new()
	add_child(modal)
	modal.call("setup", self, kind)


func close_dialog() -> void:
	if is_instance_valid(modal):
		remove_child(modal)
		modal.queue_free()
	modal = null
	for button in buttons:
		button.focus_mode = Control.FOCUS_ALL
	_focus_first()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_ESCAPE:
		if is_instance_valid(modal):
			close_dialog()
		elif screen_kind == "pause":
			dispatch("resume")
		elif screen_kind in ["failed", "complete"]:
			dispatch("main")
		else:
			_open_dialog("quit")
		get_viewport().set_input_as_handled()
	elif event.keycode in [KEY_UP, KEY_DOWN] and not is_instance_valid(modal):
		var available: Array[Button] = []
		for button in buttons:
			if not button.disabled:
				available.append(button)
		var index := available.find(get_viewport().gui_get_focus_owner())
		available[posmod(index + (1 if event.keycode == KEY_DOWN else -1), available.size())].grab_focus()
		get_viewport().set_input_as_handled()


func _layout() -> void:
	if content == null:
		return
	content.position = Vector2(size.x * 0.06, size.y * 0.10)
	content.size.x = minf(380, size.x * 0.43)
	footer.position = Vector2(size.x * 0.06, size.y * 0.94)
	keyboard.position = Vector2(size.x - keyboard.get_minimum_size().x - size.x * 0.04, size.y * 0.94)
	keyboard.visible = size.x >= 1000


func _focus_first() -> void:
	if not is_visible_in_tree() or is_instance_valid(modal):
		return
	for button in buttons:
		if not button.disabled:
			button.grab_focus()
			break


func play_click() -> void:
	if preferences.values.sound and preferences.values.volume > 0:
		_click_player.volume_db = linear_to_db(preferences.values.volume * 0.15)
		_click_player.play()


func _click_stream() -> AudioStreamWAV:
	var data := PackedByteArray()
	for index in 2205:
		var time := float(index) / 22050.0
		var sample := int(sin(TAU * (270.0 * time - 625.0 * time * time)) * exp(-time * 60) * 16000)
		data.append(sample & 255)
		data.append((sample >> 8) & 255)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	stream.data = data
	return stream
