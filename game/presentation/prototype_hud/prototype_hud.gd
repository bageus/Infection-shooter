extends CanvasLayer

const ICON_REGIONS := preload("res://game/presentation/prototype_hud/weapon_icon_regions.gd")
# Reading order of the updated atlas: rifle, pistol, uzi, shotgun, syringe, launcher.
@export var weapon_icon_cells := PackedInt32Array([1, 2, 3, 5])
@export var antidote_icon_cell := 4

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
@onready var slot_frames: Array[PanelContainer] = [$WeaponPanel/Slot1, $WeaponPanel/Slot2, $WeaponPanel/Slot3]

var player: Node
var infection: Node
var _perf_timer := 0.0
var _control_notice: Label
var _last_weapon_index := -1
var _weapon_icons: Array[Texture2D] = []
var _slot_weapon_indices := [-1, -1, -1]


func _ready() -> void:
	player = get_node(player_path)
	infection = player.get_node("InfectionRuntime")
	hp_bar.max_value = player.max_health
	mutation_bar.max_value = 100.0
	_configure_icon_regions()
	_control_notice = Label.new()
	_control_notice.text = "CONTROL LOST — MUTATION TAKES OVER"
	_control_notice.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_control_notice.position.y = 55.0
	_control_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_control_notice.add_theme_font_size_override("font_size", 22)
	_control_notice.add_theme_color_override("font_color", Color(1.0, 0.3, 0.2))
	_control_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_control_notice)


func _process(delta: float) -> void:
	_control_notice.visible = bool(infection.call("is_control_lost"))
	_update_vitals()
	_update_weapon()
	_perf_timer += delta
	if _perf_timer >= 0.25:
		_perf_timer = 0.0
		fps_label.text = "FPS %d" % Engine.get_frames_per_second()
		enemy_count_label.text = "ENEMIES %d" % get_tree().get_nodes_in_group("infected").size()


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
	_refresh_slot_icons()
	if antidote_icon_cell >= 0 and antidote_icon_cell < icons.size():
		antidote_icon.texture = icons[antidote_icon_cell]


func _refresh_slot_icons() -> void:
	for i in slot_icons.size():
		var weapon_index: int = player.get_weapon_in_slot(i)
		if _slot_weapon_indices[i] == weapon_index:
			continue
		_slot_weapon_indices[i] = weapon_index
		slot_icons[i].texture = _weapon_icons[weapon_index] if weapon_index >= 0 and weapon_index < _weapon_icons.size() else null
		(slot_frames[i].get_node("Label") as Label).text = "%d GL" % (i + 1) if weapon_index == 3 else str(i + 1)


func _set_region(target: TextureRect, source: Texture2D, region: Rect2) -> void:
	var atlas := AtlasTexture.new()
	atlas.atlas = source
	atlas.region = region
	target.texture = atlas


func _set_active_weapon_icon(index: int) -> void:
	if index < 0 or index >= slot_icons.size():
		weapon_icon.texture = null
		return
	weapon_icon.texture = slot_icons[index].texture


func _update_vitals() -> void:
	hp_bar.value = player.health
	hp_value.text = "%d / %d" % [roundi(player.health), roundi(player.max_health)]

	var mutation: float = infection.call("get_mutation")
	var critical: float = infection.call("get_critical_threshold")
	mutation_bar.value = mutation
	mutation_value.text = "%d / 100" % roundi(mutation)
	critical_marker.position.x = 78.0 + 264.0 * clampf(critical / 100.0, 0.0, 1.0)
	antidote_count.text = str(player.antidotes) + ("  KEY" if player.has_emergency_key() else "")


func _update_weapon() -> void:
	var weapon: Node = player.get_current_weapon()
	_refresh_slot_icons()
	_set_active_weapon_icon(player.get_current_weapon_index())
	weapon_name.text = weapon.call("get_weapon_name").to_upper()
	var magazine_ammo: int = weapon.call("get_magazine_ammo")
	var reserve_ammo: int = weapon.call("get_reserve_ammo")
	var reloading: bool = weapon.call("is_reloading")
	var empty := magazine_ammo == 0

	magazine.text = str(magazine_ammo)
	reserve.text = "/ %d" % reserve_ammo
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
	var warning_color := Color(1.0, 0.12, 0.08, 1.0)
	var normal_color := Color.WHITE
	weapon_name.modulate = warning_color if empty else Color.WHITE
	magazine.modulate = warning_color if empty else Color.WHITE
	reload_label.modulate = warning_color if empty else Color(0.1, 0.9, 1.0, 1.0)
	weapon_icon.modulate = warning_color if empty else normal_color


func _update_weapon_slots(empty: bool) -> void:
	var active_index: int = player.get_current_weapon_index()
	var warning_color := Color(1.0, 0.12, 0.08, 1.0)
	for i in slot_frames.size():
		var frame := slot_frames[i]
		var style := frame.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
		if i == active_index:
			style.border_width_left = 2
			style.border_width_top = 2
			style.border_width_right = 2
			style.border_width_bottom = 2
			style.border_color = warning_color if empty else Color(0.0, 0.95, 1.0, 1.0)
			style.bg_color = Color(0.0, 0.12, 0.17, 1.0)
			frame.modulate = Color.WHITE
		else:
			style.border_width_left = 1
			style.border_width_top = 1
			style.border_width_right = 1
			style.border_width_bottom = 1
			style.border_color = Color(0.12, 0.3, 0.42, 1.0)
			style.bg_color = Color(0.015, 0.055, 0.09, 0.98)
			frame.modulate = Color.WHITE
		frame.add_theme_stylebox_override("panel", style)
	_last_weapon_index = active_index
