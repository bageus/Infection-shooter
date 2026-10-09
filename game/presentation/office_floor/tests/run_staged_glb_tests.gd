extends SceneTree
## Runtime checks for staged destructible GLBs (one glTF scene per damage
## stage, imported by addons/staged_glb_import): stage groups, full breakage
## into large parts and fragments, the plant pot and the reception facade.

const PROP_SCENE := preload("res://game/presentation/office_floor/public/props/environment_prop.tscn")
const MODELS := "res://models/objects/enviroments/"
const CABINET := MODELS + "03/03_file_cabinet_largest.glb"
const PLANT := MODELS + "11/11_plant_small.glb"
const RECEPTION := MODELS + "07/07_reception_counter_two_heights_2.glb"
const SERVER_RACK := MODELS + "03/03_server_rack3.glb"
const LAPTOP := MODELS + "05/05_laptop_destructible.glb"

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	_add_floor(stage)
	_test_stage_groups()
	await _test_cabinet(stage)
	await _test_plant(stage)
	await _test_reception(stage)
	await _test_power_off(stage)
	await _test_rack_textures(stage)
	stage.queue_free()
	await process_frame
	print("Staged GLB tests: %d failure(s)." % failures)
	quit(failures)


func _test_stage_groups() -> void:
	var model := (load(CABINET) as PackedScene).instantiate() as Node3D
	var intact := model.get_node_or_null("Intact") as Node3D
	var parts := model.get_node_or_null("LargeParts") as Node3D
	var fragments := model.get_node_or_null("SmallFragments") as Node3D
	_expect(int(model.get_meta(&"staged_glb_version", 0)) >= 1, "Multi-scene GLB is imported by the staged extension.")
	_expect(intact != null and intact.scale == Vector3.ONE, "The default Intact scene stays visible.")
	_expect(parts != null and parts.scale == Vector3.ZERO and parts.get_child_count() == 26, "LargeParts is imported hidden with all 26 parts.")
	_expect(fragments != null and fragments.scale == Vector3.ZERO and fragments.get_child_count() == 118, "SmallFragments is imported hidden with all 118 fragments.")
	model.free()


func _test_cabinet(stage: Node3D) -> void:
	var setup := await _spawn(stage, CABINET, Vector3(0, 0, 0))
	var prop: RigidBody3D = setup[0]
	var effects: Node3D = setup[1]
	await _break(prop)
	_expect(bool(prop.get("_broken")), "Staged cabinet breaks under heavy damage.")
	var part := _find_fragment(effects, "Fragment_Component_")
	_expect(part != null, "Breaking spawns the cabinet's large parts.")
	if part != null:
		var name_part := str(part.get("piece_name"))
		prop.call("hit_environment_fragment", part, part.global_position, Vector3.FORWARD)
		await process_frame
		_expect(_find_fragment(effects, "Fragment_" + name_part + "_Fragment_") != null, "A shot large part splits into its own small fragments.")
	await _clear(prop, effects)


func _test_plant(stage: Node3D) -> void:
	var setup := await _spawn(stage, PLANT, Vector3(6, 0, 0))
	var prop: RigidBody3D = setup[0]
	var effects: Node3D = setup[1]
	await _break(prop)
	var pot := _find_fragment(effects, "Fragment_Pot_Plant_Destroyed")
	_expect(pot != null, "A broken plant falls as its destroyed pot.")
	if pot != null:
		prop.call("hit_environment_fragment", pot, pot.global_position, Vector3.FORWARD)
		await process_frame
		_expect(_find_fragment(effects, "Fragment_Pot_Shard_") != null, "Shooting the fallen pot shatters it into shards.")
	await _clear(prop, effects)


