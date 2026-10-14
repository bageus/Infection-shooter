extends RigidBody3D
## Scene boundary for prop physics, hit commands and authored display configuration.
const BUDGET_LIGHT := preload("res://game/presentation/office_floor/budget_omni_light.gd")
const GEOMETRY := preload("res://game/presentation/office_floor/environment_prop_geometry.gd")
const BREAK_SOUND := preload("res://game/presentation/office_floor/prop_break_sound.gd")
const BREAKUP := preload("res://game/presentation/office_floor/environment_prop_breakup.gd")
var _geometry := GEOMETRY.new()
const IMPACT_SOUND := preload("res://game/presentation/office_floor/impact_sound_watcher.gd")

const CARPET_SHADOW := preload("res://game/presentation/office_floor/carpet_shadow.gd")
const CONTACT_SHADOW := preload("res://game/presentation/office_floor/prop_contact_shadow.gd")
const DAMAGE = preload("res://game/presentation/office_floor/environment_damage.gd")
const PROP_DAMAGE := preload("res://game/features/combat/public/prop_damage_state.gd")
var _damage := PROP_DAMAGE.new()
const WEIGHT = preload("res://game/presentation/office_floor/prop_weight.gd")
const CONTACT = preload("res://game/presentation/office_floor/prop_contact.gd")
const BULLET_PUSH = preload("res://game/presentation/office_floor/bullet_push.gd")
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
const SIGN_LIFETIME := 1.0
const BOTTLE_BURST := preload("res://game/presentation/office_floor/water_bottle_burst.gd")

const LOOT_DROP := preload("res://game/features/pickups/public/loot_drop.gd")
const LOOT_CONFIG := preload("res://game/features/pickups/public/loot_config.gd")
const DISPLAY_VIEW := preload("res://game/presentation/office_floor/display_view.gd")
const DISPLAY_PROFILES := preload("res://game/presentation/office_floor/display_surface_profiles.gd")
const SURFACE_DECOR := preload("res://game/presentation/office_floor/office_surface_decor.gd")

@export_file("*.glb") var model_path := ""
@export_enum("on", "off", "auto") var display_power := "auto"
@export_enum("static", "dynamic") var display_content := "static"
@export var display_seed := 0
var _display: Node3D
var _display_wall: Node


## Screens have power and content settings; the desk lamp shares the power setting (on or off).
func has_display() -> bool:
	return model_path.get_file() in DISPLAY_PROFILES.MODELS or is_desk_lamp()


func is_desk_lamp() -> bool:
	return model_path.get_file() == "05_lamp.glb"


func configure_display(config: Dictionary) -> void:
	var power := str(config.get("power", "auto"))
	var content_type := str(config.get("content", "static"))
	display_power = power if power in ["on", "off", "auto"] else "auto"
	_apply_lamp_power()
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
	if not model_path.get_file() in DISPLAY_PROFILES.MODELS:
		return
	_display = DISPLAY_VIEW.new()
	_display.name = "Display"
	_visual.add_child(_display)
	_display.call("setup", self, model_path, get_display_config(), _display_wall)


# Diagnostic and inherited views; geometry owns the collections.
var _visual: Node3D:
	get:
		return _geometry.visual
var _intact: Node3D:
	get:
		return _geometry.intact
var _stages: Array[Node3D]:
	get:
		return _geometry.stages
var _variants: Array[Node3D]:
	get:
		return _geometry.variants
var _shapes: Array[CollisionShape3D]:
	get:
		return _geometry.shapes
var _shape_meshes: Array[MeshInstance3D]:
	get:
		return _geometry.meshes
# Read-only compatibility for existing diagnostic callers.
var _broken: bool:
	get:
		return _damage.broken
## Item weight in kg (prop_weight_v1); the RigidBody mass stays as authored.
var weight_kg := 0.0
var _extinguisher_fx: Node3D
var _reaction := HIT_REACTION.new()

var effects_root: Node3D
var _drop_weapon: Callable
var impact_pool: Node


# Public scene wiring v1; owned by the mission composition.
func configure_world(container: Node3D, impacts: Node) -> void:
	effects_root = container
	impact_pool = impacts
	if is_instance_valid(_extinguisher_fx):
		_extinguisher_fx.call("configure_world", container, impacts)


## Crates can hold loot (planner); it falls out when the crate breaks.
func has_loot() -> bool:
	return "crate" in model_path.get_file()


func configure_loot(config: Dictionary) -> void:
	if has_loot():
		set_meta(&"planning_loot", LOOT_CONFIG.sanitize(config, "empty"))


