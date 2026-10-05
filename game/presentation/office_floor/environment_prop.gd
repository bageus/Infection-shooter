extends RigidBody3D
const SFX := preload("res://game/core/audio/public/sound_events.gd")
const IMPACT_SOUND := preload("res://game/presentation/office_floor/impact_sound_watcher.gd")

const CARPET_SHADOW := preload("res://game/presentation/office_floor/carpet_shadow.gd")
const DAMAGE = preload("res://game/presentation/office_floor/environment_damage.gd")
const BALANCE = preload("res://game/features/combat/public/projectile_balance.gd")
const BOOK_CONTACT = preload("res://game/presentation/office_floor/book_contact.gd")
var repeated_electronic_particles := true


func configure_damage_particles(enabled: bool) -> void:
	repeated_electronic_particles = enabled


const SPARKS = preload("res://game/presentation/office_floor/electric_sparks.gd")
const PAPER = preload("res://game/presentation/office_floor/paper_shreds.gd")
const BLAST = preload("res://game/presentation/office_floor/blast_effect.gd")
const WALL_MOUNT = preload("res://game/presentation/office_floor/wall_mount_models.gd")
const BOOK_STACK = preload("res://game/presentation/office_floor/book_stack_breakup.gd")
const EXTINGUISHER_FX = preload("res://game/presentation/office_floor/extinguisher_hit_fx.tscn")
const HIT_REACTION = preload("res://game/presentation/office_floor/prop_hit_reaction.gd")

const DISPLAY_VIEW := preload("res://game/presentation/office_floor/display_view.gd")
const DISPLAY_PROFILES := preload("res://game/presentation/office_floor/display_surface_profiles.gd")

@export_file("*.glb") var model_path := ""
@export_enum("on", "off", "auto") var display_power := "auto"
@export_enum("static", "dynamic") var display_content := "static"
@export var display_seed := 0
var _display: Node3D
var _display_wall: Node


func has_display() -> bool:
	return model_path.get_file() in DISPLAY_PROFILES.MODELS


func configure_display(config: Dictionary) -> void:
	var power := str(config.get("power", "auto"))
	var content_type := str(config.get("content", "static"))
	display_power = power if power in ["on", "off", "auto"] else "auto"
	display_content = content_type if content_type in ["static", "dynamic"] else "static"
	if "wall_TV" in model_path.get_file():
		display_content = "dynamic"
	display_seed = clampi(int(config.get("seed", display_seed)), 0, 2147483646)
	if is_instance_valid(_display):
		_display.call("configure", get_display_config())


func get_display_config() -> Dictionary:
	if display_seed == 0:
		display_seed = randi_range(1, 2147483646)
	return {"power": display_power, "content": "dynamic" if "wall_TV" in model_path.get_file() else display_content,
		"seed": display_seed}


func configure_displays(wall: Node) -> void:
	_display_wall = wall
	if is_instance_valid(_display):
		_display.call("set_registry", wall)


func _setup_display() -> void:
	if not has_display():
		return
	_display = DISPLAY_VIEW.new()
	_display.name = "Display"
	_visual.add_child(_display)
	_display.call("setup", self, model_path, get_display_config(), _display_wall)


var _visual: Node3D
var _intact: Node3D
var _stages: Array[Node3D] = []
var _variants: Array[Node3D] = []
var _variant_index := -1
var _shapes: Array[CollisionShape3D] = []
var _shape_meshes: Array[MeshInstance3D] = []
var _glass_broken := false
var _broken := false
var _short_circuited := false
var _paper_torn := false
var _health := 0.0
var _transition_pending := false
var _pending_full_break := false
var _book_kick_cooldown := 0.0
var _extinguisher_triggered := false
var _extinguisher_fx: Node3D
var _reaction := HIT_REACTION.new()

var effects_root: Node3D
var impact_pool: Node


# Public scene wiring v1; owned by the mission composition.
func configure_world(container: Node3D, impacts: Node) -> void:
	effects_root = container
	impact_pool = impacts
	if is_instance_valid(_extinguisher_fx):
		_extinguisher_fx.call("configure_world", container, impacts)