func _test_reception(stage: Node3D) -> void:
	var setup := await _spawn(stage, RECEPTION, Vector3(-8, 0, 0))
	var prop: RigidBody3D = setup[0]
	var effects: Node3D = setup[1]
	await _break(prop)
	var facade := prop.get_node("Visual").get_node_or_null("DamageReady") as Node3D
	_expect(facade != null and facade.visible and facade.scale == Vector3.ONE, "The reception counter keeps its core and shows the chip-ready facade.")
	var chip: MeshInstance3D
	if facade != null:
		for child in facade.find_children("Facade_Chip*", "MeshInstance3D", true, false):
			chip = child as MeshInstance3D
			break
	_expect(chip != null, "The facade has chip pieces.")
	if chip != null:
		var point := (chip.global_transform * chip.get_aabb()).get_center()
		prop.call("take_projectile_hit", 20.0, point, Vector3.UP, Vector3.FORWARD, "PISTOL")
		await process_frame
		_expect(not chip.visible and _find_fragment(effects, "Fragment_Facade_Chip") != null, "A shot facade chip breaks off.")
	await _clear(prop, effects)


func _test_power_off(stage: Node3D) -> void:
	var setup := await _spawn(stage, LAPTOP, Vector3(0, 0, 8))
	var prop: RigidBody3D = setup[0]
	var effects: Node3D = setup[1]
	var power_off := prop.get_node("Visual").get_node_or_null("Power_Off") as Node3D
	_expect(power_off != null and power_off.scale == Vector3.ZERO, "The laptop imports its hidden Power_Off stage.")
	for i in 20:
		if power_off == null or power_off.scale == Vector3.ONE:
			break
		prop.call("take_projectile_hit", 30.0, prop.global_position, Vector3.UP, Vector3.FORWARD, "UZI")
		await process_frame
	_expect(power_off != null and power_off.scale == Vector3.ONE and power_off.visible, "Damage switches the laptop to its Power_Off stage.")
	await _clear(prop, effects)


func _test_rack_textures(stage: Node3D) -> void:
	var setup := await _spawn(stage, SERVER_RACK, Vector3(10, 0, 8))
	var prop: RigidBody3D = setup[0]
	var effects: Node3D = setup[1]
	var damaged := prop.get_node("Visual").find_child("Modular", true, false) as Node3D
	_expect(damaged != null, "Updated rack contains its damaged Modular stage.")
	var materials: Dictionary = {}
	if damaged != null:
		for node in damaged.find_children("*", "MeshInstance3D", true, false):
			var mesh := node as MeshInstance3D
			for surface in mesh.mesh.get_surface_count():
				materials[[mesh, surface]] = mesh.get_active_material(surface)
	await _break(prop)
	_expect(bool(prop.get("_broken")) and damaged != null and damaged.visible,
		"Damaged rack becomes visible after projectile damage.")
	_expect(not materials.is_empty(), "Damaged rack has authored materials.")
	for key: Array in materials:
		var material := materials[key] as BaseMaterial3D
		_expect(material != null and material.albedo_texture != null,
			"Damaged rack has an authored base-color texture.")
		_expect((key[0] as MeshInstance3D).get_active_material(key[1]) == material,
			"Damage preserves the updated rack's textured material.")
	await _clear(prop, effects)


func _spawn(stage: Node3D, path: String, position: Vector3) -> Array:
	var effects := Node3D.new()
	stage.add_child(effects)
	var prop := PROP_SCENE.instantiate() as RigidBody3D
	prop.set("model_path", path)
	prop.collision_mask = 3
	stage.add_child(prop)
	prop.global_position = position
	prop.call("configure_world", effects, null)
	await physics_frame
	return [prop, effects]


func _break(prop: RigidBody3D) -> void:
	for i in 80:
		if not is_instance_valid(prop) or bool(prop.get("_broken")):
			break
		prop.call("take_projectile_hit", 400.0, prop.global_position + Vector3(0, 0.5, 0), Vector3.UP, Vector3.FORWARD, "GRENADE")
		await create_timer(0.1).timeout
	await process_frame


func _find_fragment(effects: Node3D, prefix: String) -> RigidBody3D:
	for child in effects.get_children():
		if str(child.name).begins_with(prefix):
			return child as RigidBody3D
	return null


func _clear(prop: Node, effects: Node) -> void:
	if is_instance_valid(prop):
		prop.queue_free()
	effects.queue_free()
	await process_frame


func _add_floor(stage: Node3D) -> void:
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 2
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 0.2, 60)
	shape.shape = box
	floor_body.add_child(shape)
	stage.add_child(floor_body)
	floor_body.position.y = -0.1


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
