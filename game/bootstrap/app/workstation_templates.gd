extends RefCounted

# Authored in game/bootstrap/app/workstations. Coordinates are metres in the desk's
# local space: the seated person looks towards positive Z.
const ROOT := "res://game/bootstrap/app/workstations/"
const MODEL_ROOT := "res://models/objects/enviroments/"
const DESKS := {
	"08_office_desk_2": "office_desk_2",
	"08_divider_full_H_desk": "divider_h",
	"08_divider_full_U_desk": "divider_u",
	"08_office_desk_4_coner": "corner_desk",
	"07_reception_counter_two_heights": "reception"
}
const SETUPS := ["laptop", "laptop_monitor", "desktop", "dual_laptop", "dual_desktop"]
const VARIANTS := {
	"laptop": ["05_laptop2_destructible", "05_laptop_destructible", "05_laptop_close_destructible"],
	"monitor": ["05_monitor2_destructible", "05_monitor_wide_destructible", "05_monitor_destructible"],
	"tower": ["05_PC_destructible", "05_minipc", "05_computer_tower_destructible"],
	"lamp": ["05_lamp", "05_circular_desklamp_alt"],
	"paper": ["09_notepad", "09_office_file_single", "09_office_files_a", "09_office_files_a_2", "09_office_files_d_custom", "09_office_files_e", "09_office_files_e_2", "09_office_files_f", "09_office_files_f_2", "09_office_files_f_3", "09_paper_stack", "09_paper_stray", "09_file_binder", "09_file_binder_alt_1", "09_file_binder_alt_2", "09_file_binder_alt_3", "09_file_binder_alt_4", "09_file_binder_alt_5"],
	"small": ["09_stapler", "09_pen_1", "09_pen_2", "09_pen_3", "09_pen_4", "09_pen_5", "09_pen_6", "09_pencil", "09_marker", "09_pencil_box", "09_pencil_holder", "09_mug", "09_mug_alt_1", "09_mug_alt_2", "09_mug_alt_3", "09_glass", "09_glass_2", "09_tablet", "09_camera", "09_book_big", "09_book_fat", "09_book_folder", "09_book_filearchive", "09_book_small", "11_plant_small"],
	"chair": ["06_office_chair", "06_office_chair_2", "06_office_chair_2_fell"],
	"bin": ["09_trash_bin", "09_trash_bin_small"]
}


static func desk_name(path: String) -> String:
	var stem := path.get_file().get_basename()
	return str(DESKS.get(stem, ""))


static func available_models() -> Array[String]:
	var result: Array[String] = []
	for group in ["03", "05", "06", "09", "11"]:
		var directory := DirAccess.open(MODEL_ROOT + group)
		if directory == null:
			continue
		for file in directory.get_files():
			if file.ends_with(".glb") and (group != "03" or file == "03_file_cabinet_smaller.glb"):
				result.append(file.get_basename())
	result.sort()
	return result


static func generate(desk: Node3D, path: String, parent: Node3D, existing: Array[Node3D], make_asset: Callable) -> Array[Node3D]:
	var created: Array[Node3D] = []
	var profile := _read("desks/" + desk_name(path) + ".json")
	if profile.is_empty():
		return created
	var seed_value := hash([path, desk.position.x, desk.position.z, desk.rotation.y])
	var random := RandomNumberGenerator.new()
	random.seed = absi(seed_value)
	var occupied: Array[Rect2] = []
	var stations: Array = profile.get("stations", [])
	for station_index in stations.size():
		var station: Dictionary = stations[station_index]
		var setup := _read("setups/" + SETUPS[random.randi_range(0, SETUPS.size() - 1)] + ".json")
		# Reserve the mandatory mouse and phone before computer and optional pieces.
		var items: Array = [
			{"model": "05_computer_mouse", "x": 0.73, "z": -0.21},
			{"model": "05_desk_phone", "x": -0.73, "z": -0.23}
		]
		items.append_array(setup.get("items", []))
		for entry_value in items:
			var entry: Dictionary = entry_value
			_add_item(entry, station, float(profile.get("height", 0.89)), desk, parent, existing, created, occupied, random, make_asset)
		# Uncrowded desks: at most two extra pieces per working surface.
		var options: Array = profile.get("optional", [])
		if not options.is_empty():
			var shuffled := options.duplicate()
			for i in range(shuffled.size() - 1, 0, -1):
				var j := random.randi_range(0, i)
				var option_value: Variant = shuffled[i]
				shuffled[i] = shuffled[j]
				shuffled[j] = option_value
			for option_index in mini(random.randi_range(0, 2), shuffled.size()):
				var option: Dictionary = shuffled[option_index]
				_add_item(option, station, float(profile.get("height", 0.89)), desk, parent, existing, created, occupied, random, make_asset)
		var chair: Dictionary = profile.get("chair", {})
		_add_item(chair, station, 0.0, desk, parent, existing, created, occupied, random, make_asset)
		if random.randf() < 0.85:
			var bin_slot: Dictionary = profile.get("bin", {})
			_add_item(bin_slot, station, 0.0, desk, parent, existing, created, occupied, random, make_asset)
	if profile.has("cabinet"):
		var cabinet: Dictionary = profile["cabinet"]
		if random.randf() < 0.5:
			cabinet = cabinet.duplicate()
			cabinet["x"] = -float(cabinet.get("x", 0.0))
		_add_item(cabinet, {"x": 0.0, "z": 0.0, "angle": 0.0}, 0.0, desk, parent, existing, created, occupied, random, make_asset)
	return created