## A crate without authored loot stays empty, as before.
func get_loot_config() -> Dictionary:
	return LOOT_CONFIG.sanitize((get_meta(&"planning_loot") if has_meta(&"planning_loot") else null), "empty")


func configure_loot_drop(drop_weapon: Callable) -> void:
	_drop_weapon = drop_weapon


func _release_loot() -> void:
	if not has_loot() or not has_meta(&"planning_loot"):
		return
	var world: Node = effects_root if is_instance_valid(effects_root) else get_parent()
	if world == null:
		return
	var size_hint := "large" if "large" in model_path.get_file() else "small"
	LOOT_DROP.release_crate(world, global_position, get_loot_config(), size_hint, _drop_weapon)


func _ready() -> void:
	if model_path.is_empty():
		return
	var wall_mounted: bool = WALL_MOUNT.contains(model_path)
	if wall_mounted:
		set_meta("planning_wall_mount", true)
		if "/enviroments/13/" in model_path:
			add_to_group(&"wall_signs")
	if not _geometry.load_visual(self, model_path):
		return
	var visual := _visual
	_reaction.setup(self, visual)
	_geometry.prepare_stages(model_path)
	_damage.configure(model_path.get_file(), _variants.size(), not _stages.is_empty())
	# Architectural pieces and carpets stay anchored; all other groups are movable.
	freeze = wall_mounted or model_path.begins_with("res://models/objects/enviroments/01/")
	if freeze and "01_floor_" in model_path:
		var shadow := CARPET_SHADOW.new()
		shadow.name = "CarpetShadow"
		add_child(shadow)
		shadow.configure(visual)
		return # Carpet lies on the level floor and must not create a raised obstacle.
	var volume := _geometry.add_shapes(self, visual)
	_setup_display()
	SURFACE_DECOR.apply(visual, model_path, _display, display_seed)
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
	_setup_weight(volume)
	_add_contact_shadow(wall_mounted)
	if is_desk_lamp():
		_add_desk_lamp_light()
	if not freeze or wall_mounted:
		IMPACT_SOUND.watch(self)


# The desk lamp lights its own surroundings from under the shade.
func _add_desk_lamp_light() -> void:
	var shade := _visual.find_child("Lamp_*", true, false) as Node3D
	if shade == null:
		return
	var glow := BUDGET_LIGHT.create(Color(1.0, 0.86, 0.62), 1.1, 2.8)
	glow.position = Vector3(0.0, 0.12, 0.0)
	shade.add_child(glow)
	_apply_lamp_power()


# The planner can switch a desk lamp off; a lamp put out by damage stays out.
func _apply_lamp_power() -> void:
	if not is_desk_lamp() or not is_inside_tree():
		return
	var glow := find_child("BudgetLight", true, false)
	if glow != null:
		glow.call("set_wanted", display_power != "off")


# Furniture standing on the floor gets a light shadow under it.
func _add_contact_shadow(wall_mounted: bool) -> void:
	if wall_mounted or has_meta(&"kickable_prop"):
		return
	var shadow := CONTACT_SHADOW.new()
	shadow.name = "ContactShadow"
	add_child(shadow)
	if not shadow.configure(self, _visual, _shape_meshes):
		shadow.queue_free()


func take_projectile_hit_at_shape(damage: float, hit_position: Vector3, normal: Vector3, direction: Vector3, weapon: String, shape_index: int) -> bool:
	if shape_index >= 0:
		var owner_id := shape_find_owner(shape_index)
		var collision := shape_owner_get_owner(owner_id) as CollisionShape3D
		var mesh_index := _shapes.find(collision)
		if mesh_index >= 0 and mesh_index < _shape_meshes.size() and is_instance_valid(_shape_meshes[mesh_index]) and GEOMETRY.is_glass_mesh(_shape_meshes[mesh_index]):
			call_deferred("_shatter_glass", hit_position, direction)
			if weapon != "GRENADE":
				return false
		if _is_cooler_bottle_shape(mesh_index) and damage > 0.0 and weapon != "GRENADE":
			_burst_bottle(mesh_index, hit_position, direction)
			return false
	return take_projectile_hit(damage, hit_position, normal, direction, weapon)


# Only the bottle bursts; the cooler body behind it stays standing.
func _is_cooler_bottle_shape(mesh_index: int) -> bool:
	if not model_path.get_file().begins_with("02_water_cooler_bottle_attached"):
		return false
	return mesh_index >= 0 and mesh_index < _shape_meshes.size() and BOTTLE_BURST.find_bottle([_shape_meshes[mesh_index]]) == 0


