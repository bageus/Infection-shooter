extends SceneTree
## Audit actual catalog wrappers, rather than only glTF group names.
const CATALOG := preload("res://game/bootstrap/app/planning_catalog.gd")
const STAGE_NAMES := ["Modular", "Door_Off", "LargeParts", "SmallFragments", "JaggedFragments", "PlantDestroyed", "PotFragments", "Broken_7", "Fragments", "Primary", "Panels", "Medium", "Fine", "TopSecondary", "DamageReady"]
const VARIANT_NAMES := ["Hit_01", "Dent_01", "Dent_02", "Dent_03", "Power_Off"]
var failures := 0
var rows: Array[Dictionary] = []
var stage: Node3D

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	var catalog := CATALOG.new()
	catalog._build_environment_catalogs()
	for entries: Array in catalog.group_catalogs.values():
		for entry: Dictionary in entries:
			await _audit(catalog, str(entry["path"]))
	var output := FileAccess.open("/tmp/destruction_wiring.json", FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify({"models": rows, "failures": failures}, "\t"))
	stage.queue_free()
	await process_frame
	print("Destruction wiring: %d catalog models, %d staged, %d failures" % [rows.size(), rows.filter(func(row: Dictionary) -> bool: return row["staged"]).size(), failures])
	quit(failures)

func _audit(catalog: RefCounted, path: String) -> void:
	var effects := Node3D.new()
	stage.add_child(effects)
	var prop: Node3D = catalog.call("_instantiate_asset", path)
	_check(prop != null, "Catalog instantiates: " + path)
	if prop == null:
		effects.free()
		return
	stage.add_child(prop)
	prop.position = Vector3(0, 10, 0)
	if prop.has_method("configure_world"):
		prop.call("configure_world", effects, null)
	var authored_stages: Array[String] = []
	for label: String in STAGE_NAMES + VARIANT_NAMES:
		if _find(prop, label) != null:
			authored_stages.append(label)
	if path.get_file() in ["07_reception_counter_two_heights.glb", "06_conference_chair.glb", "08_office_desk_2.glb", "08_divider_black_high.glb", "08_divider_black_high_half.glb", "08_divider_black_low.glb", "08_divider_black_low_half.glb", "05_monitor_destructible.glb", "05_monitor2_destructible.glb", "05_monitor3_server_destructible.glb", "05_monitor4_server_destructible.glb", "05_monitor_wide_destructible.glb", "05_laptop2_destructible.glb"]:
		_check("LargeParts" in authored_stages, "Flattened authored parts recovered: " + path)
	var staged := not authored_stages.is_empty()
	var row := {"path": path, "stages": authored_stages, "staged": staged, "checked": "no authored stage"}
	if staged:
		_check(prop.has_method("take_projectile_hit"), "Staged catalog model receives hits: " + path)
		if "_geometry" in prop and "_damage" in prop:
			var geometry: RefCounted = prop.get("_geometry")
			var groups: Array = geometry.get("stages")
			var variants: Array = geometry.get("variants")
			_check(groups.size() + variants.size() > 0, "Authored stages connected: " + path)
			for group: Node3D in groups + variants:
				_check(bool(geometry.call("ensure_group", group)), "Damage resource resolves: " + path + "/" + str(group.name))
				_check(not group.find_children("*", "MeshInstance3D", true, false).is_empty(), "Damage stage contains mesh: " + path + "/" + str(group.name))
				group.hide()
			if path.get_file() == "02_water_cooler_destructible.glb":
				await _audit_fixed_cooler(prop, effects)
				row["checked"] = "fixed whole cooler"
			elif not groups.is_empty():
				prop.call("take_projectile_hit", 10000.0, prop.global_position + Vector3(0, .5, 0), Vector3.BACK, Vector3.FORWARD, "AK")
				await process_frame
				# Variants absorb their own stage first; hit through all authored variants.
				for index in variants.size():
					if not is_instance_valid(prop):
						break
					prop.call("take_projectile_hit", 10000.0, prop.global_position, Vector3.BACK, Vector3.FORWARD, "AK")
					await process_frame
				_check(not is_instance_valid(prop) or bool(prop.get("_broken")), "Rifle damage breaks staged model: " + path)
				if is_instance_valid(prop):
					if "server_rack" in path or "DamageReady" in authored_stages:
						_check(groups[0].visible, "In-place damage geometry is visible: " + path)
					else:
						_check(effects.get_child_count() > 0, "Breakage emits authored fragments: " + path)
				row["checked"] = "rifle break"
			else:
				prop.call("take_projectile_hit", 10000.0, prop.global_position, Vector3.BACK, Vector3.FORWARD, "AK")
				await process_frame
				_check(int((prop.get("_damage") as RefCounted).get("variant_index")) >= 0, "Damage variant activates: " + path)
				row["checked"] = "damage variant"
		elif "_started" in prop:
			prop.call("take_projectile_hit", 10000.0, prop.global_position + Vector3(0, .8, 0), Vector3.BACK, Vector3.FORWARD, "AK")
			_check(bool(prop.get("_started")), "Table enters authored modular stage")
			prop.call("hit_piece", "Top", prop.global_position + Vector3(0, .8, 0), Vector3.FORWARD, 10000.0, "AK")
			await process_frame
			_check(not (prop.get("_active") as Dictionary).has("Top"), "Table top breaks into authored fragments")
			row["checked"] = "table modular/fragment transition"
		else:
			row["checked"] = "dedicated structural/fixture hit receiver"
	rows.append(row)
	if is_instance_valid(prop):
		prop.queue_free()
	effects.queue_free()
	await process_frame

func _audit_fixed_cooler(prop: Node3D, effects: Node3D) -> void:
	# This authored LargeParts stage is a whole body, not permission to shatter it.
	var body := prop as RigidBody3D
	_check(body != null, "Fixed cooler uses its physical catalog wrapper")
	if body == null:
		return
	var original := body.transform
	var layer := body.collision_layer
	for weapon in ["AK", "GRENADE"]:
		body.call("take_projectile_hit", 10000.0, body.global_position, Vector3.BACK, Vector3.FORWARD, weapon)
		await process_frame
		_check(not bool(body.get("_broken")), "Fixed cooler stays whole after " + weapon)
		_check(body.freeze and body.transform.is_equal_approx(original), "Fixed cooler stays anchored after " + weapon)
		_check(layer != 0 and body.collision_layer == layer, "Fixed cooler keeps its collision layer after " + weapon)
		var shapes: Array = body.get("_shapes")
		_check(not shapes.is_empty(), "Fixed cooler retains collision shapes after " + weapon)
		for shape: CollisionShape3D in shapes:
			_check(not shape.disabled, "Fixed cooler collision stays enabled after " + weapon)
		var intact := _find(body, "Intact")
		_check(intact != null and intact.is_visible_in_tree(), "Fixed cooler intact geometry stays visible after " + weapon)
		_check(effects.get_child_count() == 0, "Fixed cooler emits no replacement body fragments after " + weapon)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _find(node: Node, label: String) -> Node3D:
	if node is Node3D and str(node.name).split(".")[0].to_lower() == label.to_lower():
		return node as Node3D
	for child: Node in node.get_children():
		var match_node := _find(child, label)
		if match_node != null:
			return match_node
	return null