func _physics_process(delta: float) -> void:
	_book_kick_cooldown = BOOK_CONTACT.kick_if_close(self, _book_kick_cooldown, delta)

func _ready() -> void:
	if model_path.is_empty():
		return
	var wall_mounted: bool = WALL_MOUNT.contains(model_path)
	if wall_mounted:
		set_meta("planning_wall_mount", true)
	var is_book := model_path.get_file().begins_with("09_book")
	set_physics_process(is_book)
	if is_book:
		# Player/enemy masks use layers 1-2. Bullets and aiming include layer 3.
		collision_layer = 4
		collision_mask = 3
	var packed := load(model_path) as PackedScene
	if packed == null:
		push_error("Environment model unavailable: " + model_path)
		return
	var visual := packed.instantiate() as Node3D
	if visual == null:
		return
	visual.name = "Visual"
	if "wall_TV" in model_path.get_file():
		# Authored televisions lie in XZ; wall placement expects a +Z front.
		visual.rotation.x = PI / 2.0
	add_child(visual)
	_visual = visual
	_reaction.setup(self, visual)
	_discover_stages()
	if model_path.get_file() == "06_conference_chair.glb":
		# Only the baked chair may affect its initial height or collision.
		for stage in _stages:
			stage.hide()
		for variant in _variants:
			variant.hide()
	_add_missing_bookcase_shelves()
	# This GLB exports the complete table alongside a visible Primary debris group.
	# Keep the authored intact root as the only initial mesh and collision source.
	if model_path.get_file() == "07_table_square.glb":
		var primary := DAMAGE.find_named(_visual, "Primary")
		if primary != null:
			primary.hide()
	_health = _stage_health()
	# Architectural pieces and carpets stay anchored; all other groups are movable.
	freeze = wall_mounted or model_path.begins_with("res://models/objects/enviroments/01/")
	if freeze and "01_floor_" in model_path:
		var shadow := CARPET_SHADOW.new()
		shadow.name = "CarpetShadow"
		add_child(shadow)
		shadow.configure(visual)
		return # Carpet lies on the level floor and must not create a raised obstacle.
	var volume := _add_shapes(visual)
	_setup_display()
	if model_path.get_file() == "06_conference_chair.glb" and global_position.y < 0.25:
		var lowest := INF
		for mesh in _shape_meshes:
			var bounds: AABB = mesh.global_transform * mesh.get_aabb()
			lowest = minf(lowest, bounds.position.y)
		if lowest < 0.025:
			global_position.y += 0.025 - lowest
	mass = clampf(volume * 18.0, 0.12, 55.0)
	if "fire_extinguisher" in model_path.get_file():
		mass = 1.8
		linear_damp = 3.5
		angular_damp = 2.5
		_extinguisher_fx = EXTINGUISHER_FX.instantiate() as Node3D
		add_child(_extinguisher_fx)
		_extinguisher_fx.call("configure", self, _shape_meshes)
		_extinguisher_fx.call("configure_world", effects_root, impact_pool)
		_extinguisher_fx.connect("ruptured", _on_extinguisher_ruptured)
	if "table" in model_path.get_file() or "desk" in model_path.get_file():
		linear_damp = 3.0
		angular_damp = 4.0
	# Continuous detection is costly; only small, light objects can be fast enough to tunnel.
	continuous_cd = mass < 4.0
	if not freeze or wall_mounted:
		IMPACT_SOUND.watch(self)


