extends Node3D

const TILE_SCENE := preload("res://game/presentation/office_floor/public/structural/base_floor_tile.tscn")

@export var floor_size := Vector2(80.0, 60.0)
@export var tile_step := 2.0
@export var tile_y := 0.001
var openings: Array[Rect2] = []

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
			var tile_position := Vector2(start_x + x * tile_step, start_z + z * tile_step)
			var tile_area := Rect2(tile_position - Vector2.ONE * tile_step * 0.5, Vector2.ONE * tile_step)
			var intersects_opening := false
			for opening in openings:
				if opening.intersects(tile_area):
					intersects_opening = true
					break
			if not intersects_opening:
				_add_tile(tile_position, 1.0)
				continue
			for sub_z in 4:
				for sub_x in 4:
					var center := tile_area.position + Vector2(sub_x + 0.5, sub_z + 0.5) * (tile_step / 4.0)
					var covered := false
					for opening in openings:
						if opening.has_point(center):
							covered = true
							break
					if not covered:
						_add_tile(center, 0.25)


func _add_tile(center: Vector2, tile_scale: float) -> void:
	var tile := TILE_SCENE.instantiate() as Node3D
	add_child(tile)
	tile.position = Vector3(center.x, tile_y, center.y)
	tile.scale = Vector3(tile_scale, 1.0, tile_scale)


func set_stair_openings(areas: Array[Rect2]) -> void:
	if openings == areas:
		return
	openings = areas.duplicate()
	_build_tiles()
