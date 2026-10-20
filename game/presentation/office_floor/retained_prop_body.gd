extends RefCounted
## Retain appliance bodies while their single authored attachment falls off.
const DAMAGE := preload("res://game/presentation/office_floor/environment_damage.gd")
const SOUND := preload("res://game/presentation/office_floor/prop_break_sound.gd")
const PARTS := {
	"02_water_cooler_destructible.glb": "",
	"02_water_cooler_bottle_attached_destructible.glb": "Bottle_01",
	"02_microwave_destructible.glb": "Door_01"
}
var enabled := false
var detached := false
var _part := ""


static func anchored(model_path: String) -> bool:
	var file := model_path.get_file()
	return file == "02_frige_dented.glb"


func configure(geometry: RefCounted, model_path: String) -> void:
	var file := model_path.get_file()
	enabled = PARTS.has(file)
	if not enabled:
		return
	_part = PARTS[file]
	if _part.is_empty() or geometry.intact == null or geometry.stages.is_empty():
		return
	var stage: Node3D = geometry.stages[0]
	if not geometry.ensure_group(stage):
		return
	var body := DAMAGE.find_named(stage, "Body_Whole") as MeshInstance3D
	var attachment := DAMAGE.find_named(stage, _part) as MeshInstance3D
	if body == null or attachment == null:
		push_error("Retained appliance requires Body_Whole and " + _part)
		return
	# The new GLBs bake Intact into one mesh. Restore two local meshes so a
	# bottle/door hit has its own collision and hiding it cannot hide the body.
	for child: Node in geometry.intact.get_children():
		child.free()
	for source: MeshInstance3D in [body, attachment]:
		geometry.intact.add_child(source.duplicate())
	stage.hide()


func protects() -> bool:
	return enabled and (_part.is_empty() or detached)


func hit_shape(host: RigidBody3D, geometry: RefCounted, index: int, amount: float, position: Vector3, direction: Vector3) -> bool:
	if not enabled or index < 0 or index >= geometry.meshes.size():
		return false
	if protects():
		return true
	var mesh: MeshInstance3D = geometry.meshes[index]
	if mesh.name != _part or amount <= 0.0:
		return false
	if detach(host, geometry, position, direction):
		host.get("_damage").shatter()
	return true


func detach(host: RigidBody3D, geometry: RefCounted, position: Vector3, direction: Vector3) -> bool:
	if not enabled:
		return false
	if protects():
		return true
	for i in geometry.meshes.size():
		var mesh: MeshInstance3D = geometry.meshes[i]
		if mesh.name != _part:
			continue
		host.get("_reaction").cancel()
		var fragment := DAMAGE.spawn_piece(host, mesh, host, geometry.stages.size(), 0, direction, position)
		if fragment == null:
			return true
		fragment.set("breakable", false)
		mesh.hide()
		geometry.shapes[i].set_deferred("disabled", true)
		detached = true
		SOUND.play(host, host.get("effects_root"), str(host.get("model_path")), "tech", position)
		return true
	return true