func _add_shapes(node: Node) -> float:
	var volume := 0.0
	if node is MeshInstance3D:
		var mesh := node as MeshInstance3D
		if mesh.mesh != null and mesh.is_visible_in_tree() and absf(mesh.global_basis.determinant()) > 0.000000000001:
			var box := BoxShape3D.new()
			var bounds := mesh.get_aabb()
			box.size = Vector3(maxf(bounds.size.x, 0.02), maxf(bounds.size.y, 0.02), maxf(bounds.size.z, 0.02))
			var shape := CollisionShape3D.new()
			shape.name = mesh.name
			shape.shape = box
			add_child(shape)
			_shapes.append(shape)
			_shape_meshes.append(mesh)
			var local := global_transform.affine_inverse() * mesh.global_transform
			shape.transform = local
			shape.position += local.basis * bounds.get_center()
			volume += box.size.x * box.size.y * box.size.z * absf(local.basis.determinant())
	for child in node.get_children():
		volume += _add_shapes(child)
	return volume


func _discover_stages() -> void:
	_intact = DAMAGE.find_named(_visual, "Intact")
	for name_part in ["Hit_01", "Dent_01", "Dent_02", "Dent_03", "Power_Off"]:
		var variant: Node3D = DAMAGE.find_named(_visual, name_part)
		if variant != null:
			_variants.append(variant)
	# Staged GLBs (addons/staged_glb_import) add LargeParts → Small/JaggedFragments,
	# PlantDestroyed → PotFragments and the in-place DamageReady facade.
	for name_part in ["Modular", "Door_Off", "LargeParts", "SmallFragments", "JaggedFragments", "PlantDestroyed", "PotFragments", "Broken_7", "Fragments", "Primary", "Panels", "Medium", "Fine", "TopSecondary", "DamageReady"]:
		var stage: Node3D = DAMAGE.find_named(_visual, name_part)
		if stage != null:
			_stages.append(stage)


func _add_missing_bookcase_shelves() -> void:
	if model_path.get_file() not in ["03_book_case.glb", "03_book_case_with_back.glb"] or _intact == null:
		return
	var baked := _intact.find_child("Intact*", true, false) as MeshInstance3D
	if baked == null:
		return # Re-exported staged bookcases already contain their shelves.
	var material: Material = baked.get_active_material(0)
	if material == null:
		var wood := StandardMaterial3D.new()
		wood.albedo_color = Color(0.45, 0.27, 0.16)
		material = wood
	for shelf_height in [0.50, 0.95, 1.40, 1.85, 2.30]:
		var shelf := MeshInstance3D.new()
		shelf.name = "VisibleShelf"
		var mesh := BoxMesh.new()
		mesh.size = Vector3(1.94, 0.035, 0.46)
		mesh.material = material
		shelf.mesh = mesh
		_intact.add_child(shelf)
		shelf.position.y = shelf_height


func take_projectile_hit_at_shape(damage: float, hit_position: Vector3, normal: Vector3, direction: Vector3, weapon: String, shape_index: int) -> bool:
	if shape_index >= 0:
		var owner_id := shape_find_owner(shape_index)
		var collision := shape_owner_get_owner(owner_id) as CollisionShape3D
		var mesh_index := _shapes.find(collision)
		if mesh_index >= 0 and _is_glass_mesh(_shape_meshes[mesh_index]):
			call_deferred("_shatter_glass", hit_position, direction)
			if weapon != "GRENADE":
				return false
	return take_projectile_hit(damage, hit_position, normal, direction, weapon)


func get_projectile_material(shape_index: int = -1) -> String:
	if shape_index >= 0:
		var shape_owner := shape_owner_get_owner(shape_find_owner(shape_index)) as CollisionShape3D
		var mesh_index := _shapes.find(shape_owner)
		if mesh_index >= 0 and _is_glass_mesh(_shape_meshes[mesh_index]):
			return "glass"
	var group := model_path.get_file().substr(0, 2)
	if group == "01": return "concrete"
	if group == "05": return "tech"
	if group == "09" or group == "11": return "light"
	if group == "03" or group == "06": return "metal"
	return "wood"


func _damage_category() -> String:
	var group := model_path.get_file().substr(0, 2)
	if group == "05": return "tech"
	if group == "09" or group == "11" or group == "12": return "small"
	return "large"


func _stage_health() -> float:
	match _damage_category():
		"tech": return 65.0
		"small": return 42.0
	return 155.0


