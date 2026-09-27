extends Node3D

const ART := preload("res://game/features/combat/public/launcher_visual.gd")
const LABELS := ["пистолет", "автомат", "дробовик", "барабанный гранатомёт"]

@export_range(0, 3) var weapon_index := 3
var _base_position := Vector3.ZERO
var _time := 0.0
var _hint: Label3D


func _ready() -> void:
	add_to_group("weapon_pickups")
	_base_position = global_position
	var art := ART.make_visual(weapon_index == 3)
	add_child(art)
	art.scale = Vector3.ONE * 0.9
	art.position.y = 0.08 if weapon_index == 3 and ART.launcher_model() != null else 0.25
	_hint = Label3D.new()
	_hint.text = "[G] Подобрать: " + LABELS[weapon_index] + "\nАктивное оружие выпадет рядом"
	_hint.font_size = 44
	_hint.pixel_size = 0.006
	_hint.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hint.position = Vector3(0, 0.78, 0)
	_hint.visible = false
	add_child(_hint)


func _process(delta: float) -> void:
	_time += delta
	global_position.y = _base_position.y + sin(_time * 1.6) * 0.07
	rotation.y += delta * 0.55
	var player := get_tree().get_first_node_in_group("player") as Node3D
	_hint.visible = player != null and player.global_position.distance_to(global_position) <= 2.4


func claim(player: Node3D) -> bool:
	if player.global_position.distance_to(global_position) > 2.4 or not player.has_method("pickup_weapon"):
		return false
	if not bool(player.call("pickup_weapon", weapon_index)):
		return false
	queue_free()
	return true
