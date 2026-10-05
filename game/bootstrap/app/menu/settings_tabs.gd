extends RefCounted
const NOTICES := preload("res://game/bootstrap/app/menu/settings_notices.gd")
var notices := NOTICES.new()
const EDITOR := preload("res://game/bootstrap/app/menu/control_binding_editor.gd")
var dialog: Control
var tabs: TabContainer
var controls: RefCounted


func setup(owner_dialog: Control, selected_tab: int) -> void:
	dialog = owner_dialog
	tabs = TabContainer.new()
	tabs.name = "SettingsTabs"
	tabs.custom_minimum_size = Vector2(530, 280)
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.tab_alignment = TabBar.ALIGNMENT_CENTER
	var outer: VBoxContainer = dialog.get("layout")
	outer.add_child(tabs)
	notices.setup(dialog, tabs)
	for index in 4:
		var page := ScrollContainer.new()
		page.name = ["General", "Controls", "Video", "Audio"][index]
		page.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		page.follow_focus = true
		tabs.add_child(page)
		tabs.set_tab_title(index, dialog.view.text(["tabGeneral", "tabControls", "tabVideo", "tabAudio"][index]))
		var margin := MarginContainer.new()
		margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		margin.add_theme_constant_override("margin_top", 20)
		page.add_child(margin)
		var box := VBoxContainer.new()
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_theme_constant_override("separation", 12)
		margin.add_child(box)
		dialog.set("layout", box)
		match index:
			0: _general()
			1:
				controls = EDITOR.new()
				controls.setup(dialog)
			2: _video()
			3: _audio()
	dialog.set("layout", outer)
	tabs.current_tab = clampi(selected_tab, 0, 3)
	tabs.tab_changed.connect(_tab_changed)


func _tab_changed(index: int) -> void:
	dialog.set("settings_tab", index)
	controls.cancel()


func _general() -> void:
	var language := OptionButton.new()
	language.name = "Language"
	language.add_item("Русский")
	language.add_item("English")
	language.selected = 1 if dialog.view.preferences.values.language == "en" else 0
	language.item_selected.connect(dialog._language_changed)
	dialog.call("_row", "language", language)
	var cloud := CheckButton.new()
	cloud.name = "TestMutagen"
	cloud.text = dialog.view.text("testMutagen")
	cloud.button_pressed = dialog.view.preferences.values.test_mutagen
	cloud.toggled.connect(func(value: bool) -> void: dialog.call("_change", "test_mutagen", value))
	dialog.get("layout").add_child(cloud)
	notices.set_notice(0, dialog.view.text("testMutagenHint"))


func _video() -> void:
	dialog.call("_slider", "brightness", "brightness", .8, 1.4, .05)
	var scale := OptionButton.new()
	scale.name = "TextScale"
	for percent in [100, 115, 130]:
		scale.add_item(str(percent) + "%")
	scale.selected = [1.0, 1.15, 1.3].find(dialog.view.preferences.values.text_scale)
	scale.item_selected.connect(dialog._scale_changed)
	dialog.call("_row", "scale", scale)
	var occlusion := OptionButton.new()
	occlusion.name = "Occlusion"
	occlusion.add_item(dialog.view.text("occlusionSilhouettes"))
	occlusion.add_item(dialog.view.text("occlusionHole"))
	occlusion.selected = dialog.view.preferences.values.occlusion_mode
	occlusion.item_selected.connect(func(index: int) -> void: dialog.call("_change", "occlusion_mode", index))
	dialog.call("_row", "occlusion", occlusion)
	dialog.call("_button", "fullscreen", dialog._fullscreen)


func _audio() -> void:
	dialog.call("_slider", "volume", "volume", 0, 1, .05)
	dialog.call("_slider", "effectsVolume", "effects_volume", 0, 1, .05)
	dialog.call("_slider", "musicVolume", "music_volume", 0, 1, .05)
	var sound := CheckButton.new()
	sound.name = "SoundToggle"
	sound.text = dialog.view.text("sound")
	sound.button_pressed = dialog.view.preferences.values.sound
	sound.toggled.connect(func(value: bool) -> void: dialog.call("_change", "sound", value))
	sound.mouse_entered.connect(dialog.view.play_hover.bind(sound))
	dialog.get("layout").add_child(sound)