static func _read(path: String) -> Dictionary:
	var file := FileAccess.open(ROOT + path, FileAccess.READ)
	if file == null:
		push_warning("Workstation template missing: " + path)
		return {}
	var data: Variant = JSON.parse_string(file.get_as_text())
	return data as Dictionary if data is Dictionary else {}


static func _model_path(model: String) -> String:
	if model.length() < 2 or not model.substr(0, 2).is_valid_int():
		return ""
	var path := MODEL_ROOT + model.substr(0, 2) + "/" + model + ".glb"
	return path if FileAccess.file_exists(path) else ""


static func _add_item(entry: Dictionary, station: Dictionary, height: float, desk: Node3D, parent: Node3D, existing: Array[Node3D], created: Array[Node3D], occupied: Array[Rect2], random: RandomNumberGenerator, make_asset: Callable) -> void:
	if entry.is_empty():
		return
	var model := str(entry.get("model", ""))
	if VARIANTS.has(model):
		var choices: Array = VARIANTS[model]
		model = str(choices[random.randi_range(0, choices.size() - 1)])
	var path := _model_path(model)
	if path.is_empty():
		return
	var node := make_asset.call(path) as Node3D
	if node == null:
		return
	parent.add_child(node)
	var angle := deg_to_rad(float(station.get("angle", 0.0)))
	var local := Vector3(float(entry.get("x", 0.0)), 0.0, float(entry.get("z", 0.0)))
	local = local.rotated(Vector3.UP, angle) + Vector3(float(station.get("x", 0.0)), 0.0, float(station.get("z", 0.0)))
	var jitter := float(entry.get("jitter", 0.025))
	local += Vector3(random.randf_range(-jitter, jitter), 0.0, random.randf_range(-jitter, jitter))
	var rotation_jitter := float(entry.get("rotation_jitter", 6.0))
	node.rotation.y = desk.rotation.y + angle + deg_to_rad(random.randf_range(-rotation_jitter, rotation_jitter))
	var surface_height := 0.0 if bool(entry.get("floor", false)) else height
	node.global_position = desk.to_global(local + Vector3.UP * surface_height)
	var bounds := _bounds(node)
	# Imported meshes may be centred around their pivot; align their bottom to the surface.
	if bounds.size.length_squared() < 0.000001 or bounds.size.x > 1.6 or bounds.size.z > 1.6:
		node.queue_free()
		return
	node.global_position.y += desk.to_global(Vector3.UP * surface_height).y - bounds.position.y
	bounds = _bounds(node)
	var rectangle := Rect2(Vector2(bounds.position.x, bounds.position.z), Vector2(bounds.size.x, bounds.size.z)).grow(0.025)
	# Desk legs are allowed under a worktop, but objects on the floor must not block a nearby chair.
	for other in occupied:
		if rectangle.intersects(other):
			node.queue_free()
			return
	for other in existing:
		if is_instance_valid(other) and other != desk and other.global_position.distance_to(node.global_position) < 2.0:
			var other_bounds := _bounds(other)
			if other_bounds.position.y < bounds.end.y and other_bounds.end.y > bounds.position.y:
				var other_rectangle := Rect2(Vector2(other_bounds.position.x, other_bounds.position.z), Vector2(other_bounds.size.x, other_bounds.size.z))
				if rectangle.intersects(other_rectangle):
					node.queue_free()
					return
	node.set_meta("planning_scene_path", path)
	created.append(node)
	occupied.append(rectangle)


static func _bounds(node: Node3D) -> AABB:
	var result := AABB()
	var found := false
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		if current is MeshInstance3D:
			var mesh := current as MeshInstance3D
			if mesh.mesh != null and mesh.is_visible_in_tree() and absf(mesh.global_basis.determinant()) > 0.000001:
				var box := mesh.global_transform * mesh.get_aabb()
				result = result.merge(box) if found else box
				found = true
		for child in current.get_children():
			stack.append(child)
	return result
