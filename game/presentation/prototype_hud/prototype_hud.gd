extends CanvasLayer

const ICON_REGIONS := preload("res://game/presentation/prototype_hud/weapon_icon_regions.gd")
const PALETTE := preload("res://game/presentation/prototype_hud/hud_palette.gd")
const ICON_TINT := preload("res://game/presentation/prototype_hud/icon_tint.gdshader")
const TITLE_FONT := preload("res://assets/interface/fonts/title.ttf")
# Semantic cells: rifle, pistol, uzi, shotgun, syringe, launcher, key.
@export var weapon_icon_cells := PackedInt32Array([1, 2, 3, 5])
@export var antidote_icon_cell := 4
@export var key_icon_cell := 6

@export var player_path: NodePath

@onready var hp_bar: ProgressBar = $HealthPanel/HealthBar
@onready var hp_value: Label = $HealthPanel/HealthValue
@onready var mutation_bar: ProgressBar = $HealthPanel/MutationBar
@onready var mutation_value: Label = $HealthPanel/MutationValue
@onready var critical_marker: ColorRect = $HealthPanel/CriticalMarker
@onready var antidote_count: Label = $AntidotePanel/AntidoteCount
@onready var weapon_name: Label = $WeaponPanel/WeaponName
@onready var magazine: Label = $WeaponPanel/Magazine
@onready var reserve: Label = $WeaponPanel/Reserve
@onready var reload_label: Label = $WeaponPanel/Reload
@onready var weapon_icon: TextureRect = $WeaponPanel/WeaponIcon
@onready var antidote_icon: TextureRect = $AntidotePanel/Symbol
@onready var slot_icons: Array[TextureRect] = [$WeaponPanel/Slot1/Icon, $WeaponPanel/Slot2/Icon, $WeaponPanel/Slot3/Icon]
@onready var fps_label: Label = $FPS
@onready var enemy_count_label: Label = $EnemyCount
@onready var slot_keys: Array[Button] = [$WeaponPanel/Slot1/KeyHint, $WeaponPanel/Slot2/KeyHint, $WeaponPanel/Slot3/KeyHint]
@onready var antidote_key: Button = $AntidotePanel/KeyHint
@onready var key_panel: Panel = $KeyPanel
@onready var key_icon: TextureRect = $KeyPanel/KeyIcon
@onready var slot_frames: Array[Panel] = [$WeaponPanel/Slot1, $WeaponPanel/Slot2, $WeaponPanel/Slot3]

var player: Node
var infection: Node
var _perf_timer := 0.0
var _antidote_hint_remaining := 0.0
var _key_outline: StyleBoxFlat
var _key_filled: StyleBoxFlat
var _control_notice: Label
var _last_weapon_index := -1
var _weapon_icons: Array[Texture2D] = []
var _slot_weapon_indices := [-1, -1, -1]
var _vital_snapshot: Array = []
var _hp_flash: Tween
var _weapon_snapshot: Array = []

var _has_key := false


func _ready() -> void:
	player = get_node(player_path)
	infection = player.get_node("InfectionRuntime")
	hp_bar.max_value = player.max_health
	mutation_bar.max_value = 100.0
	_configure_icon_tints()
	_configure_icon_regions()
	_configure_key_buttons()
	weapon_name.hide()
	weapon_name.text = ""
	_control_notice = Label.new()
	_control_notice.text = "CONTROL LOST — MUTATION TAKES OVER"
	_control_notice.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_control_notice.position.y = 55.0
	_control_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_control_notice.add_theme_font_override("font", TITLE_FONT)
	_control_notice.add_theme_font_size_override("font_size", 24)
	_control_notice.add_theme_color_override("font_color", PALETTE.WARNING)
	_control_notice.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_control_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_control_notice)


func _process(delta: float) -> void:
	_control_notice.visible = bool(infection.call("is_control_lost"))
	_update_vitals()
	_update_weapon()
	_antidote_hint_remaining = maxf(0.0, _antidote_hint_remaining - delta)
	_update_key_buttons()
	_perf_timer += delta
	if _perf_timer >= 0.25:
		_perf_timer = 0.0
		fps_label.text = "FPS %d" % Engine.get_frames_per_second()
		enemy_count_label.text = "ENEMIES %d" % get_tree().get_nodes_in_group("infected_alive").size()


