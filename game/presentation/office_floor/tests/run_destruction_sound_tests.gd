extends SceneTree
## Verify actual damage/selection commands emit once and voices survive the prop.
const PROP := preload("res://game/presentation/office_floor/public/props/environment_prop.tscn")
const PHYSICAL := preload("res://game/presentation/office_floor/physical_prop.gd")
const PLAYER := preload("res://game/features/player/public/player.tscn")
const BURST := preload("res://game/presentation/office_floor/extinguisher_burst.tscn")
const BREAK_SOUND := preload("res://game/presentation/office_floor/prop_break_sound.gd")
var failures := 0
var stage: Node3D
var effects: Node3D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	effects = Node3D.new()
	stage.add_child(effects)
	await _environment("res://models/objects/enviroments/07/07_table_longest.glb", &"break_furniture")
	await _environment("res://models/objects/enviroments/04/04_cardboard_box_closed.glb", &"break_cardboard")
	await _environment("res://models/objects/enviroments/02/02_microwave_destructible.glb", &"break_electronics")
	await _environment("res://models/objects/enviroments/02/02_kittle_destructible.glb", &"break_electronics")
	await _lamp()
	await _physical_crate()
	await _weapon()
	_check(BREAK_SOUND.event_for("02_kettle.glb", "wood") == &"break_electronics", "Appliances use electrical sounds regardless of numbered group")
	var burst := BURST.instantiate()
	_check(burst.get_node_or_null("Pop") == null, "Burst has no unused Pop node")
	burst.free()
	stage.queue_free()
	await process_frame
	await process_frame
	print("Destruction sound tests: %d failure(s)." % failures)
	quit(failures)


func _count(event: StringName) -> int:
	return get_node_count_in_group(StringName("sfx_" + String(event)))


func _clear_voices() -> void:
	for node in get_nodes_in_group(&"sfx_voice"):
		node.queue_free()
	await process_frame


func _environment(path: String, event: StringName) -> void:
	var prop := PROP.instantiate() as RigidBody3D
	prop.set("model_path", path)
	prop.freeze = true
	prop.call("configure_world", effects, null)
	stage.add_child(prop)
	prop.call("take_projectile_hit", 1.0, Vector3.ZERO, Vector3.UP, Vector3.FORWARD, "PISTOL")
	await process_frame
	_check(_count(event) == 0, "Surviving hit is not destruction: " + path)
	prop.call("take_projectile_hit", 5000.0, Vector3.ZERO, Vector3.UP, Vector3.FORWARD, "GRENADE")
	await process_frame
	_check(_count(event) == 1, "Actual destruction emits one correct cue: " + path)
	prop.call("take_projectile_hit", 5000.0, Vector3.ZERO, Vector3.UP, Vector3.FORWARD, "GRENADE")
	await process_frame
	_check(_count(event) == 1, "Already broken prop does not repeat cue: " + path)
	prop.queue_free()
	await process_frame
	_check(_count(event) == 1, "Destruction audio survives deleting the prop")
	await _clear_voices()


func _lamp() -> void:
	var lamp := PROP.instantiate() as RigidBody3D
	lamp.set("model_path", "res://models/objects/enviroments/05/05_lamp.glb")
	lamp.call("configure_world", effects, null)
	stage.add_child(lamp)
	lamp.call("take_projectile_hit", 1.0, Vector3.ZERO, Vector3.UP, Vector3.FORWARD, "PISTOL")
	lamp.call("take_projectile_hit", 1.0, Vector3.ZERO, Vector3.UP, Vector3.FORWARD, "PISTOL")
	_check(_count(&"break_lamp") == 1, "Lamp goes out audibly once")
	lamp.queue_free()
	await _clear_voices()


func _physical_crate() -> void:
	var crate := RigidBody3D.new()
	crate.set_script(PHYSICAL)
	crate.name = "WoodCrate"
	crate.call("configure_world", effects, null)
	stage.add_child(crate)
	crate.call("take_melee_hit", 5000.0, Vector3.ZERO, Vector3.FORWARD)
	crate.call("take_melee_hit", 5000.0, Vector3.ZERO, Vector3.FORWARD)
	_check(_count(&"break_wood") == 1, "Melee destruction of a wooden crate is heard once")
	await process_frame
	_check(_count(&"break_wood") == 1, "Crate sound survives queued deletion")
	await _clear_voices()


func _weapon() -> void:
	var actor := PLAYER.instantiate() as CharacterBody3D
	stage.add_child(actor)
	actor.set_physics_process(false)
	_check(_count(&"weapon_switch") == 0, "Initial equipment is silent")
	actor.call("select_weapon_slot", 0)
	_check(_count(&"weapon_switch") == 0, "Selecting current slot is silent")
	actor.call("select_weapon_slot", 1)
	_check(_count(&"weapon_switch") == 1, "Actual slot change plays handling sound")
	actor.call("select_weapon_slot", 1)
	actor.call("select_weapon_slot", 99)
	_check(_count(&"weapon_switch") == 1, "Same and invalid slots do not repeat sound")
	actor.queue_free()
	await _clear_voices()


func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
