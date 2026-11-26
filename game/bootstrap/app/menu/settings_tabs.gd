extends RefCounted
const NOTICES := preload("res://game/bootstrap/app/menu/settings_notices.gd")
var notices := NOTICES.new()
const SHADOWS := preload("res://game/bootstrap/app/menu/shadow_quality.gd")
const DESTRUCTION_QUALITY := preload("res://game/core/vfx/public/destruction_quality.gd")
const BLOOD_LEVEL := preload("res://game/core/vfx/public/blood_level.gd")
const SETTLE_SECONDS := 0.35
const EDITOR := preload("res://game/bootstrap/app/menu/control_binding_editor.gd")
const STYLE := preload("res://game/bootstrap/app/menu/menu_style.gd")
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
	var web := OS.has_feature("web")
	if not web:
		_enemy_modes()
	_enemy_difficulty()
	if not web:
		_debug_rows()
	_comfort_rows()
	if not web:
		_tuning_sliders()


## Debug toggles; web builds show no rows for them and apply_web_rules fixes their values.
func _debug_rows() -> void:
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


func _comfort_rows() -> void:
	var floor_hints := CheckButton.new()
	floor_hints.name = "FloorHints"
	floor_hints.text = dialog.view.text("floorHints")
	floor_hints.tooltip_text = dialog.view.text("floorHintsHint")
	floor_hints.button_pressed = dialog.view.preferences.values.floor_hints
	floor_hints.toggled.connect(func(value: bool) -> void: dialog.call("_change", "floor_hints", value))
	dialog.get("layout").add_child(floor_hints)
	var health_bars := CheckButton.new()
	health_bars.name = "EnemyHealthBars"
	health_bars.text = dialog.view.text("enemyHealthBars")
	health_bars.tooltip_text = dialog.view.text("enemyHealthBarsHint")
	health_bars.button_pressed = dialog.view.preferences.values.enemy_health_bars
	health_bars.toggled.connect(func(value: bool) -> void: dialog.call("_change", "enemy_health_bars", value))
	for counter in [["show_fps", "showFps", "showFpsHint"], ["show_enemy_count", "showEnemyCount", "showEnemyCountHint"]]:
		var check := CheckButton.new()
		check.name = "Counter_" + counter[0]
		check.text = dialog.view.text(counter[1])
		check.tooltip_text = dialog.view.text(counter[2])
		check.button_pressed = dialog.view.preferences.values[counter[0]]
		check.toggled.connect(func(value: bool) -> void: dialog.call("_change", counter[0], value))
		dialog.get("layout").add_child(check)
	dialog.get("layout").add_child(health_bars)
	var shake := CheckButton.new()
	shake.name = "CameraShake"
	shake.text = dialog.view.text("cameraShake")
	shake.tooltip_text = dialog.view.text("cameraShakeHint")
	shake.button_pressed = dialog.view.preferences.values.camera_shake
	shake.toggled.connect(func(value: bool) -> void: dialog.call("_change", "camera_shake", value))
	dialog.get("layout").add_child(shake)
	var post_fx := CheckButton.new()
	post_fx.name = "PostFx"
	post_fx.text = dialog.view.text("postFx")
	post_fx.tooltip_text = dialog.view.text("postFxHint")
	post_fx.button_pressed = dialog.view.preferences.values.post_fx
	post_fx.toggled.connect(func(value: bool) -> void: dialog.call("_change", "post_fx", value))
	dialog.get("layout").add_child(post_fx)


func _tuning_sliders() -> void:
	dialog.call("_slider", "walkSpeed", "walk_speed_multiplier", 0.5, 1.5, 0.05, "%.2f×")
	dialog.call("_slider", "walkAnimationSpeed", "walk_animation_multiplier", 0.5, 2.0, 0.05, "%.2f×")
	dialog.call("_slider", "enemyMoveSpeed", "enemy_move_speed_multiplier", 0.5, 2.0, 0.05, "%.2f×")
	dialog.call("_slider", "enemyAnimationSpeed", "enemy_animation_multiplier", 0.5, 2.0, 0.05, "%.2f×")


