extends "res://game/presentation/office_floor/environment_prop.gd"

const WATER := preload("res://game/presentation/office_floor/water_spray.gd")

var _fixture_broken := false


func _ready() -> void:
	super._ready()
	# Installed bathroom fixtures remain attached to the floor or wall until hit.
	freeze = true
	if "wall_urinal" in model_path.get_file() or "wall_hand_dryer" in model_path.get_file():
		set_meta("planning_wall_mount", true)


func take_projectile_hit(_hit_damage: float, hit_position: Vector3, _normal: Vector3, direction: Vector3, _weapon: String) -> bool:
	if _fixture_broken:
		return true
	_fixture_broken = true
	var outlet := _water_outlet(hit_position)
	var dryer := "hand_dryer" in model_path.get_file()
	if dryer:
		SPARKS.spawn(self, hit_position, true)
	call_deferred("_break_fixture", hit_position, direction, outlet, dryer)
	return true


func get_projectile_material(_shape_index: int = -1) -> String:
	return "tech" if "hand_dryer" in model_path.get_file() else "concrete"


func _water_outlet(fallback: Vector3) -> Vector3:
	var part_name := ""
	match model_path.get_file():
		"02_toilet_new.glb": part_name = "tank_main_body"
		"02_wall_urinal_improved.glb": part_name = "flush_button"
		"02_sink_pedestal_improved.glb": part_name = "spout_outlet"
		"16_toilet_floor.glb": part_name = "tank"
		"16_wall_urinal.glb": part_name = "flush"
		"16_sink_pedestal.glb": part_name = "faucet"
	for mesh in _shape_meshes:
		if is_instance_valid(mesh) and mesh.name.to_lower() == part_name:
			return (mesh.global_transform * mesh.get_aabb()).get_center()
	return fallback


func _break_fixture(hit_position: Vector3, direction: Vector3, outlet: Vector3, dryer: bool) -> void:
	if not is_inside_tree() or _visual == null:
		return
	var pieces: Array[MeshInstance3D] = _shape_meshes.duplicate()
	for collision in _shapes:
		collision.set_deferred("disabled", true)
	collision_layer = 0
	_visual.hide()
	for index in pieces.size():
		var part := pieces[index]
		if is_instance_valid(part):
			DAMAGE.spawn_piece(self, part, null, 0, index, direction, hit_position)
	if not dryer:
		WATER.spawn(self, outlet, "urinal" in model_path.get_file())
	# Keep the anchor until the water shuts off, independently of debris lifetime.
	get_tree().create_timer(11.0).timeout.connect(queue_free)
