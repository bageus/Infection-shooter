extends Node3D

const FALL_DEATH_Y: float = -4.0

@onready var player: Node3D = $Gameplay/Player
@onready var enemies: Node3D = $Gameplay/Enemies
@onready var game_over: Control = $GameOver

var _ended: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	game_over.process_mode = Node.PROCESS_MODE_ALWAYS
	game_over.hide()
	for enemy in enemies.get_children():
		if enemy.has_method("set_target"):
			enemy.call("set_target", player)


func _process(_delta: float) -> void:
	if _ended:
		return
	if player.global_position.y < FALL_DEATH_Y:
		_end_run("YOU FELL OUTSIDE THE FLOOR")
		return
	var health_value: Variant = player.get("health")
	if health_value != null and float(health_value) <= 0.0:
		_end_run("MISSION FAILED")


func _end_run(reason: String) -> void:
	_ended = true
	$GameOver/Panel/VBox/Reason.text = reason
	game_over.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true


func _on_restart_pressed() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _on_exit_pressed() -> void:
	get_tree().paused = false
	get_tree().quit()