func take_projectile_hit(damage: float, hit_position: Vector3, _normal: Vector3, direction: Vector3, weapon: String) -> bool:
	if "fire_extinguisher" in model_path.get_file():
		_trigger_extinguisher(hit_position, direction)
		return false
	if PAPER.is_paper(model_path):
		_tear_paper(hit_position, direction)
		return false
	if _damage_category() == "tech":
		if _short_circuited:
			if repeated_electronic_particles:
				SPARKS.spawn(self, hit_position)
		else:
			_short_circuited = true
			if is_instance_valid(_display):
				_display.call("disable")
			SPARKS.short_circuit(self, hit_position, _normal)
	if model_path.get_file() == "02_water_cooler_bottle.glb":
		if not freeze:
			sleeping = false
			apply_central_impulse((direction.normalized() + Vector3.UP * 0.25).normalized() * (mass * 0.055 if weapon == "SHOTGUN" else mass * 0.2))
		return false
	if not freeze and weapon == "SHOTGUN":
		sleeping = false
		var is_table := "table" in model_path.get_file() or "desk" in model_path.get_file()
		var push := direction.normalized() if is_table else (direction.normalized() + Vector3.UP * 0.18).normalized()
		apply_central_impulse(push * clampf(mass * (0.004 if is_table else 0.015), 0.025, 0.15 if is_table else 0.32))
	if BOOK_STACK.contains(model_path) and not _broken:
		_health -= BALANCE.object_damage(damage, weapon, "small")
		if _health <= 0.0:
			_broken = true
			BOOK_STACK.scatter(self, _visual, hit_position, direction)
			queue_free()
	elif not _broken and not _transition_pending and (_variant_index + 1 < _variants.size() or not _stages.is_empty()):
		_health -= BALANCE.object_damage(damage, weapon, _damage_category())
		if _health <= 0.0:
			_pending_full_break = weapon == "GRENADE" and not _stages.is_empty()
			_transition_pending = true
			call_deferred("_apply_damage", hit_position, direction)
		elif damage > 0.0 and weapon != "PISTOL":
			_reaction.shudder(direction)
	elif _broken and _is_facade_damage():
		_chip_facade(hit_position, direction)
	elif bool(get_meta("planning_wall_mount", false)) and freeze and not _broken:
		_health -= BALANCE.object_damage(damage, weapon, _damage_category())
		if _health <= 0.0:
			_broken = true
			freeze = false
			IMPACT_SOUND.wake(self)
			sleeping = false
			apply_central_impulse((direction.normalized() + Vector3.UP * 0.2).normalized() * maxf(0.5, mass * 0.12))
	elif not freeze:
		sleeping = false
		apply_impulse(direction.normalized() * maxf(0.4, mass * 0.3), hit_position - global_position)
	return false


# Any paper object is torn apart completely by a single shot.
func _tear_paper(hit_position: Vector3, direction: Vector3) -> void:
	if _paper_torn:
		return
	_paper_torn = true
	_broken = true
	PAPER.tear(self, hit_position, direction)
	collision_layer = 0
	if _visual != null:
		_visual.hide()
	for collision in _shapes:
		collision.set_deferred("disabled", true)
	queue_free.call_deferred()


func _trigger_extinguisher(hit_position: Vector3, direction: Vector3) -> void:
	if _extinguisher_triggered:
		return
	_extinguisher_triggered = true
	if _extinguisher_fx != null:
		_extinguisher_fx.call("start", hit_position, direction)


func _on_extinguisher_ruptured(location: Vector3) -> void:
	BLAST.detonate(self, location, 5.0, false)
	_visual.hide()
	collision_layer = 0
	queue_free()


func take_melee_hit(damage: float, hit_position: Vector3, direction: Vector3) -> void:
	if bool(get_meta("planning_wall_mount", false)) and freeze:
		return
	take_projectile_hit(damage, hit_position, Vector3.ZERO, direction, "MELEE")


