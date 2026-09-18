extends CanvasLayer

@export var player_path: NodePath

@onready var hp_bar: ProgressBar = $HealthPanel/HealthBar
@onready var hp_value: Label = $HealthPanel/HealthValue
@onready var mutation_bar: ProgressBar = $HealthPanel/MutationBar
@onready var mutation_value: Label = $HealthPanel/MutationValue
@onready var critical_marker: ColorRect = $HealthPanel/CriticalMarker
@onready var armor_segments: HBoxContainer = $HealthPanel/ArmorSegments
@onready var antidote_count: Label = $AntidotePanel/AntidoteCount
@onready var weapon_name: Label = $WeaponPanel/WeaponName
@onready var magazine: Label = $WeaponPanel/Magazine
@onready var reserve: Label = $WeaponPanel/Reserve
@onready var reload_label: Label = $WeaponPanel/Reload
@onready var gun_parts: Array[ColorRect] = [$WeaponPanel/GunStock, $WeaponPanel/GunBody, $WeaponPanel/GunBarrel, $WeaponPanel/GunGrip]
@onready var slot_frames: Array[PanelContainer] = [$WeaponPanel/Slot1, $WeaponPanel/Slot2, $WeaponPanel/Slot3]

var player: Node
var infection: Node


func _ready() -> void:
	player = get_node(player_path)
	infection = player.get_node("InfectionRuntime")
	hp_bar.max_value = player.max_health
	mutation_bar.max_value = 100.0


func _process(_delta: float) -> void:
	hp_bar.value = player.health
	hp_value.text = "%d / %d" % [roundi(player.health), roundi(player.max_health)]

	var mutation: float = infection.call("get_mutation")
	var critical: float = infection.call("get_critical_threshold")
	mutation_bar.value = mutation
	mutation_value.text = "%d / 100" % roundi(mutation)
	critical_marker.position.x = 80.0 + 260.0 * clampf(critical / 100.0, 0.0, 1.0)

	var filled := ceili(player.armor / maxf(player.max_armor, 1.0) * armor_segments.get_child_count())
	for i in armor_segments.get_child_count():
		var segment := armor_segments.get_child(i) as ColorRect
		segment.color = Color(0.08, 0.82, 1.0, 1.0) if i < filled else Color(0.025, 0.12, 0.18, 0.9)

	antidote_count.text = str(player.antidotes)
	var weapon: Node = player.get_current_weapon()
	weapon_name.text = weapon.call("get_weapon_name")
	var magazine_ammo: int = weapon.call("get_magazine_ammo")
	var reserve_ammo: int = weapon.call("get_reserve_ammo")
	var reloading: bool = weapon.call("is_reloading")
	var empty: bool = magazine_ammo == 0

	magazine.text = str(magazine_ammo)
	reserve.text = "/ %d" % reserve_ammo

	if reloading:
		reload_label.text = "RELOADING"
	elif empty and reserve_ammo > 0:
		reload_label.text = "RELOAD [R]"
	elif empty:
		reload_label.text = "NO AMMO"
	else:
		reload_label.text = ""

	var warning_color := Color(1.0, 0.12, 0.08, 1.0)
	var normal_weapon_color := Color(0.82, 0.93, 1.0, 1.0)
	weapon_name.modulate = warning_color if empty else Color.WHITE
	magazine.modulate = warning_color if empty else Color.WHITE
	reload_label.modulate = warning_color if empty and not reloading else Color(0.1, 0.9, 1.0, 1.0)
	for part in gun_parts:
		part.color = warning_color if empty else normal_weapon_color

	var active_index: int = player.get_current_weapon_index()
	for i in slot_frames.size():
		if i == active_index:
			slot_frames[i].modulate = warning_color if empty else Color(0.05, 1.0, 1.0, 1.0)
		else:
			slot_frames[i].modulate = Color(0.5, 0.66, 0.78, 0.9)
