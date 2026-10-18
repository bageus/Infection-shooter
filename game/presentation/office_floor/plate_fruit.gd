extends RefCounted
## Fruit baked onto a plate prop (plate_fruit_v1): one body, random seeded layout, scatters when shot.
## Authored config {"enabled": bool, "count": 1..5, "seed": int}; a plate without fruit stays as before.

const DAMAGE := preload("res://game/presentation/office_floor/environment_damage.gd")
const GEOMETRY := preload("res://game/presentation/office_floor/environment_prop_geometry.gd")
const PROP_DAMAGE := preload("res://game/features/combat/public/prop_damage_state.gd")
const SFX := preload("res://game/core/audio/public/sound_events.gd")
const MODEL_DIR := "res://models/objects/enviroments/09/"
## Only the flat round plate carries fruit; the platter model already has its own.
const PLATES: Array[String] = ["09_fruit_plate_2.glb"]
const FRUITS: Array[String] = ["09_fruit_apple.glb", "09_fruit_orange.glb", "09_fruit_banana.glb", "09_fruit_banana_b.glb"]
const MIN_COUNT := 1
const MAX_COUNT := 5
const PLATE_RADIUS := 0.1
const DISH_HEIGHT := 0.015
const NODE_NAME := "Fruit"

var config := {"enabled": false, "count": 3, "seed": 0}
var _spent := false


static func applies(model_path: String) -> bool:
	return model_path.get_file() in PLATES


static func sanitize(raw: Variant) -> Dictionary:
	var source: Dictionary = raw if raw is Dictionary else {}
	var count := int(source.get("count", 3)) if source.get("count", 3) is int or source.get("count", 3) is float else 3
	var seed_value := int(source.get("seed", 0)) if source.get("seed", 0) is int or source.get("seed", 0) is float else 0
	return {"enabled": typeof(source.get("enabled")) == TYPE_BOOL and source["enabled"], "count": clampi(count, MIN_COUNT, MAX_COUNT),
		"seed": clampi(seed_value, 0, 2147483646)}


## Kinds of the fruit in the layout, in placement order; the same seed gives the same plate.
static func layout(count: int, seed_value: int) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var items: Array[Dictionary] = []
	var start := rng.randf() * TAU
	var banana_used := false
	for index in count:
		var model := FRUITS[rng.randi_range(0, FRUITS.size() - 1)]
		if "banana" in model:
			# One banana per plate: they are as long as the dish is wide.
			model = FRUITS[rng.randi_range(0, 1)] if banana_used else model
			banana_used = true
		var angle := start + (float(index) + rng.randf_range(-0.2, 0.2)) * TAU / count
		var radius := rng.randf_range(0.0, 0.03) if count == 1 else rng.randf_range(0.05, PLATE_RADIUS)
		radius = minf(radius, 0.03) if "banana" in model else radius
		items.append({"model": model, "position": Vector3(cos(angle) * radius, DISH_HEIGHT, sin(angle) * radius), "yaw": rng.randf() * TAU})
	return items


func configure(body: RigidBody3D, geometry: GEOMETRY, raw: Variant) -> void:
	config = sanitize(raw)
	if config["enabled"] and int(config["seed"]) == 0:
		config["seed"] = randi_range(1, 2147483646)
	if geometry.visual != null:
		build(geometry.visual, str(body.get("model_path")))
		geometry.rebuild(body)


func build(visual: Node3D, model_path: String) -> void:
	var old := visual.get_node_or_null(NODE_NAME)
	if old != null:
		old.free()
	if not config["enabled"] or _spent or not applies(model_path):
		return
	var holder := Node3D.new()
	holder.name = NODE_NAME
	visual.add_child(holder)
	for item: Dictionary in layout(int(config["count"]), int(config["seed"])):
		var packed := load(MODEL_DIR + str(item["model"])) as PackedScene
		if packed == null:
			continue
		var pivot := Node3D.new()
		pivot.position = item["position"]
		pivot.rotation.y = float(item["yaw"])
		pivot.add_child(packed.instantiate())
		holder.add_child(pivot)


## A shot plate with fruit either breaks (everything flies apart) or flips; the fruit always scatters.
## Returns true when this hit was consumed.
func hit(body: RigidBody3D, geometry: GEOMETRY, damage_state: PROP_DAMAGE, point: Vector3, direction: Vector3) -> bool:
	if _spent or not config["enabled"] or geometry.visual == null or damage_state.broken:
		return false
	var holder := geometry.visual.get_node_or_null(NODE_NAME) as Node3D
	if holder == null:
		return false
	_spent = true
	var breaks := randf() < 0.5
	var index := 0
	for child in geometry.visual.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		if mesh.mesh != null and mesh.is_visible_in_tree() and (breaks or holder.is_ancestor_of(mesh)):
			DAMAGE.spawn_piece(body, mesh, null, 0, index, direction, point, true)
			index += 1
	if breaks:
		damage_state.broken = true
		var world: Variant = body.get("effects_root")
		SFX.play(world if is_instance_valid(world) else body.get_parent(), &"glass_break", point)
		geometry.visual.hide()
		for shape: CollisionShape3D in geometry.shapes:
			shape.set_deferred("disabled", true)
		body.collision_layer = 0
		body.freeze = true
		return true
	holder.hide()
	holder.queue_free()
	geometry.rebuild(body)
	var side := direction.cross(Vector3.UP)
	body.freeze = false
	body.sleeping = false
	body.apply_central_impulse((Vector3.UP * 1.6 + direction.normalized() * 0.6) * body.mass)
	body.apply_torque_impulse(side.normalized() * body.mass * 0.2 if side.length() > 0.01 else Vector3.RIGHT * body.mass * 0.2)
	return true
