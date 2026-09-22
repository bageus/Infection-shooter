extends CanvasLayer

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


func _ready() -> void:
	player = get_node(player_path)
	infection = player.get_node("InfectionRuntime")
	hp_bar.max_value = player.max_health
	mutation_bar.max_value = 100.0
	_configure_icon_regions()


func _process(delta: float) -> void:
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
	var size := texture.get_size()
	# Atlas order in icon_interface.png: rifle, pistol, uzi, shotgun, syringe.
	var cell_width := size.x / 5.0
	var regions: Array[Rect2] = []
	for i in 5:
		regions.append(Rect2(cell_width * i, 0.0, cell_width, size.y))
	_set_region(slot_icons[0], texture, regions[1])
	_set_region(slot_icons[1], texture, regions[2])
	_set_region(slot_icons[2], texture, regions[3])
	_set_region(antidote_icon, texture, regions[4])


func _set_region(target: TextureRect, source: Texture2D, region: Rect2) -> void:
	var atlas := AtlasTexture.new()
	atlas.atlas = source
	atlas.region = region
	target.texture = atlas


func _set_active_weapon_icon(index: int) -> void:
	if index < 0 or index >= slot_icons.size():
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
	antidote_count.text = str(player.antidotes)


func _update_weapon() -> void:
	var weapon: Node = player.get_current_weapon()
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
	var normal_color := Color(0.82, 0.93, 1.0, 1.0)
	weapon_name.modulate = warning_color if empty else Color.WHITE
	magazine.modulate = warning_color if empty else Color.WHITE
	reload_label.modulate = warning_color if empty else Color(0.1, 0.9, 1.0, 1.0)
	weapon_icon.modulate = warning_color if empty else normal_color


func _update_weapon_slots(empty: bool) -> void:
	var active_index: int = player.get_current_weapon_index()
	var warning_color := Color(1.0, 0.12, 0.08, 1.0)
	for i in slot_frames.size():
		if i == active_index:
			slot_frames[i].modulate = warning_color if empty else Color(0.05, 1.0, 1.0, 1.0)
		else:
			slot_frames[i].modulate = Color(0.5, 0.66, 0.78, 0.9)