func _enemy_modes() -> void:
	for entry in [["EnemiesIgnorePlayer", "enemiesIgnorePlayer", "enemies_ignore_player"], ["EnemiesNoDamage", "enemiesNoDamage", "enemies_no_damage"]]:
		var toggle := CheckButton.new()
		toggle.name = entry[0]
		toggle.text = dialog.view.text(entry[1])
		toggle.tooltip_text = dialog.view.text(entry[1] + "Hint")
		toggle.button_pressed = bool(dialog.view.preferences.values[entry[2]])
		toggle.toggled.connect(func(value: bool) -> void: dialog.call("_change", entry[2], value))
		dialog.get("layout").add_child(toggle)


## Three steps; the label names the step, and the file is written once on release like the walk sliders.
func _enemy_difficulty() -> void:
	var names := ["enemyDifficultyLow", "enemyDifficultyNormal", "enemyDifficultyHigh"]
	var slider := HSlider.new()
	slider.name = "EnemyDifficulty"
	slider.custom_minimum_size.x = 160
	slider.min_value = 0
	slider.max_value = 2
	slider.step = 1
	slider.value = dialog.view.preferences.values.enemy_difficulty
	slider.tooltip_text = dialog.view.text("enemyDifficultyHint")
	var value_label := STYLE.label(dialog.view.text(names[int(slider.value)]), 13)
	value_label.name = slider.name + "Value"
	value_label.custom_minimum_size.x = 92
	var box := HBoxContainer.new()
	box.add_child(slider)
	box.add_child(value_label)
	var dragging := [false]
	slider.drag_started.connect(func() -> void: dragging[0] = true)
	slider.drag_ended.connect(func(_changed: bool) -> void:
		dragging[0] = false
		dialog.call("_commit"))
	slider.value_changed.connect(func(value: float) -> void:
		value_label.text = dialog.view.text(names[int(value)])
		dialog.view.preferences.values.enemy_difficulty = int(value)
		dialog.view.preferences.apply_to_game(dialog.view.get_tree())
		if not dragging[0]:
			dialog.call("_commit"))
	dialog.call("_row", "enemyDifficulty", box)


func _video() -> void:
	var web := OS.has_feature("web")
	if not web:
		preload("res://game/bootstrap/app/menu/display_options.gd").build(dialog)
	dialog.call("_slider", "brightness", "brightness", .8, 1.4, .05)
	if not web:
		var occlusion := OptionButton.new()
		occlusion.name = "Occlusion"
		occlusion.add_item(dialog.view.text("occlusionSilhouettes"))
		occlusion.add_item(dialog.view.text("occlusionHole"))
		occlusion.selected = dialog.view.preferences.values.occlusion_mode
		occlusion.item_selected.connect(func(index: int) -> void: dialog.call("_change", "occlusion_mode", index))
		dialog.call("_row", "occlusion", occlusion)
	_blood_color()
	if not web:
		var blood_style := OptionButton.new()
		blood_style.name = "BloodStyle"
		blood_style.add_item(dialog.view.text("bloodStyleAssets"))
		blood_style.add_item(dialog.view.text("bloodStyleProcedural"))
		blood_style.selected = dialog.view.preferences.values.blood_style
		blood_style.item_selected.connect(func(index: int) -> void: dialog.call("_change", "blood_style", index))
		_lock_blood(blood_style)
		dialog.call("_row", "bloodStyle", blood_style)
		_blood_level()
	_destruction_quality()
	if not web:
		var effects_quality := OptionButton.new()
		effects_quality.name = "EffectsQuality"
		for key in ["effectsQuality0", "effectsQuality1", "effectsQuality2"]:
			effects_quality.add_item(dialog.view.text(key))
		effects_quality.selected = dialog.view.preferences.values.effects_quality
		effects_quality.tooltip_text = dialog.view.text("effectsQualityHint")
		effects_quality.item_selected.connect(func(index: int) -> void: dialog.call("_change", "effects_quality", index))
		dialog.call("_row", "effectsQuality", effects_quality)
	if not web:
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
		shadows.tooltip_text = dialog.view.text("shadowsHint")
		shadows.button_pressed = dialog.view.preferences.values.shadows
		dialog.get("layout").add_child(shadows)
		_shadow_quality()
		var quality := dialog.get("layout").find_child("ShadowQuality", true, false) as HSlider
		var quality_name := dialog.get("layout").find_child("ShadowQualityName", true, false) as Label
		_set_shadow_quality_enabled(quality, quality_name, shadows.button_pressed)
		shadows.toggled.connect(func(value: bool) -> void:
			_set_shadow_quality_enabled(quality, quality_name, value)
			dialog.call("_change", "shadows", value))
		_render_scale_row()
		_few_lamps_row()
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
	var smoke := CheckButton.new()
	smoke.name = "BulletImpactSmoke"
	smoke.text = dialog.view.text("bulletImpactSmoke")
	smoke.tooltip_text = dialog.view.text("bulletImpactSmokeHint")
	smoke.button_pressed = dialog.view.preferences.values.bullet_impact_smoke
	smoke.toggled.connect(func(value: bool) -> void: dialog.call("_change", "bullet_impact_smoke", value))
	dialog.get("layout").add_child(smoke)
	var hide_unseen := CheckButton.new()
	hide_unseen.name = "HideUnseenProps"
	hide_unseen.text = dialog.view.text("hideUnseenProps")
	hide_unseen.tooltip_text = dialog.view.text("hideUnseenPropsHint")
	hide_unseen.button_pressed = dialog.view.preferences.values.hide_unseen_props
	hide_unseen.toggled.connect(func(value: bool) -> void: dialog.call("_change", "hide_unseen_props", value))
	dialog.get("layout").add_child(hide_unseen)
	_dust_row()


