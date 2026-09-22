extends Node3D

const FALL_DEATH_Y: float = -4.0
const PlanningMode = preload("res://game/bootstrap/app/planning_mode.gd")
const ChunkStreamer = preload("res://game/bootstrap/app/chunk_streamer.gd")
const PlanningLighting = preload("res://game/bootstrap/app/planning_lighting.gd")

@onready var player: Node3D = $Gameplay/Player
@onready var enemies: Node3D = $Gameplay/Enemies
@onready var game_over: Control = $GameOver
@onready var pause_menu: Control = $PauseMenu
@onready var planning_ui: Control = $PlanningUI
@onready var planning_root: Node3D = $PlanningObjects
@onready var gameplay: Node3D = $Gameplay
@onready var mutation_choice: Control = $MutationChoice
@onready var infection_runtime: Node = $Gameplay/Player/InfectionRuntime

var _ended := false
var _pause_open := false
var planning_mode: Node
var chunk_streamer: Node
var planning_lighting: Node


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	game_over.process_mode = Node.PROCESS_MODE_ALWAYS
	pause_menu.process_mode = Node.PROCESS_MODE_ALWAYS
	planning_ui.process_mode = Node.PROCESS_MODE_ALWAYS
	game_over.hide()
	pause_menu.hide()
	planning_ui.hide()
	mutation_choice.hide()
	mutation_choice.process_mode = Node.PROCESS_MODE_ALWAYS
	infection_runtime.ability_choice_requested.connect(_on_mutation_choice_requested)
	infection_runtime.ability_changed.connect(_on_mutation_ability_changed)
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
	planning_lighting = PlanningLighting.new()
	planning_lighting.name = "PlanningLighting"
	add_child(planning_lighting)
	planning_lighting.setup($WorldEnvironment)
	for enemy in enemies.get_children():
		if enemy.has_method("set_target"):
			enemy.call("set_target", player)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
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
	if player.global_position.y < FALL_DEATH_Y:
		_end_run("YOU FELL OUTSIDE THE FLOOR")
		return
	var health_value: Variant = player.get("health")
	if health_value != null and float(health_value) <= 0.0:
		_end_run("MISSION FAILED")


func _open_pause_menu() -> void:
	_pause_open = true
	pause_menu.show()
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
	if mutation_choice.visible:
		return
	mutation_choice.show()
	mutation_choice.move_to_front()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_mutation_ability_changed(choice: int) -> void:
	if choice == 0:
		mutation_choice.hide()
		if not _pause_open and not planning_mode.active and not _ended:
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
	$GameOver/Panel/VBox/Reason.text = reason
	game_over.show()
	game_over.move_to_front()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true


func _on_restart_pressed() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _on_exit_pressed() -> void:
	get_tree().paused = false
	get_tree().quit()
