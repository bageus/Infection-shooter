extends Node3D

const BEACON := preload("res://game/features/pickups/public/pickup_beacon.gd")
const MODEL := "res://models/objects/pickups/modern_key.glb"
const GOLD := Color(0.95, 0.7, 0.16)
const HOVER := 0.3

var _base_y := 0.0
var _elapsed := 0.0
var _runtime_active := false
var _art: Node3D
var _beacon: Node3D


func _ready() -> void:
	add_to_group("hidden_outline")
	add_to_group("mission_key")
	_art = Node3D.new()
	add_child(_art)
	var golden := StandardMaterial3D.new()
	golden.albedo_color = GOLD
	golden.metallic = 0.85
	golden.roughness = 0.24
	golden.emission_enabled = true
	golden.emission = GOLD
	golden.emission_energy_multiplier = 0.25
	# Flat modern key (Blender, models/objects/pickups): rounded head with a hole, blade with bit cuts.
	var model := (load(MODEL) as PackedScene).instantiate() as Node3D
	for mesh in model.find_children("*", "MeshInstance3D"):
		(mesh as MeshInstance3D).material_override = golden
		(mesh as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_art.add_child(model)
	_art.scale = Vector3.ONE * 1.2
	# The beacon keeps its orientation while the key spins; its arrow waits for reveal_arrow().
	_beacon = BEACON.make(GOLD, 0.7, 1.15, 0.9)
	_beacon.call("set_arrow_visible", false)
	add_child(_beacon)


# Dropped keys hover at the spot they land on, so nothing is snapped to the floor.
func settle_on_floor() -> void:
	pass


# The mission calls this once the player has searched for a while; the arrow then blinks above the key.
func reveal_arrow() -> void:
	_beacon.call("set_arrow_visible", true)


func _process(delta: float) -> void:
	if not _runtime_active:
		# The mission layout moves the key after _ready: hover above its final floor spot.
		_base_y = global_position.y + HOVER
		_runtime_active = true
	_elapsed += delta
	global_position.y = _base_y + sin(_elapsed * 1.7) * 0.07
	_art.rotation.y += delta * 0.9
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player != null and player.global_position.distance_to(global_position) <= 1.35:
		player.call("acquire_emergency_key")
		queue_free()
