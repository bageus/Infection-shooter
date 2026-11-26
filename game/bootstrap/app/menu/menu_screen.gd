extends Control

signal action_requested(action: String)

const SFX := preload("res://game/core/audio/public/sound_events.gd")
const STYLE := preload("res://game/bootstrap/app/menu/menu_style.gd")
const PREFERENCES := preload("res://game/bootstrap/app/menu/menu_preferences.gd")
const CAMPAIGN := preload("res://game/bootstrap/app/campaign_config.gd")
const PLATFORM := preload("res://game/infrastructure/platform/public/platform.gd")
const CHECKPOINT := preload("res://game/bootstrap/app/checkpoint_progress.gd")
const WEB_SHOP := preload("res://game/bootstrap/app/menu/web_shop_panel.gd")
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
var content_scroll: ScrollContainer
var content: VBoxContainer
var footer: Label
var keyboard: Label
var reason_key := ""
## Set by the game before a mission ends: its map is a checkpoint, so restart says so.
var checkpoint_mission := false
## Store page offered on the defeat and victory screens; empty on platforms without the promo.
var steam_url := ""
## Web arena shop beside the main menu buttons; only on a platform with the endless mode.
var shop_enabled := false
var shop: Control
var _click_player: AudioStreamPlayer
var _music: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	translations = JSON.parse_string(FileAccess.get_file_as_string("res://assets/interface/translations.json"))
	var campaign := CAMPAIGN.new()
	campaign.load_file()
	steam_url = campaign.steam_promo_url(PLATFORM.detect_id())
	shop_enabled = campaign.mode(PLATFORM.detect_id()) == "endless"
	preferences.load_settings()
	# The game scene (and its environment) may not be current yet; apply once
	# the tree has settled so saved volume and brightness hold from the start.
	(func() -> void: preferences.apply_to_game(get_tree())).call_deferred()
	_click_player = AudioStreamPlayer.new()
	_click_player.stream = _click_stream()
	_click_player.bus = &"UI"
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
	content_scroll = ScrollContainer.new()
	content_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content_scroll.follow_focus = true
	add_child(content_scroll)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	content_scroll.add_child(content)
	footer = STYLE.label("", 10)
	add_child(footer)
	keyboard = STYLE.label("", 10)
	keyboard.add_theme_color_override("font_color", Color("74262b"))
	add_child(keyboard)
	resized.connect(_layout)
	visibility_changed.connect(_focus_first)
	refresh()
	_music = preload("res://game/bootstrap/app/menu/menu_music.gd").new()
	add_child(_music)
	_music.call("setup", self)


func text(key: String) -> String:
	return str(translations[preferences.values.language].get(key, key))


func show_screen(kind: String, reason: String = "", checkpoint := false) -> void:
	screen_kind = kind
	reason_key = reason
	checkpoint_mission = checkpoint
	preferences.load_settings()
	refresh()
	show()
	if _music != null:
		_music.call("sync")
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
	if is_instance_valid(shop):
		remove_child(shop)
		shop.queue_free()
	shop = null
	if shop_enabled and screen_kind == "main":
		shop = WEB_SHOP.new()
		add_child(shop)
		shop.setup(self)
	footer.text = "━━   " + text("lastSignal").to_upper()
	footer.visible = screen_kind == "failed"
	keyboard.text = "v." + str(ProjectSettings.get_setting("application/config/version", "0.00.000"))
	_layout()
	_focus_first()