func _apply_damage(hit_position: Vector3, direction: Vector3) -> void:
	if _broken:
		return
	_reaction.cancel()
	if _damage_category() == "tech":
		SPARKS.spawn(self, hit_position, true)
	if _variant_index + 1 < _variants.size() and not _pending_full_break:
		if _intact != null:
			_intact.hide()
		if _variant_index >= 0:
			_variants[_variant_index].hide()
		_variant_index += 1
		var variant := _variants[_variant_index]
		DAMAGE.reveal_meshes(variant)
		variant.show()
		_health = _stage_health() * 0.8
		_transition_pending = false
		_rebuild_shapes()
	elif not _stages.is_empty():
		_broken = true
		if "server_rack" in model_path.get_file() or _is_facade_damage():
			if _intact != null:
				_intact.hide()
			var rack_meshes: Array[MeshInstance3D] = DAMAGE.reveal_meshes(_stages[0])
			if model_path.get_file() == "03_server_rack3.glb":
				var dark_metal := StandardMaterial3D.new()
				dark_metal.albedo_color = Color(0.055, 0.075, 0.09)
				dark_metal.metallic = 0.55
				for rack_mesh in rack_meshes:
					rack_mesh.material_override = dark_metal
			_stages[0].show()
			_rebuild_shapes()
			return
		_reaction.break_dust(_shape_meshes)
		_visual.hide()
		for shape in _shapes:
			shape.set_deferred("disabled", true)
		collision_layer = 0
		freeze = true
		_spawn_stage(0, "", hit_position, direction, _pending_full_break)


# Localized damage (reception counter): the core stays, facade chips break off.
func _is_facade_damage() -> bool:
	return not _stages.is_empty() and _stages[0].name == "DamageReady"


func _chip_facade(hit_position: Vector3, direction: Vector3) -> void:
	var nearest: MeshInstance3D
	var nearest_distance := 0.8
	for mesh in DAMAGE.reveal_meshes(_stages[0]):
		if mesh.visible and mesh.name.begins_with("Facade_Chip"):
			var distance := (mesh.global_transform * mesh.get_aabb()).get_center().distance_to(hit_position)
			if distance < nearest_distance:
				nearest = mesh
				nearest_distance = distance
	if nearest == null:
		return
	DAMAGE.spawn_piece(self, nearest, null, _stages.size(), 0, direction, hit_position)
	nearest.hide()
	_rebuild_shapes()


func _rebuild_shapes() -> void:
	_reaction.cancel()
	for shape in _shapes:
		shape.set_deferred("disabled", true)
		shape.queue_free()
	_shapes.clear()
	_shape_meshes.clear()
	_add_shapes(_visual)


func _spawn_stage(stage_index: int, prefix: String, hit_position: Vector3, direction: Vector3, blast: bool = false) -> bool:
	if stage_index >= _stages.size():
		return false
	var meshes: Array[MeshInstance3D] = DAMAGE.reveal_meshes(_stages[stage_index])
	var spawned := 0
	for mesh in meshes:
		if not prefix.is_empty() and mesh.name != prefix and not mesh.name.begins_with(prefix + "_"):
			continue
		if spawned >= 32:
			break
		var body: RigidBody3D = DAMAGE.spawn_piece(self, mesh, self, stage_index, spawned, direction, hit_position, blast)
		if body != null:
			spawned += 1
	return spawned > 0


func hit_environment_fragment(fragment: RigidBody3D, hit_position: Vector3, direction: Vector3) -> void:
	var name_part: String = fragment.get("piece_name")
	var next_stage: int = int(fragment.get("stage_index")) + 1
	while next_stage < _stages.size():
		if _spawn_stage(next_stage, name_part, hit_position, direction):
			fragment.queue_free()
			return
		next_stage += 1
	# A single-piece stage (a knocked-over plant pot) shatters into the whole next stage.
	var stage_index := int(fragment.get("stage_index"))
	if stage_index + 1 < _stages.size() and DAMAGE.reveal_meshes(_stages[stage_index]).size() == 1:
		if _spawn_stage(stage_index + 1, "", hit_position, direction, true):
			fragment.queue_free()
			return
	fragment.apply_central_impulse(direction.normalized() * 0.6)


