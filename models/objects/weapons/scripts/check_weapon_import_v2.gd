extends SceneTree

func _initialize():
	var folder = "/workspace/scratch/ce18408cc06f/output/infection_weapon_pack_v2/models"
	var results = []
	var failed = false
	for file in DirAccess.get_files_at(folder):
		if not file.ends_with(".glb"):
			continue
		var document = GLTFDocument.new()
		var state = GLTFState.new()
		var error = document.append_from_file(folder.path_join(file), state)
		var scene = document.generate_scene(state) if error == OK else null
		var texture_count = 0
		for material in state.get_materials():
			if material is BaseMaterial3D and material.albedo_texture != null and material.normal_texture != null and material.roughness_texture != null:
				texture_count += 1
		var passed = error == OK and scene != null and texture_count == state.get_materials().size()
		results.append({"file": file, "import_error": error, "scene_generated": passed, "pbr_materials_with_all_maps": texture_count, "meshes": state.get_meshes().size(), "materials": state.get_materials().size()})
		print(file, " ", "PASS" if passed else "FAIL")
		if scene:
			scene.free()
		failed = failed or not passed
	var report = FileAccess.open(folder.get_base_dir().path_join("godot_import_validation.json"), FileAccess.WRITE)
	report.store_string(JSON.stringify({"godot_version": Engine.get_version_info(), "models": results}, "  "))
	quit(1 if failed else 0)