func _configure_icon_regions() -> void:
	var texture := weapon_icon.texture
	if texture == null:
		return
	var icons := ICON_REGIONS.extract(texture)
	_weapon_icons.clear()
	for cell in weapon_icon_cells:
		_weapon_icons.append(icons[cell] if cell >= 0 and cell < icons.size() else null)
	if _weapon_icons.size() < 4 or _weapon_icons[3] == null:
		push_warning("Weapon atlas: launcher cell unavailable; check weapon_icon_cells reading order.")
	_weapon_icons.append_array([preload("res://assets/interface/icon/weapon_ak.png"), preload("res://assets/interface/icon/weapon_m4.png"), preload("res://assets/interface/icon/weapon_sniper.png"), preload("res://assets/interface/icon/weapon_minigun.png")])
	_refresh_slot_icons()
	if antidote_icon_cell >= 0 and antidote_icon_cell < icons.size():
		antidote_icon.texture = icons[antidote_icon_cell]
	if key_icon_cell >= 0 and key_icon_cell < icons.size():
		key_icon.texture = icons[key_icon_cell]


func _configure_icon_tints() -> void:
	for rect: TextureRect in [weapon_icon, antidote_icon, key_icon] + slot_icons:
		var material := ShaderMaterial.new()
		material.shader = ICON_TINT
		material.set_shader_parameter("tint", PALETTE.INK)
		rect.material = material
	_tint(key_icon, PALETTE.KEY_GOLD)


func _tint(rect: TextureRect, color: Color) -> void:
	(rect.material as ShaderMaterial).set_shader_parameter("tint", color)


func _refresh_slot_icons() -> void:
	for i in slot_icons.size():
		var weapon_index: int = player.get_weapon_in_slot(i)
		if _slot_weapon_indices[i] == weapon_index:
			continue
		_slot_weapon_indices[i] = weapon_index
		slot_icons[i].texture = _weapon_icons[weapon_index] if weapon_index >= 0 and weapon_index < _weapon_icons.size() else null
		slot_keys[i].text = str(i + 1)


func _set_active_weapon_icon(index: int) -> void:
	if index < 0 or index >= slot_icons.size():
		weapon_icon.texture = null
		return
	weapon_icon.texture = slot_icons[index].texture


func _update_vitals() -> void:
	var mutation: float = infection.call("get_mutation")
	var critical: float = infection.call("get_critical_threshold")
	var has_key: bool = player.has_emergency_key()
	var snapshot: Array = [player.health, player.max_health, mutation, critical, player.antidotes, player.infinite_antidotes, has_key]
	if snapshot == _vital_snapshot:
		return
	var previous_health: float = float(_vital_snapshot[0]) if not _vital_snapshot.is_empty() else float(player.health)
	_vital_snapshot = snapshot
	if player.health - previous_health >= 3.0:
		_flash_health_bar()
	hp_bar.max_value = player.max_health
	hp_bar.value = player.health
	hp_value.text = "%d / %d" % [roundi(player.health), roundi(player.max_health)]
	mutation_bar.value = mutation
	mutation_value.text = "%d / 100" % roundi(mutation)
	critical_marker.position.x = mutation_bar.position.x - 1.0 + mutation_bar.size.x * clampf(critical / 100.0, 0.0, 1.0)
	antidote_count.text = "∞" if player.infinite_antidotes else str(player.antidotes)
	_update_key_cell(has_key)


# A green pulse on the health bar marks a noticeable heal (medkit, kill heal).
func _flash_health_bar() -> void:
	if not is_inside_tree():
		return
	if _hp_flash != null:
		_hp_flash.kill()
	hp_bar.modulate = Color(0.75, 1.9, 0.9)
	_hp_flash = create_tween()
	_hp_flash.tween_property(hp_bar, "modulate", Color.WHITE, 0.6).set_ease(Tween.EASE_IN)


func _update_key_cell(has_key: bool) -> void:
	if has_key == _has_key:
		return
	_has_key = has_key
	key_panel.visible = has_key
	if has_key and is_inside_tree():
		# Brief flash so the newly filled cell is noticed in combat.
		key_panel.modulate = Color(1.8, 1.6, 1.1)
		create_tween().tween_property(key_panel, "modulate", Color.WHITE, 0.9)


func _update_weapon() -> void:
	var weapon: Node = player.get_current_weapon()
	_refresh_slot_icons()
	var magazine_ammo: int = weapon.call("get_magazine_ammo")
	var reserve_ammo: int = weapon.call("get_reserve_ammo")
	var reloading: bool = weapon.call("is_reloading")
	var empty := magazine_ammo == 0
	var active: int = player.get_current_weapon_index()
	var snapshot: Array = [weapon, active, magazine_ammo, reserve_ammo, reloading, _slot_weapon_indices.duplicate()]
	if snapshot == _weapon_snapshot:
		return
	_weapon_snapshot = snapshot
	_set_active_weapon_icon(active)
	weapon_icon.tooltip_text = weapon.call("get_weapon_name").to_upper()

	magazine.text = str(magazine_ammo)
	reserve.text = "TOTAL" if bool(weapon.get("direct_reserve_feed")) else "/ %d" % reserve_ammo
	_update_reload_message(reloading, empty, reserve_ammo)
	_update_weapon_warning(empty)
	_update_weapon_slots(empty)


