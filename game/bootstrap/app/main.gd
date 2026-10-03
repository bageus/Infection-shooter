extends Node3D

const WORLD_BINDINGS := preload("res://game/bootstrap/app/world_bindings.gd")
const IMPACT_POOL := preload("res://game/features/combat/public/impact_effects.gd")

const FALL_DEATH_Y: float = -4.0
const PlanningMode = preload("res://game/bootstrap/app/planning_mode.gd")
const ChunkStreamer = preload("res://game/bootstrap/app/chunk_streamer.gd")
const TEST_CLOUD := preload("res://game/features/infection_source/public/mutagen_cloud.tscn")
const MUTATION_UI := preload("res://game/bootstrap/app/mutation_tree_ui.gd")
const BLOOD_EFFECTS := preload("res://game/presentation/office_floor/public/blood_effects_3d.tscn")
const MISSION_LAYOUT := preload("res://game/bootstrap/app/mission_layout.gd")

@onready var player: Node3D = $Gameplay/Player
@onready var enemies: Node3D = $Gameplay/Enemies
@onready var game_over: Control = $Menus/GameOver
@onready var pause_menu: Control = $Menus/PauseMenu
@onready var planning_ui: Control = $PlanningUI
@onready var planning_root: Node3D = $PlanningObjects
@onready var gameplay: Node3D = $Gameplay
@onready var mutation_choice: Control = $MutationChoice
@onready var infection_runtime: Node = $Gameplay/Player/InfectionRuntime

var world_bindings: RefCounted
var mission_objects: Node3D
var impact_pool: Node3D

var _ended := false
var _pause_open := false
var planning_mode: Node
var chunk_streamer: Node
var planning_lighting: Node
var mutation_tree_ui: CanvasLayer
var mission_layout: Node3D
var blood_effects: Node3D


func _ready() -> void:
	get_window().title = "Infection Shooter"
	process_mode = Node.PROCESS_MODE_PAUSABLE
	game_over.process_mode = Node.PROCESS_MODE_ALWAYS
	pause_menu.process_mode = Node.PROCESS_MODE_ALWAYS
	planning_ui.process_mode = Node.PROCESS_MODE_ALWAYS
	game_over.connect("action_requested", _on_menu_action)
	pause_menu.connect("action_requested", _on_menu_action)
	game_over.hide()
	pause_menu.hide()
	planning_ui.hide()
	_setup_world_bindings()
	mutation_choice.hide()
	mutation_choice.process_mode = Node.PROCESS_MODE_ALWAYS
	infection_runtime.ability_choice_requested.connect(_on_mutation_choice_requested)
	infection_runtime.ability_changed.connect(_on_mutation_ability_changed)
	infection_runtime.defeated.connect(_on_mutation_defeated)
	mutation_tree_ui = MUTATION_UI.new()
	add_child(mutation_tree_ui)
	mutation_tree_ui.call("configure", infection_runtime)
	$MutationChoice/Panel/VBox/Choices/FastHands.pressed.connect(_choose_fast_hands)
	$MutationChoice/Panel/VBox/Choices/LegMutation.pressed.connect(_choose_leg_mutation)
	$MutationChoice/Panel/VBox/Choices/EnhancedAmmo.pressed.connect(_choose_enhanced_ammo)
	planning_mode = PlanningMode.new()
	add_child(planning_mode)
	planning_mode.process_mode = Node.PROCESS_MODE_ALWAYS
	planning_mode.setup(self, planning_root, planning_ui)
	chunk_streamer = ChunkStreamer.new()
	chunk_streamer.name = "ChunkStreamer"
	add_child(chunk_streamer)
	chunk_streamer.setup(player, [planning_root, $Structure])
	planning_lighting = $PlanningLighting
	planning_lighting.setup($WorldEnvironment, $PlanningUI/Panel/VBox/LightingPreview, $PlanningUI/Panel/VBox/LocalLights)
	mission_layout = MISSION_LAYOUT.new()
	mission_layout.name = "MissionLayout"
	gameplay.add_child(mission_layout)
	mission_layout.call("setup", self, player, infection_runtime)
	var mutagen_test_cloud := TEST_CLOUD.instantiate()
	mutagen_test_cloud.name = "PermanentTestMutagen"
	mutagen_test_cloud.set("permanent", true)
	gameplay.add_child(mutagen_test_cloud)
	mutagen_test_cloud.global_position = Vector3.ZERO
	mutagen_test_cloud.call("activate")
	_setup_blood_effects()
	for enemy in enemies.get_children():
		if enemy.has_method("set_target"):
			enemy.call("set_target", player)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if mutation_tree_ui != null and bool(mutation_tree_ui.call("is_tree_open")):
			mutation_tree_ui.call("close_tree")
			get_viewport().set_input_as_handled()
			return
		if planning_mode.active:
			planning_mode.exit()
			return
		if _ended:
			return
		if _pause_open:
			_resume_game()
		else:
			_open_pause_menu()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if _ended or _pause_open or planning_mode.active:
		return
	if mission_layout.call("goal_reached", player.global_position):
		_end_run("MISSION COMPLETE")
		return
	if bool(infection_runtime.call("is_defeated")):
		_end_run("MUTATION OVERTOOK YOU")
		return
	if player.global_position.y < FALL_DEATH_Y:
		_end_run("YOU FELL OUTSIDE THE FLOOR")
		return
	var health_value: Variant = player.get("health")
	if health_value != null and float(health_value) <= 0.0:
		_end_run("MISSION FAILED")