func _shatter_glass(hit_position: Vector3, direction: Vector3) -> void:
	if _glass_broken or _broken:
		return
	_glass_broken = true
	SFX.play(self, &"glass_break", hit_position)
	var glass_bounds := AABB()
	var found := false
	for i in _shape_meshes.size():
		var mesh := _shape_meshes[i]
		if not is_instance_valid(mesh) or not _is_glass_mesh(mesh):
			continue
		var bounds: AABB = mesh.global_transform * mesh.get_aabb()
		glass_bounds = bounds if not found else glass_bounds.merge(bounds)
		found = true
		if "glass" in mesh.name.to_lower() or "mirror" in mesh.name.to_lower() or mesh.mesh.get_surface_count() == 1:
			mesh.hide()
			_shapes[i].set_deferred("disabled", true)
	if not found:
		return
	var shards: Node3D = DAMAGE.find_named(_visual, "Glass_Shards")
	if shards != null:
		# Vending machines keep their shard group below a hidden damage variant.
		# Reveal its parents only while copying shard geometry.
		var hidden_parents: Array[Node3D] = []
		var ancestor := shards.get_parent() as Node3D
		while ancestor != null and ancestor != _visual:
			if ancestor.scale.length_squared() < 0.000001:
				hidden_parents.append(ancestor)
				ancestor.scale = Vector3.ONE
			ancestor = ancestor.get_parent() as Node3D
		var meshes: Array[MeshInstance3D] = DAMAGE.reveal_meshes(shards)
		for index in mini(meshes.size(), 12):
			DAMAGE.spawn_piece(self, meshes[index], self, _stages.size(), index, direction, hit_position)
		for hidden in hidden_parents:
			hidden.scale = Vector3.ZERO
	else:
		_spawn_fallback_glass(glass_bounds, hit_position, direction)


func _is_glass_mesh(mesh: MeshInstance3D) -> bool:
	if mesh == null or mesh.mesh == null:
		return false
	var lower := mesh.name.to_lower()
	if "glass" in lower or "mirror" in lower:
		return true
	for surface in mesh.mesh.get_surface_count():
		var material := mesh.get_active_material(surface)
		if material != null and ("glass" in material.resource_name.to_lower() or "mirror" in material.resource_name.to_lower()):
			return true
	return false


func _spawn_fallback_glass(bounds: AABB, hit_position: Vector3, direction: Vector3) -> void:
	for i in 6:
		var part := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.09, 0.12, 0.025)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.55, 0.84, 0.95, 0.7)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		box.material = material
		part.mesh = box
		_visual.add_child(part)
		part.global_position = bounds.position + Vector3(randf() * bounds.size.x, randf() * bounds.size.y, randf() * bounds.size.z)
		DAMAGE.spawn_piece(self, part, null, _stages.size(), i, direction, hit_position)
		part.queue_free()


func push_from_character(character_position: Vector3, movement: Vector3) -> void:
	if freeze or movement.length_squared() < 0.01:
		return
	var away := global_position - character_position
	away.y = 0.0
	var direction := away.normalized() if away.length_squared() > 0.01 else movement.normalized()
	sleeping = false
	apply_central_impulse(direction * minf(mass * 0.45, 3.0))


func get_display_edges() -> Dictionary:
	if not is_instance_valid(_display) or not bool(_display.get("tiled")):
		return {}
	var profile: Dictionary = (_display.get("screens") as Array)[0]["profile"]
	return {"frame": _display.call("wall_frame"), "size": Vector2(float(profile["size"][0]), float(profile["size"][1]))}


func snap_display_edges(neighbors: Array[Dictionary]) -> void:
	var source := get_display_edges()
	if not source.is_empty():
		global_position += preload("res://game/presentation/office_floor/display_edge_snap.gd").position(source, neighbors)