func _update_reload_message(reloading: bool, empty: bool, reserve_ammo: int) -> void:
	if reloading:
		reload_label.text = "RELOADING"
	elif empty and reserve_ammo > 0:
		reload_label.text = "RELOAD [R]"
	elif empty:
		reload_label.text = "NO AMMO"
	else:
		reload_label.text = ""


func _update_weapon_warning(empty: bool) -> void:
	var ink := PALETTE.WARNING if empty else PALETTE.INK
	weapon_name.add_theme_color_override("font_color", ink)
	magazine.add_theme_color_override("font_color", ink)
	reload_label.add_theme_color_override("font_color", PALETTE.WARNING if empty else PALETTE.MUTED)


var _slot_state := Vector2i(-99, -1)
var _key_states: Dictionary = {}


func _update_weapon_slots(empty: bool) -> void:
	var active_index: int = player.get_current_weapon_index()
	# Styles are rebuilt only when the active slot or empty state changes.
	var state := Vector2i(active_index, int(empty))
	if state == _slot_state:
		return
	_slot_state = state
	_tint(weapon_icon, PALETTE.WARNING if empty else PALETTE.INK)
	for i in slot_frames.size():
		var frame := slot_frames[i]
		var style := frame.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
		var active := i == active_index
		# Active slot: lighter cell with the menus' red focus underline.
		style.set_border_width_all(1)
		style.border_width_bottom = 2 if active else 1
		style.border_color = (PALETTE.WARNING if empty else PALETTE.ACCENT) if active else PALETTE.BORDER_DIM
		style.bg_color = PALETTE.CELL_ACTIVE if active else PALETTE.CELL
		frame.add_theme_stylebox_override("panel", style)
		_tint(slot_icons[i], PALETTE.INK if active else PALETTE.FAINT)
	_last_weapon_index = active_index


func _configure_key_buttons() -> void:
	_key_outline = StyleBoxFlat.new()
	_key_outline.bg_color = Color.TRANSPARENT
	_key_outline.border_color = PALETTE.FAINT
	_key_outline.set_border_width_all(1)
	_key_outline.set_content_margin_all(0)
	_key_filled = _key_outline.duplicate() as StyleBoxFlat
	_key_filled.bg_color = PALETTE.ACCENT
	_key_filled.border_color = PALETTE.ACCENT
	for index in slot_keys.size():
		slot_keys[index].pressed.connect(_on_weapon_key_pressed.bind(index))
		slot_keys[index].focus_mode = Control.FOCUS_NONE
	antidote_key.pressed.connect(_on_antidote_key_pressed)
	antidote_key.focus_mode = Control.FOCUS_NONE
	_update_key_buttons()


func _on_weapon_key_pressed(index: int) -> void:
	if player.call("select_weapon_slot", index):
		_update_weapon()
	_update_key_buttons()


func _on_antidote_key_pressed() -> void:
	if player.call("use_antidote"):
		_antidote_hint_remaining = 0.18
		_update_vitals()
	_update_key_buttons()


func _update_key_buttons() -> void:
	var blocked := bool(infection.call("is_control_lost")) or bool(infection.call("is_defeated"))
	var active: int = player.get_current_weapon_index()
	for index in slot_keys.size():
		_set_key_state(slot_keys[index], index == active, blocked)
	var using_antidote := _antidote_hint_remaining > 0.0 or Input.is_action_pressed("antidote") or antidote_key.is_pressed()
	_set_key_state(antidote_key, using_antidote, blocked or (player.antidotes <= 0 and not player.infinite_antidotes))


func _set_key_state(button: Button, selected: bool, blocked: bool) -> void:
	var key_state := int(selected) + 2 * int(blocked)
	if int(_key_states.get(button.get_instance_id(), -1)) == key_state:
		return
	_key_states[button.get_instance_id()] = key_state
	button.disabled = blocked
	var style := _key_filled if selected else _key_outline
	var ink := PALETTE.INK if selected else PALETTE.MUTED
	for state in ["normal", "hover", "disabled"]:
		button.add_theme_stylebox_override(state, style)
	button.add_theme_stylebox_override("pressed", _key_filled)
	for state in ["font_color", "font_hover_color", "font_disabled_color"]:
		button.add_theme_color_override(state, ink)
	button.add_theme_color_override("font_pressed_color", PALETTE.INK)