func _burst_bottle(mesh_index: int, hit_position: Vector3, direction: Vector3) -> void:
	BOTTLE_BURST.burst(self, _shape_meshes[mesh_index], _shapes[mesh_index], effects_root, hit_position, direction)


func get_projectile_material(shape_index: int = -1) -> String:
	if shape_index >= 0:
		var shape_owner := shape_owner_get_owner(shape_find_owner(shape_index)) as CollisionShape3D
		var mesh_index := _shapes.find(shape_owner)
		if mesh_index >= 0 and mesh_index < _shape_meshes.size() and is_instance_valid(_shape_meshes[mesh_index]) and GEOMETRY.is_glass_mesh(_shape_meshes[mesh_index]):
			return "glass"
	var group := model_path.get_file().substr(0, 2)
	if group == "01": return "concrete"
	if group == "05": return "tech"
	if group == "09" or group == "11": return "light"
	if group == "03" or group == "06": return "metal"
	return "wood"


func take_projectile_hit(damage: float, hit_position: Vector3, _normal: Vector3, direction: Vector3, weapon: String) -> bool:
	if "fire_extinguisher" in model_path.get_file():
		BULLET_PUSH.apply(self, weight_kg, weapon, direction, hit_position)
		_trigger_extinguisher(hit_position, direction)
		return false
	if PAPER.is_paper(model_path):
		_tear_paper(hit_position, direction)
		return false
	if _damage.category == "tech":
		if damage > 0.0 and model_path.get_file() == "05_lamp.glb":
			_put_out_lamp()
		if not _damage.short_circuit():
			if repeated_electronic_particles:
				SPARKS.spawn(self, hit_position)
		else:
			if is_instance_valid(_display):
				_display.call("disable")
			SPARKS.short_circuit(self, hit_position, _normal)
			if is_desk_lamp():
				BREAK_SOUND.play(self, effects_root, model_path, "tech", hit_position)
	if model_path.get_file() == "02_water_cooler_bottle.glb":
		var bottle := BOTTLE_BURST.find_bottle(_shape_meshes)
		if bottle >= 0 and damage > 0.0:
			_burst_bottle(bottle, hit_position, direction)
			collision_layer = 0
			queue_free.call_deferred()
		return false
	# Every loose item moves when shot, by its weight (anchored ones stay).
	BULLET_PUSH.apply(self, weight_kg, weapon, direction, hit_position)
	var action := _damage.hit(damage, weapon, BOOK_STACK.contains(model_path),
		bool(get_meta("planning_wall_mount", false)), freeze, _is_facade_damage())
	match action:
		PROP_DAMAGE.HitAction.SCATTER:
			BOOK_STACK.scatter(self, _visual, hit_position, direction)
			queue_free()
		PROP_DAMAGE.HitAction.TRANSITION:
			call_deferred("_apply_damage", hit_position, direction)
		PROP_DAMAGE.HitAction.SHUDDER:
			_reaction.shudder(direction)
		PROP_DAMAGE.HitAction.CHIP_FACADE:
			if BREAKUP.chip_facade(self, _geometry, hit_position, direction):
				BREAK_SOUND.play(self, effects_root, model_path, get_projectile_material(), hit_position)
				_rebuild_shapes()
		PROP_DAMAGE.HitAction.DETACH:
			BREAK_SOUND.play(self, effects_root, model_path, get_projectile_material(), hit_position)
			_detach(direction)
	return false


func _detach(direction: Vector3) -> void:
	freeze = false
	IMPACT_SOUND.wake(self)
	sleeping = false
	apply_central_impulse((direction.normalized() + Vector3.UP * 0.2).normalized() * maxf(0.5, mass * 0.12))
	if is_in_group(&"wall_signs"):
		_vanish_after(SIGN_LIFETIME)


## A wall sign mounted on a glass pane drops with it when the pane breaks.
func fall_off_with_glass() -> void:
	if not is_in_group(&"wall_signs") or not freeze or _damage.broken:
		return
	_damage.broken = true
	_detach(Vector3.DOWN)


