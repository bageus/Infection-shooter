extends Node3D

const TILE_SCENE := preload("res://game/presentation/office_floor/public/structural/base_floor_tile.tscn")

@export var floor_size := Vector2(80.0, 60.0)
@export var tile_step := 2.0
@export var tile_y := 0.001

func _ready() -> void:
	_build_tiles()

func _build_tiles() -> void:
	for child in get_children():
		child.queue_free()
	var columns := ceili(floor_size.x / tile_step)
	var rows := ceili(floor_size.y / tile_step)
	var start_x := -floor_size.x * 0.5 + tile_step * 0.5
	var start_z := -floor_size.y * 0.5 + tile_step * 0.5
	for z in rows:
		for x in columns:
			var tile := TILE_SCENE.instantiate() as Node3D
			add_child(tile)
			tile.position = Vector3(start_x + x * tile_step, tile_y, start_z + z * tile_step)
