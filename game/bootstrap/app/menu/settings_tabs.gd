extends RefCounted
const NOTICES := preload("res://game/bootstrap/app/menu/settings_notices.gd")
var notices := NOTICES.new()
const SHADOWS := preload("res://game/bootstrap/app/menu/shadow_quality.gd")
const SETTLE_SECONDS := 0.35
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
	_style_tabs()
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
		margin.add_theme_constant_override("margin_top", 28)
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


## Pages share the dialog's own background; the tab strip is separated from
## the page by a thin rule and a gap instead of a differently tinted panel.
func _style_tabs() -> void:
	var page := StyleBoxFlat.new()
	page.bg_color = Color.TRANSPARENT
	page.border_color = Color(0.64, 0.64, 0.61, 0.32)
	page.border_width_top = 1
	page.content_margin_top = 6
	tabs.add_theme_stylebox_override("panel", page)
	for state in ["tab_unselected", "tab_hovered", "tab_selected", "tab_focus", "tab_disabled"]:
		var tab := StyleBoxFlat.new()
		tab.bg_color = Color("74262b66") if state == "tab_hovered" else Color.TRANSPARENT
		tab.border_color = Color("b8464d")
		tab.border_width_bottom = 2 if state == "tab_selected" else 0
		tab.content_margin_left = 16
		tab.content_margin_right = 16
		tab.content_margin_top = 8
		tab.content_margin_bottom = 8
		if state == "tab_focus":
			tab.border_width_bottom = 0
			tab.draw_center = false
		tabs.add_theme_stylebox_override(state, tab)
	tabs.add_theme_stylebox_override("tabbar_background", StyleBoxEmpty.new())
	tabs.add_theme_color_override("font_selected_color", Color("f4f1e8"))
	tabs.add_theme_color_override("font_unselected_color", Color("b7b6ad"))
	tabs.add_theme_color_override("font_hovered_color", Color("e2dfd4"))


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
	var scale := OptionButton.new()
	scale.name = "TextScale"
	for percent in [100, 115, 130]:
		scale.add_item(str(percent) + "%")
	scale.selected = [1.0, 1.15, 1.3].find(dialog.view.preferences.values.text_scale)
	scale.item_selected.connect(dialog._scale_changed)
	dialog.call("_row", "scale", scale)
	var cloud := CheckButton.new()
	cloud.name = "TestMutagen"
	cloud.text = dialog.view.text("testMutagen")
	cloud.button_pressed = dialog.view.preferences.values.test_mutagen
	cloud.toggled.connect(func(value: bool) -> void: dialog.call("_change", "test_mutagen", value))
	dialog.get("layout").add_child(cloud)
	var antidotes := CheckButton.new()
	antidotes.name = "InfiniteAntidotes"
	antidotes.text = dialog.view.text("infiniteAntidotes")
	antidotes.button_pressed = dialog.view.preferences.values.infinite_antidotes
	antidotes.toggled.connect(func(value: bool) -> void: dialog.call("_change", "infinite_antidotes", value))
	dialog.get("layout").add_child(antidotes)
	var dodge := OptionButton.new()
	dodge.name = "DodgeAnimation"
	dodge.add_item(dialog.view.text("dodgeAnimationRoll"))
	dodge.add_item(dialog.view.text("dodgeAnimationStrafe"))
	dodge.selected = dialog.view.preferences.values.dodge_animation
	dodge.item_selected.connect(func(index: int) -> void: dialog.call("_change", "dodge_animation", index))
	dialog.call("_row", "dodgeAnimation", dodge)
	dialog.call("_slider", "walkSpeed", "walk_speed_multiplier", 0.5, 1.5, 0.05, "%.2f×")
	dialog.call("_slider", "walkAnimationSpeed", "walk_animation_multiplier", 0.5, 2.0, 0.05, "%.2f×")
	notices.set_notice(0, dialog.view.text("testMutagenHint") + "\n\n" + dialog.view.text("walkTuningHint"))


