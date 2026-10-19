extends RefCounted
## Predator Dash strike lane: a strip on the floor from the player along the
## dash, as wide as the dash reach, with bright edges and a faint fill. It
## stays for the dash and fades after it. The strip follows the lowest surface
## under each row, so desks and props on the way do not lift it.

const FLOOR_ZONE := preload("res://game/features/combat/public/floor_danger_zone.gd")
const LENGTH := 6.0
const HALF_WIDTH := 1.6
const ROWS := 12
const LIFT := 0.03
const FADE := 0.3
## Across the lane: bright edge band, faint middle.
const COLUMNS := [[-1.0, 0.8], [-0.9, 0.2], [0.0, 0.1], [0.9, 0.2], [1.0, 0.8]]
const LANE_SHADER := preload("res://game/features/player/skill_fx/fx_strike_lane.gdshader")


static func spawn(parent: Node3D, world: World3D, origin: Vector3, direction: Vector3, seconds: float) -> MeshInstance3D:
	direction.y = 0.0
	if direction.length_squared() < 0.0001:
		return null
	direction = direction.normalized()
	var side := Vector3(-direction.z, 0.0, direction.x)
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	for row in ROWS + 1:
		var along := float(row) / ROWS
		var fade := 1.0 - along * along
		for column: Array in COLUMNS:
			var flat: Vector3 = origin + direction * LENGTH * along + side * HALF_WIDTH * float(column[0])
			vertices.append(FLOOR_ZONE.floor_point(world, flat) + Vector3.UP * LIFT)
			colors.append(Color(float(column[1]), fade, 0.0, 1.0))
			uvs.append(Vector2(float(column[0]), LENGTH * along))
	var indices := PackedInt32Array()
	var width := COLUMNS.size()
	for row in ROWS:
		for column in width - 1:
			var a := row * width + column
			indices.append_array([a, a + 1, a + width, a + 1, a + width + 1, a + width])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var zone := MeshInstance3D.new()
	zone.name = "DashFloorZone"
	zone.mesh = mesh
	zone.top_level = true
	zone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = LANE_SHADER
	zone.material_override = material
	parent.add_child(zone)
	var tween := zone.create_tween()
	tween.tween_interval(seconds)
	tween.tween_method(func(value: float) -> void: zone.set_instance_shader_parameter(&"alpha", value), 1.0, 0.0, FADE)
	tween.tween_callback(zone.queue_free)
	return zone
