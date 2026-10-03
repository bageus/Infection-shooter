extends RefCounted
## Visual reactions of a destructible environment prop: a short shudder on
## surviving hits and a dust puff on breaking. Presentation only; the visual is
## always restored before the owner rebuilds its collision shapes.

const DEBRIS := preload("res://game/presentation/office_floor/debris_lifecycle.gd")
const SHUDDER_DISTANCE := 0.025

var _host: Node3D
var _visual: Node3D
var _rest := Vector3.ZERO
var _tween: Tween


func setup(host: Node3D, visual: Node3D) -> void:
	_host = host
	_visual = visual
	_rest = visual.position


func shudder(direction: Vector3) -> void:
	if _visual == null:
		return
	cancel()
	var kick := (_host.global_basis.inverse() * Vector3(direction.x, 0.0, direction.z)).normalized() * SHUDDER_DISTANCE
	_tween = _host.create_tween()
	_tween.tween_property(_visual, "position", _rest + kick, 0.04)
	_tween.tween_property(_visual, "position", _rest - kick * 0.4, 0.06)
	_tween.tween_property(_visual, "position", _rest, 0.06)


func cancel() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if is_instance_valid(_visual):
		_visual.position = _rest


func break_dust(shape_meshes: Array[MeshInstance3D]) -> void:
	var bounds := AABB()
	var found := false
	for mesh in shape_meshes:
		if not is_instance_valid(mesh):
			continue
		var mesh_bounds: AABB = mesh.global_transform * mesh.get_aabb()
		bounds = mesh_bounds if not found else bounds.merge(mesh_bounds)
		found = true
	if found:
		DEBRIS.dust_puff(_host, bounds.get_center() - Vector3(0.0, bounds.size.y * 0.2, 0.0), bounds.size.length())
