extends Control
@export var player_path:NodePath
@export var enemies_path:NodePath
@export var source_path:NodePath
var player:Node3D
var enemies:Node
var source:Node3D
func _ready()->void:
	player=get_node(player_path);enemies=get_node(enemies_path);source=get_node(source_path)
func _process(_delta:float)->void:queue_redraw()
func _draw()->void:
	var c:=size*0.5;var rad:=minf(size.x,size.y)*0.43
	draw_circle(c,rad,Color(0.01,0.07,0.11,0.94));draw_arc(c,rad,0,TAU,64,Color(0.1,0.85,1,1),2)
	draw_line(c+Vector2(-rad,0),c+Vector2(rad,0),Color(0.1,0.4,0.5,0.6));draw_line(c+Vector2(0,-rad),c+Vector2(0,rad),Color(0.1,0.4,0.5,0.6))
	draw_circle(c,5,Color(0.1,0.95,1,1))
	for e in enemies.get_children():
		if e is Node3D:_blip(c,rad,e.global_position,Color(1,0.1,0.08,1),4)
	_blip(c,rad,source.global_position,Color(0.2,1,0.1,1),6)
func _blip(c:Vector2,rad:float,p:Vector3,col:Color,r:float)->void:
	var o:=Vector2(p.x-player.global_position.x,p.z-player.global_position.z)/18.0*rad
	if o.length()>rad-5:o=o.normalized()*(rad-5)
	draw_circle(c+o,r,col)
