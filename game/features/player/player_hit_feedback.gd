extends RefCounted
## Hit read on the player: the body recoils away from the blow and flashes white
## for a split second, or light blue when armor took the hit.

const FLASH_SECONDS := 0.18
const FLASH_ALPHA := 0.65
const WHITE := Color(1.0, 1.0, 1.0)
const ARMOR_BLUE := Color(0.45, 0.75, 1.0)

## World direction of the next blow; ZERO rocks the body straight back. Used once.
var direction := Vector3.ZERO
var _player: Node3D
var _material: StandardMaterial3D
var _tween: Tween


func configure(player: Node3D) -> void:
	_player = player
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA


func play(armored: bool) -> void:
	if _player == null or not _player.is_inside_tree():
		return
	var driver := _player.get_node_or_null("AnimationDriver")
	if driver != null:
		driver.call("notify_hit", _player.global_position + Vector3.UP, direction, 1.0)
	direction = Vector3.ZERO
	var body := _player.get_node_or_null("Body")
	if body == null:
		return
	var color := ARMOR_BLUE if armored else WHITE
	_material.albedo_color = Color(color, FLASH_ALPHA)
	if _tween != null and _tween.is_valid():
		_tween.kill()
	for mesh: Node in body.find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).material_overlay = _material
	_tween = _player.create_tween()
	_tween.tween_property(_material, "albedo_color:a", 0.0, FLASH_SECONDS)
	_tween.tween_callback(_clear.bind(body))


func _clear(body: Node) -> void:
	if is_instance_valid(body):
		for mesh: Node in body.find_children("*", "MeshInstance3D", true, false):
			(mesh as MeshInstance3D).material_overlay = null