func _open_pause_menu() -> void:
	_pause_open = true
	pause_menu.call("show_screen", "pause")
	pause_menu.move_to_front()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _resume_game() -> void:
	_pause_open = false
	pause_menu.hide()
	get_tree().paused = false


func _on_resume_pressed() -> void:
	chunk_streamer.set_runtime_enabled(true)
	_resume_game()


func _on_planning_pressed() -> void:
	chunk_streamer.set_runtime_enabled(false)
	_pause_open = false
	pause_menu.hide()
	planning_mode.enter()


func _on_mutation_choice_requested() -> void:
	# Keep the older single-choice runtime compatible with saved games.
	infection_runtime.call("select_ability", 1)
	# Only skill_available opens the tree; legacy reactivation must not prompt.


func _on_mutation_ability_changed(choice: int) -> void:
	if choice == 0:
		mutation_choice.hide()
		if not _pause_open and not planning_mode.active and not _ended and not bool(mutation_tree_ui.call("is_tree_open")):
			get_tree().paused = false


func _select_mutation(choice: int) -> void:
	if infection_runtime.call("select_ability", choice):
		mutation_choice.hide()
		get_tree().paused = false


func _choose_fast_hands() -> void:
	_select_mutation(1)


func _choose_leg_mutation() -> void:
	_select_mutation(2)


func _choose_enhanced_ammo() -> void:
	_select_mutation(3)


func _end_run(reason: String) -> void:
	_ended = true
	var kind := "complete" if reason == "MISSION COMPLETE" else "failed"
	var reason_key: String = {"MUTATION OVERTOOK YOU": "failedMutation",
		"YOU FELL OUTSIDE THE FLOOR": "failedFall", "MISSION FAILED": "failedHealth"}.get(reason, "")
	game_over.call("show_screen", kind, reason_key)
	game_over.move_to_front()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true


func drop_weapon_pickup(index: int, world_position: Vector3) -> bool:
	if not is_instance_valid(mission_layout):
		return false
	return bool(mission_layout.call("spawn_weapon", index, world_position))


func _on_menu_action(action: String) -> void:
	match action:
		"resume":
			_on_resume_pressed()
		"planning":
			_on_planning_pressed()
		"restart", "start":
			_on_restart_pressed()
		"main", "quit":
			get_tree().paused = false
			get_tree().change_scene_to_file("res://game/bootstrap/app/menu/front_end.tscn")


func _on_restart_pressed() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _on_exit_pressed() -> void:
	get_tree().paused = false
	get_tree().quit()


func _setup_blood_effects() -> void:
	blood_effects = BLOOD_EFFECTS.instantiate() as Node3D
	add_child(blood_effects)
	var blood_surfaces: Array[Node] = [$Structure, $Floor, $FloorBody, planning_root]
	blood_effects.call("configure_environment", blood_surfaces)
	enemies.child_entered_tree.connect(_bind_enemy_blood)
	for enemy in enemies.get_children():
		_bind_enemy_blood(enemy)


func _bind_enemy_blood(enemy: Node) -> void:
	bind_world_object(enemy)
	if blood_effects == null or not enemy.has_signal("projectile_blood"):
		return
	var bindings := {
		"projectile_blood": "splatter_hit", "blood_wounded": "small_stain",
		"wounded_moved": "drops_trail", "body_dragged": "smear_drag", "blood_death": "death_pool",
		"limb_severed": "severed_burst"
	}
	for event in bindings:
		if not enemy.has_signal(event):
			continue
		var callback := Callable(blood_effects, bindings[event])
		if not enemy.is_connected(event, callback):
			enemy.connect(event, callback)
	enemy.set("blood_drop_distance", blood_effects.call("movement_spacing"))


func _on_mutation_defeated() -> void:
	if _ended:
		return
	if mutation_tree_ui != null and mutation_tree_ui.call("is_tree_open"):
		mutation_tree_ui.call("close_tree")
	_end_run("MUTATION OVERTOOK YOU")


func _setup_world_bindings() -> void:
	mission_objects = Node3D.new()
	mission_objects.name = "MissionObjects"
	add_child(mission_objects)
	impact_pool = Node3D.new()
	impact_pool.name = "ImpactEffects"
	impact_pool.set_script(IMPACT_POOL)
	add_child(impact_pool)
	world_bindings = WORLD_BINDINGS.new(mission_objects, impact_pool, player, drop_weapon_pickup)
	world_bindings.call("bind_scene", player)
	for branch in [$Structure, planning_root, enemies]:
		world_bindings.call("bind_scene", branch)


func bind_world_object(node: Node) -> void:
	if world_bindings != null:
		world_bindings.call("bind_scene", node)
