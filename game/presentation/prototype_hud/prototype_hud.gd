extends CanvasLayer

@export var player_path: NodePath

@onready var hp_bar: ProgressBar = $HealthPanel/HealthBar
@onready var hp_value: Label = $HealthPanel/HealthValue
@onready var mutation_bar: ProgressBar = $HealthPanel/MutationBar
@onready var mutation_value: Label = $HealthPanel/MutationValue
@onready var critical_marker: ColorRect = $HealthPanel/CriticalMarker
@onready var armor_segments: HBoxContainer = $HealthPanel/ArmorSegments
@onready var antidote_count: Label = $HealthPanel/AntidoteCount
@onready var weapon_name: Label = $WeaponPanel/WeaponName
@onready var magazine: Label = $WeaponPanel/Magazine
@onready var reserve: Label = $WeaponPanel/Reserve
@onready var reload_label: Label = $WeaponPanel/Reload
@onready var slots: Array[PanelContainer] = [$WeaponPanel/Slot1, $WeaponPanel/Slot2, $WeaponPanel/Slot3]

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
	critical_marker.position.x = 78.0 + 260.0 * clampf(critical / 100.0, 0.0, 1.0)

	var filled := ceili(player.armor / maxf(player.max_armor, 1.0) * armor_segments.get_child_count())
	for i in armor_segments.get_child_count():
		var segment := armor_segments.get_child(i) as ColorRect
		segment.color = Color(0.1, 0.85, 1.0, 1.0) if i < filled else Color(0.03, 0.12, 0.18, 0.8)

	antidote_count.text = str(player.antidotes)
	var weapon: Node = player.get_current_weapon()
	weapon_name.text = weapon.call("get_weapon_name")
	magazine.text = str(weapon.call("get_magazine_ammo"))
	reserve.text = "/ %d" % weapon.call("get_reserve_ammo")
	reload_label.text = "RELOADING" if weapon.call("is_reloading") else ""

	for i in slots.size():
		slots[i].modulate = Color(0.05, 1.0, 1.0, 1.0) if i == player.get_current_weapon_index() else Color(0.55, 0.7, 0.82, 0.8)
