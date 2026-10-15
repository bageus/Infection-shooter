extends SceneTree
## Looks for UV seams on enemy skins, where a baked blood mask would show a stripe.
## A seam edge joins two vertices that are close in the body but far apart in UV
## space, so its UV length per metre is much larger than the typical one.
##
##   godot --headless --path . --script res://tools/check_blood_mask_seams.gd
##
## Prints, per enemy scene: triangles, seam-like triangles and the worst ratio.

const SCENES := [
	"res://game/features/infected/public/infected_brute.tscn",
	"res://game/features/infected/public/infected_capsule.tscn",
	"res://game/features/infected/public/infected_colossus.tscn",
	"res://game/features/infected/public/infected_horde.tscn",
	"res://game/features/infected/public/infected_hunger.tscn",
	"res://game/features/infected/public/infected_revenant.tscn",
	"res://game/features/infected/public/infected_titan.tscn",
	"res://game/features/infected/public/mutant_level2.tscn",
]
# An edge counts as a seam when its UV length per metre is this many times the median.
const SEAM_FACTOR := 4.0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for path in SCENES:
		var body := (load(path) as PackedScene).instantiate() as Node3D
		root.add_child(body)
		await process_frame
		await process_frame
		var parts: Node = body.get("_parts")
		if parts == null or (parts.get("_entries") as Array).is_empty():
			print("%s: no body parts data" % path.get_file())
			body.queue_free()
			await process_frame
			continue
		var ratios := PackedFloat32Array()
		var triangles: Array = []
		for entry: Dictionary in parts.get("_entries"):
			for surface: Dictionary in entry.data.surfaces:
				_collect(surface, ratios, triangles)
		var median := _median(ratios)
		var seams := 0
		var jumps := 0
		var worst := 0.0
		for tri: Array in triangles:
			var worst_edge: float = maxf(tri[0], maxf(tri[1], tri[2]))
			var ratio: float = worst_edge / maxf(median, 0.0001)
			worst = maxf(worst, ratio)
			if ratio > SEAM_FACTOR:
				seams += 1
		for surface: Dictionary in _surfaces(parts):
			jumps += _jumps(surface)
		print("%s: %d triangles, %d stretched, %d UV jumps, median uv/m %.2f, worst ratio %.1fx" % [path.get_file(), triangles.size(), seams, jumps, median, worst])
		body.queue_free()
		await process_frame
	quit(0)


func _surfaces(parts: Node) -> Array:
	var out: Array = []
	for entry: Dictionary in parts.get("_entries"):
		out.append_array(entry.data.surfaces)
	return out


# Edges that are short on the body (under 10 cm) but jump more than 0.3 in UV.
# A real seam shows as this kind of jump; a stretched triangle does not.
func _jumps(surface: Dictionary) -> int:
	var vertices: PackedVector3Array = surface.vertices
	var uvs: PackedVector2Array = surface.uvs
	var indices: PackedInt32Array = surface.indices
	var count := 0
	if uvs.size() != vertices.size():
		return 0
	for tri in range(0, indices.size() - 2, 3):
		for k in 3:
			var a := indices[tri + k]
			var b := indices[tri + (k + 1) % 3]
			if vertices[a].distance_to(vertices[b]) < 0.1 and uvs[a].distance_to(uvs[b]) > 0.3:
				count += 1
	return count


# Stores each triangle as the three edge ratios (uv length per metre) and all edge ratios.
func _collect(surface: Dictionary, ratios: PackedFloat32Array, triangles: Array) -> void:
	var vertices: PackedVector3Array = surface.vertices
	var uvs: PackedVector2Array = surface.uvs
	var indices: PackedInt32Array = surface.indices
	if uvs.size() != vertices.size():
		return
	for tri in range(0, indices.size() - 2, 3):
		var edges := [[indices[tri], indices[tri + 1]], [indices[tri + 1], indices[tri + 2]], [indices[tri + 2], indices[tri]]]
		var edge_ratios := [0.0, 0.0, 0.0]
		var valid := true
		for k in 3:
			var a: int = edges[k][0]
			var b: int = edges[k][1]
			var metres := vertices[a].distance_to(vertices[b])
			if metres < 0.0005:
				valid = false
				break
			edge_ratios[k] = uvs[a].distance_to(uvs[b]) / metres
			ratios.append(edge_ratios[k])
		if valid:
			triangles.append(edge_ratios)


func _median(values: PackedFloat32Array) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[sorted.size() / 2]