func _render_scale_row() -> void:
	var percent := Label.new()
	percent.name = "RenderScalePercent"
	percent.custom_minimum_size.x = 60
	percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var slider := HSlider.new()
	slider.name = "RenderScale"
	slider.tooltip_text = dialog.view.text("renderScaleHint")
	slider.custom_minimum_size.x = 160
	slider.min_value = 50
	slider.max_value = 100
	slider.step = 5
	slider.tick_count = 11
	slider.value = dialog.view.preferences.values.render_scale
	percent.text = "%d%%" % int(slider.value)
	# Applying rewrites the settings file and rebuilds the menu, so it waits until the slider stops.
	var settle := Timer.new()
	settle.one_shot = true
	settle.wait_time = SETTLE_SECONDS
	slider.add_child(settle)
	settle.timeout.connect(func() -> void: dialog.call("_change", "render_scale", int(slider.value)))
	slider.value_changed.connect(func(value: float) -> void:
		percent.text = "%d%%" % int(value)
		dialog.view.preferences.values.render_scale = int(value)
		if settle.is_inside_tree(): settle.start())
	var box := HBoxContainer.new()
	box.add_child(slider)
	box.add_child(percent)
	dialog.call("_row", "renderScale", box)


func _few_lamps_row() -> void:
	var few_lamps := CheckButton.new()
	few_lamps.name = "FewLamps"
	few_lamps.text = dialog.view.text("fewLamps")
	few_lamps.tooltip_text = dialog.view.text("fewLampsHint")
	few_lamps.button_pressed = dialog.view.preferences.values.few_lamps
	few_lamps.toggled.connect(func(value: bool) -> void: dialog.call("_change", "few_lamps", value))
	dialog.get("layout").add_child(few_lamps)


func _dust_row() -> void:
	var dust := CheckButton.new()
	dust.name = "Dust"
	dust.text = dialog.view.text("dust")
	dust.tooltip_text = dialog.view.text("dustHint")
	dust.button_pressed = dialog.view.preferences.values.dust
	dust.toggled.connect(func(value: bool) -> void: dialog.call("_change", "dust", value))
	dialog.get("layout").add_child(dust)


func _shadow_quality() -> void:
	var name_label := Label.new()
	name_label.name = "ShadowQualityName"
	name_label.custom_minimum_size.x = 90
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var slider := HSlider.new()
	slider.name = "ShadowQuality"
	slider.tooltip_text = dialog.view.text("shadowQualityHint")
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
		if settle.is_inside_tree(): settle.start())
	var box := HBoxContainer.new()
	box.add_child(slider)
	box.add_child(name_label)
	dialog.call("_row", "shadowQuality", box)


## Quality only applies while shadows are on: the whole row is dimmed and locked.
func _set_shadow_quality_enabled(slider: HSlider, name_label: Label, enabled: bool) -> void:
	slider.editable = enabled
	slider.modulate.a = 1.0 if enabled else .4
	name_label.modulate.a = 1.0 if enabled else .4


