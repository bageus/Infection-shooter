extends SceneTree
## Add generated LODs to existing enemy resources without rebuilding rigs or textures.
const DIRECTORY := "res://models/objects/characters/enemy/game/"
const NAMES := ["Hunger", "Revenant", "Brute", "Titan", "Colossus", "Horde"]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for enemy: String in NAMES:
		for suffix: String in ["_game.res", "_rig_mesh.res"]:
			var path := DIRECTORY + enemy + suffix
			var source := load(path) as ArrayMesh
			var importer := ImporterMesh.new()
			for surface in source.get_surface_count():
				importer.add_surface(source.surface_get_primitive_type(surface), source.surface_get_arrays(surface), [], {}, source.surface_get_material(surface), source.surface_get_name(surface), source.surface_get_format(surface))
			importer.generate_lods(25.0, 60.0, [])
			var generated := importer.get_mesh()
			# Keep original serialized vertex/skin streams; re-encoding normals can
			# introduce rounding. Only generated LOD buffers are transferred.
			var stored: Array = source.get("_surfaces")
			var generated_surfaces: Array = generated.get("_surfaces")
			for surface in source.get_surface_count():
				var original_arrays := source.surface_get_arrays(surface)
				var generated_arrays := generated.surface_get_arrays(surface)
				for slot in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_INDEX, Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS]:
					if original_arrays[slot] != generated_arrays[slot]:
						push_error("LOD generation changed vertex topology: " + path)
						quit(1)
						return
				stored[surface]["lods"] = generated_surfaces[surface].get("lods", [])
			var result := source.duplicate() as ArrayMesh
			result.set("_surfaces", stored)
			for surface in source.get_surface_count():
				if result.surface_get_arrays(surface) != source.surface_get_arrays(surface):
					push_error("LOD transfer changed base geometry: " + path)
					quit(1)
					return
			if ResourceSaver.save(result, path) != OK:
				push_error("Cannot save LODs: " + path)
				quit(1)
				return
			print("%s: %d LODs" % [path, importer.get_surface_lod_count(0)])
	quit()