func _vanish_after(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
	if not is_inside_tree():
		return
	collision_layer = 0
	collision_mask = 0
	queue_free()


func _put_out_lamp() -> void:
	var glow := find_child("BudgetLight", true, false)
	if glow != null:
		glow.call("set_wanted", false)


# Any paper object is torn apart completely by a single shot.
func _tear_paper(hit_position: Vector3, direction: Vector3) -> void:
	if not _damage.tear_paper():
		return
	PAPER.tear(self, hit_position, direction)
	collision_layer = 0
	if _visual != null:
		_visual.hide()
	for collision in _shapes:
		collision.set_deferred("disabled", true)
	queue_free.call_deferred()


func _trigger_extinguisher(hit_position: Vector3, direction: Vector3) -> void:
	if not _damage.trigger_extinguisher():
		return
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
	if _damage.category == "tech":
		SPARKS.spawn(self, hit_position, true)
	var previous_variant := _damage.variant_index
	var transition := _damage.complete_transition()
	if transition == PROP_DAMAGE.Transition.VARIANT:
		if _intact != null:
			_intact.hide()
		if previous_variant >= 0:
			_variants[previous_variant].hide()
		var variant := _variants[_damage.variant_index]
		if not _geometry.ensure_group(variant):
			return
		DAMAGE.reveal_meshes(variant)
		variant.show()
		_rebuild_shapes()
		BREAK_SOUND.play(self, effects_root, model_path, get_projectile_material(), hit_position)
	elif transition == PROP_DAMAGE.Transition.BREAK:
		BREAK_SOUND.play(self, effects_root, model_path, get_projectile_material(), hit_position)
		if "server_rack" in model_path.get_file() or _is_facade_damage():
			if _intact != null:
				_intact.hide()
			if not _geometry.ensure_group(_stages[0]):
				return
			DAMAGE.reveal_meshes(_stages[0])
			_stages[0].show()
			_rebuild_shapes()
			return
		_release_loot()
		_reaction.break_dust(_shape_meshes)
		if model_path.get_file().begins_with("02_water_cooler_bottle_attached"):
			var intact_bottle := BOTTLE_BURST.find_bottle(_shape_meshes)
			if intact_bottle >= 0:
				_burst_bottle(intact_bottle, hit_position, direction)
		_visual.hide()
		for shape in _shapes:
			shape.set_deferred("disabled", true)
		collision_layer = 0
		freeze = true
		BREAKUP.spawn_stage(self, _geometry, 0, "", hit_position, direction, _damage.full_break)


func _is_facade_damage() -> bool:
	return not _stages.is_empty() and _stages[0].name == "DamageReady"


func _rebuild_shapes() -> void:
	_reaction.cancel()
	_geometry.rebuild(self)


func hit_environment_fragment(fragment: RigidBody3D, hit_position: Vector3, direction: Vector3) -> void:
	if fragment.is_queued_for_deletion():
		return
	BREAKUP.hit_fragment(self, _geometry, fragment, hit_position, direction)
	if fragment.is_queued_for_deletion():
		BREAK_SOUND.play(self, effects_root, model_path, get_projectile_material(), hit_position)


func _shatter_glass(hit_position: Vector3, direction: Vector3) -> void:
	if _damage.break_glass():
		BREAKUP.shatter_glass(self, _geometry, hit_position, direction)


# Light, low items stop blocking characters (layer 3) and are kicked aside by
# feet; everything else is pushed according to its weight.
func _setup_weight(volume: float) -> void:
	weight_kg = WEIGHT.weight_kg(model_path.get_file(), volume)
	if freeze:
		return
	var bounds := AABB()
	for index in _shape_meshes.size():
		var mesh_bounds: AABB = _shape_meshes[index].global_transform * _shape_meshes[index].get_aabb()
		bounds = mesh_bounds if index == 0 else bounds.merge(mesh_bounds)
	if WEIGHT.is_kickable(weight_kg, bounds.size):
		CONTACT.make_kickable(self)
		body_entered.connect(func(body: Node) -> void: CONTACT.kick(self, weight_kg, body))


func push_from_character(character_position: Vector3, movement: Vector3, strength: float = 1.0) -> void:
	CONTACT.push(self, weight_kg, character_position, movement, strength)


func get_display_edges() -> Dictionary:
	if not is_instance_valid(_display) or not bool(_display.get("tiled")):
		return {}
	var profile: Dictionary = (_display.get("screens") as Array)[0]["profile"]
	return {"frame": _display.call("wall_frame"), "size": Vector2(float(profile["size"][0]), float(profile["size"][1]))}


func snap_display_edges(neighbors: Array[Dictionary]) -> void:
	var source := get_display_edges()
	if not source.is_empty():
		global_position += preload("res://game/presentation/office_floor/display_edge_snap.gd").position(source, neighbors)