## Blood amount 0..2 (low, medium, maximum). The colour is a separate switch. Like shadow quality, the
## change is applied once the slider stops moving.
func _blood_level() -> void:
	var name_label := Label.new()
	name_label.name = "BloodLevelName"
	name_label.custom_minimum_size.x = 90
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var slider := HSlider.new()
	slider.name = "BloodLevel"
	slider.custom_minimum_size.x = 160
	slider.min_value = 0
	slider.max_value = BLOOD_LEVEL.COUNT - 1
	slider.step = 1
	slider.tick_count = BLOOD_LEVEL.COUNT
	slider.value = dialog.view.preferences.values.blood_level
	slider.editable = not blood_locked()
	slider.modulate.a = 1.0 if slider.editable else .4
	if blood_locked():
		slider.tooltip_text = dialog.view.text("bloodLockedHint")
	name_label.text = dialog.view.text("bloodLevel" + str(int(slider.value)))
	var settle := Timer.new()
	settle.one_shot = true
	settle.wait_time = SETTLE_SECONDS
	slider.add_child(settle)
	settle.timeout.connect(func() -> void: dialog.call("_change", "blood_level", int(slider.value)))
	slider.value_changed.connect(func(value: float) -> void:
		name_label.text = dialog.view.text("bloodLevel" + str(int(value)))
		dialog.view.preferences.values.blood_level = int(value)
		if settle.is_inside_tree(): settle.start())
	var box := HBoxContainer.new()
	box.add_child(slider)
	box.add_child(name_label)
	dialog.call("_row", "bloodLevel", box)


## Destruction quality 0..2 (low, medium, high): how many floor decals a break leaves and how long
## its pieces stay loose. Like blood level, it applies once the slider stops moving.
func _destruction_quality() -> void:
	var name_label := Label.new()
	name_label.name = "DestructionQualityName"
	name_label.custom_minimum_size.x = 90
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var slider := HSlider.new()
	slider.name = "DestructionQuality"
	slider.custom_minimum_size.x = 160
	slider.min_value = 0
	slider.max_value = DESTRUCTION_QUALITY.COUNT - 1
	slider.step = 1
	slider.tick_count = DESTRUCTION_QUALITY.COUNT
	slider.value = dialog.view.preferences.values.destruction_quality
	slider.tooltip_text = dialog.view.text("destructionQualityHint")
	name_label.text = dialog.view.text("destructionQuality" + str(int(slider.value)))
	var settle := Timer.new()
	settle.one_shot = true
	settle.wait_time = SETTLE_SECONDS
	slider.add_child(settle)
	settle.timeout.connect(func() -> void: dialog.call("_change", "destruction_quality", int(slider.value)))
	slider.value_changed.connect(func(value: float) -> void:
		name_label.text = dialog.view.text("destructionQuality" + str(int(value)))
		dialog.view.preferences.values.destruction_quality = int(value)
		if settle.is_inside_tree(): settle.start())
	var box := HBoxContainer.new()
	box.add_child(slider)
	box.add_child(name_label)
	dialog.call("_row", "destructionQuality", box)


func _audio() -> void:
	dialog.call("_slider", "volume", "volume", 0, 1, .05)
	dialog.call("_slider", "effectsVolume", "effects_volume", 0, 1, .05)
	dialog.call("_slider", "musicVolume", "music_volume", 0, 1, .05)
	dialog.call("_slider", "menuMusicVolume", "menu_music_volume", 0, 1, .05)


## Blood colour: green or red, on every platform. It is a separate switch from the amount.
func _blood_color() -> void:
	var color := OptionButton.new()
	color.name = "BloodColor"
	color.add_item(dialog.view.text("bloodColorGreen"))
	color.add_item(dialog.view.text("bloodColorRed"))
	color.selected = 0 if dialog.view.preferences.values.blood_green else 1
	color.disabled = BLOOD_LEVEL.forced_green
	color.item_selected.connect(func(index: int) -> void: dialog.call("_change", "blood_green", index == 0))
	_lock_blood(color)
	dialog.call("_row", "bloodColor", color)


## Release builds keep the blood choice fixed while a game runs; it changes in the menu before a game
## starts. Debug builds can change it any time.
func blood_locked() -> bool:
	if OS.is_debug_build():
		return false
	var scene: Node = dialog.view.get_tree().current_scene
	return scene != null and scene.has_method("set_blood_level")


func _lock_blood(option: OptionButton) -> void:
	if blood_locked():
		option.disabled = true
		option.tooltip_text = dialog.view.text("bloodLockedHint")