func _video() -> void:
	preload("res://game/bootstrap/app/menu/display_options.gd").build(dialog)
	dialog.call("_slider", "brightness", "brightness", .8, 1.4, .05)
	var occlusion := OptionButton.new()
	occlusion.name = "Occlusion"
	occlusion.add_item(dialog.view.text("occlusionSilhouettes"))
	occlusion.add_item(dialog.view.text("occlusionHole"))
	occlusion.selected = dialog.view.preferences.values.occlusion_mode
	occlusion.item_selected.connect(func(index: int) -> void: dialog.call("_change", "occlusion_mode", index))
	dialog.call("_row", "occlusion", occlusion)
	var lighting := CheckButton.new()
	lighting.name = "Lighting"
	lighting.text = dialog.view.text("lighting")
	lighting.button_pressed = dialog.view.preferences.values.lighting
	lighting.toggled.connect(func(value: bool) -> void: dialog.call("_change", "lighting", value))
	dialog.get("layout").add_child(lighting)
	var game_only := CheckButton.new()
	game_only.name = "GameLightsOnly"
	game_only.text = dialog.view.text("gameLightsOnly")
	game_only.tooltip_text = dialog.view.text("gameLightsOnlyHint")
	game_only.button_pressed = dialog.view.preferences.values.game_lights_only
	game_only.toggled.connect(func(value: bool) -> void: dialog.call("_change", "game_lights_only", value))
	dialog.get("layout").add_child(game_only)
	var sunlight := CheckButton.new()
	sunlight.name = "Sunlight"
	sunlight.text = dialog.view.text("sunlight")
	sunlight.tooltip_text = dialog.view.text("sunlightHint")
	sunlight.button_pressed = dialog.view.preferences.values.sunlight
	sunlight.toggled.connect(func(value: bool) -> void: dialog.call("_change", "sunlight", value))
	dialog.get("layout").add_child(sunlight)
	var shadows := CheckButton.new()
	shadows.name = "Shadows"
	shadows.text = dialog.view.text("shadows")
	shadows.button_pressed = dialog.view.preferences.values.shadows
	dialog.get("layout").add_child(shadows)
	_shadow_quality()
	var quality := dialog.get("layout").find_child("ShadowQuality", true, false) as HSlider
	var quality_name := dialog.get("layout").find_child("ShadowQualityName", true, false) as Label
	_set_shadow_quality_enabled(quality, quality_name, shadows.button_pressed)
	shadows.toggled.connect(func(value: bool) -> void:
		_set_shadow_quality_enabled(quality, quality_name, value)
		dialog.call("_change", "shadows", value))
	var mesh_lod := CheckButton.new()
	mesh_lod.name = "MeshLod"
	mesh_lod.text = dialog.view.text("meshLod")
	mesh_lod.button_pressed = dialog.view.preferences.values.mesh_lod
	mesh_lod.toggled.connect(func(value: bool) -> void: dialog.call("_change", "mesh_lod", value))
	dialog.get("layout").add_child(mesh_lod)
	var keep_corpses := CheckButton.new()
	keep_corpses.name = "KeepCorpses"
	keep_corpses.text = dialog.view.text("keepCorpses")
	keep_corpses.button_pressed = dialog.view.preferences.values.keep_corpses
	keep_corpses.toggled.connect(func(value: bool) -> void: dialog.call("_change", "keep_corpses", value))
	dialog.get("layout").add_child(keep_corpses)
	var particles := CheckButton.new()
	particles.name = "ElectronicParticles"
	particles.text = dialog.view.text("electronicParticles")
	particles.button_pressed = dialog.view.preferences.values.electronic_particles
	particles.toggled.connect(func(value: bool) -> void: dialog.call("_change", "electronic_particles", value))
	dialog.get("layout").add_child(particles)
	var smoke := CheckButton.new()
	smoke.name = "BulletImpactSmoke"
	smoke.text = dialog.view.text("bulletImpactSmoke")
	smoke.tooltip_text = dialog.view.text("bulletImpactSmokeHint")
	smoke.button_pressed = dialog.view.preferences.values.bullet_impact_smoke
	smoke.toggled.connect(func(value: bool) -> void: dialog.call("_change", "bullet_impact_smoke", value))
	dialog.get("layout").add_child(smoke)


func _shadow_quality() -> void:
	var name_label := Label.new()
	name_label.name = "ShadowQualityName"
	name_label.custom_minimum_size.x = 90
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var slider := HSlider.new()
	slider.name = "ShadowQuality"
	slider.custom_minimum_size.x = 160
	slider.min_value = 0
	slider.max_value = SHADOWS.level_count() - 1
	slider.step = 1
	slider.tick_count = SHADOWS.level_count()
	slider.value = dialog.view.preferences.values.shadow_quality
	name_label.text = dialog.view.text("shadowQuality" + str(int(slider.value)))
	# Applying rewrites the settings file, rebuilds the menu and resizes the shadow atlas,
	# so it waits until the slider has stopped moving.
	var settle := Timer.new()
	settle.one_shot = true
	settle.wait_time = SETTLE_SECONDS
	slider.add_child(settle)
	settle.timeout.connect(func() -> void: dialog.call("_change", "shadow_quality", int(slider.value)))
	slider.value_changed.connect(func(value: float) -> void:
		name_label.text = dialog.view.text("shadowQuality" + str(int(value)))
		dialog.view.preferences.values.shadow_quality = int(value)
		settle.start())
	var box := HBoxContainer.new()
	box.add_child(slider)
	box.add_child(name_label)
	dialog.call("_row", "shadowQuality", box)


## Quality only applies while shadows are on: the whole row is dimmed and locked.
func _set_shadow_quality_enabled(slider: HSlider, name_label: Label, enabled: bool) -> void:
	slider.editable = enabled
	slider.modulate.a = 1.0 if enabled else .4
	name_label.modulate.a = 1.0 if enabled else .4


func _audio() -> void:
	dialog.call("_slider", "volume", "volume", 0, 1, .05)
	dialog.call("_slider", "effectsVolume", "effects_volume", 0, 1, .05)
	dialog.call("_slider", "musicVolume", "music_volume", 0, 1, .05)
	dialog.call("_slider", "menuMusicVolume", "menu_music_volume", 0, 1, .05)
	var music := CheckButton.new()
	music.name = "MenuMusicToggle"
	music.text = dialog.view.text("menuMusic")
	music.button_pressed = dialog.view.preferences.values.menu_music
	music.toggled.connect(func(value: bool) -> void: dialog.call("_change", "menu_music", value))
	dialog.get("layout").add_child(music)
	var sound := CheckButton.new()
	sound.name = "SoundToggle"
	sound.text = dialog.view.text("sound")
	sound.button_pressed = dialog.view.preferences.values.sound
	sound.toggled.connect(func(value: bool) -> void: dialog.call("_change", "sound", value))
	sound.mouse_entered.connect(dialog.view.play_hover.bind(sound))
	dialog.get("layout").add_child(sound)