func _build_content() -> void:
	var factor: float = preferences.values.text_scale
	var headline: String = {"main": "INFECTION\nSHOOTER", "pause": text("pause"),
		"failed": text("failed").replace(" ", "\n"), "complete": text("missionDone").replace(" ", "\n")}[screen_kind]
	var title := STYLE.label(headline.to_upper(), 62, true)
	title.add_theme_constant_override("line_spacing", -10)
	var title_area := Control.new()
	title_area.custom_minimum_size.y = 140 if headline.contains("\n") else 74
	content.add_child(title_area)
	title_area.add_child(title)
	title.scale.x = 0.78
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 16
	content.add_child(spacer)
	match screen_kind:
		"main":
			_add_button("new", "briefing")
			var can_continue := not CHECKPOINT.resume_map().is_empty()
			var disabled_continue := _add_button("continue", "continue", not can_continue)
			disabled_continue.tooltip_text = "" if can_continue else text("noSave")
			var row := HBoxContainer.new()
			content.remove_child(disabled_continue)
			content.add_child(row)
			disabled_continue.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(disabled_continue)
			var no_save := STYLE.label(text("noSave"), roundi(10 * factor))
			no_save.name = "NoSave"
			no_save.visible = not can_continue
			no_save.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			no_save.add_theme_color_override("font_color", STYLE.MUTED)
			row.add_child(no_save)
			if OS.is_debug_build(): _add_button("loadMap", "load_map") # Planner only; release exports have none
			_add_button("settings", "settings")
			_add_button("about", "about")
			_add_button("aboutUs", "about_us")
			_add_button("exit", "quit")
		"pause":
			_add_button("continue", "resume")
			_add_button(_restart_key(), "restart")
			if OS.is_debug_build(): # The planner stays out of release exports
				_add_button("planning", "planning")
			_add_button("settings", "settings")
			_add_button("toMain", "main")
		"failed":
			_emphasize(_add_button(_restart_key(), "restart"))
			_add_button("toMain", "main")
			_add_steam_button()
		"complete":
			_add_continue_row()
			_add_button("toMain", "main")
			_add_steam_button()
	var note_key := _note_key()
	if not note_key.is_empty():
		var note := STYLE.label(text(note_key), roundi(11 * factor))
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.add_theme_color_override("font_color", STYLE.MUTED)
		note.custom_minimum_size.y = 35
		content.add_child(note)


func _add_steam_button() -> void:
	if not steam_url.is_empty():
		_add_button("steamPromo", "steam")


## Continue sits beside a checkpoint marker when the finished mission was a checkpoint.
func _add_continue_row() -> void:
	var go := _add_button("continue", "continue")
	_emphasize(go)
	content.remove_child(go)
	var row := HBoxContainer.new()
	content.add_child(row)
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(go)
	if checkpoint_mission:
		var marker := STYLE.label(text("checkpointLabel"), roundi(11 * preferences.values.text_scale))
		marker.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		marker.add_theme_color_override("font_color", STYLE.MUTED)
		row.add_child(marker)


func _emphasize(button: Button) -> void:
	button.custom_minimum_size.y = 72
	button.add_theme_font_size_override("font_size", 26)
	button.add_theme_color_override("font_color", Color("ffffff"))
	button.add_theme_color_override("font_focus_color", Color("ffffff"))


## Web builds keep the plain restart wording; desktop names the checkpoint it returns to.
func _restart_key() -> String:
	if OS.has_feature("web"):
		return "restart"
	return "restartCheckpoint" if checkpoint_mission else "restart"


func _note_key() -> String:
	if not reason_key.is_empty():
		return reason_key
	return "noSave" if screen_kind == "failed" else ""


func _add_button(key: String, action: String, disabled: bool = false) -> Button:
	var button := STYLE.button(text(key), activate.bind(action), disabled)
	button.name = action.to_pascal_case()
	if is_instance_valid(modal):
		button.focus_mode = Control.FOCUS_NONE
	button.mouse_entered.connect(play_hover.bind(button))
	content.add_child(button)
	buttons.append(button)
	return button


func activate(action: String) -> void:
	play_click()
	# A failed mission has no alternative to restarting, so that restart needs no confirmation.
	var direct := screen_kind == "failed" and action == "restart"
	if action in ["settings", "about", "about_us", "briefing", "quit", "restart", "main", "load_map"] and not direct:
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
	if is_visible_in_tree() and is_instance_valid(modal) and modal.call("consume_binding_input", event):
		get_viewport().set_input_as_handled()
		return
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
	elif event.keycode not in [KEY_TAB, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		# Leave GUI navigation to controls, but stop gameplay shortcuts behind menus.
		get_viewport().set_input_as_handled()


func _layout() -> void:
	if content == null:
		return
	content_scroll.position = Vector2(size.x * 0.06, size.y * 0.10)
	content_scroll.size = Vector2(minf(400, size.x * 0.43), size.y * 0.80)
	if is_instance_valid(shop):
		var left := content_scroll.position.x + content_scroll.size.x + 24.0
		shop.position = Vector2(left, size.y * 0.05)
		shop.size = Vector2(maxf(size.x - left - size.x * 0.02, 320.0), size.y * 0.90)
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
	if preferences.values.volume > 0:
		_click_player.volume_db = linear_to_db(preferences.values.volume * 0.15)
		_click_player.play()


func _click_stream() -> AudioStreamOggVorbis:
	return preload("res://assets/audio/ui/menu_click.ogg")

func play_hover(control: Control) -> void:
	if not is_visible_in_tree() or (control is BaseButton and control.disabled):
		return
	if preferences.values.volume > 0:
		SFX.play_ui(self, &"menu_hover")
