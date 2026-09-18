extends Node3D

@onready var player: Node3D = $Gameplay/Player
@onready var enemies: Node3D = $Gameplay/Enemies


func _ready() -> void:
	for enemy in enemies.get_children():
		if enemy.has_method("set_target"):
			enemy.call("set_target", player)
