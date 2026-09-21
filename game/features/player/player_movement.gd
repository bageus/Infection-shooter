extends CharacterBody3D
@export var move_speed: float = 6.0
@export var sprint_speed: float = 9.0
@export var ground_acceleration: float = 18.0
@export var ground_deceleration: float = 13.0
@export var roll_speed: float = 13.0
@export var roll_duration: float = 0.24
@export var roll_cooldown: float = 0.65
@export var roll_push_strength: float = 8.5
@export var roll_push_radius: float = 1.25
@export var camera_rotation_speed: float = 95.0
@export var gravity_acceleration: float = 24.0
@export var max_health: float = 100.0
@export var max_armor: float = 100.0
@export var starting_antidotes: int = 2
@export var max_antidotes: int = 3
@onready var camera_rig: Node3D = $CameraRig
@onready var camera: Camera3D = $CameraRig/Camera3D
@onready var aim_pivot: Node3D = $AimPivot
@onready var weapons: Array[Node3D] = [$AimPivot/Pistol,$AimPivot/Uzi,$AimPivot/Shotgun]
@onready var infection_runtime: Node = $InfectionRuntime
var health: float
var armor: float
var antidotes: int
var current_weapon_index: int = 0
var _roll_direction := Vector3.ZERO
var _roll_remaining: float = 0.0
var _roll_cooldown_remaining: float = 0.0
func _ready() -> void:
	health=max_health
	armor=max_armor
	antidotes=starting_antidotes
	_select_weapon(0)
func _physics_process(delta: float) -> void:
	_roll_cooldown_remaining=maxf(0.0,_roll_cooldown_remaining-delta)
	_handle_actions()
	_update_camera(delta)
	_update_aim()
	_update_move(delta)
	var w:=get_current_weapon()
	if w != null and _roll_remaining <= 0.0 and Input.is_action_pressed("fire"):
		w.call("try_fire")
func _handle_actions() -> void:
	if Input.is_action_just_pressed("weapon_1"): _select_weapon(0)
	elif Input.is_action_just_pressed("weapon_2"): _select_weapon(1)
	elif Input.is_action_just_pressed("weapon_3"): _select_weapon(2)
	if Input.is_action_just_pressed("reload"):
		var w:=get_current_weapon()
		if w!=null: w.call("start_reload")
	if Input.is_action_just_pressed("antidote"): use_antidote()
func _select_weapon(index:int)->void:
	if index<0 or index>=weapons.size(): return
	var old:=get_current_weapon()
	if old!=null: old.call("cancel_reload")
	current_weapon_index=index
	for i in weapons.size(): weapons[i].visible=i==index
func get_current_weapon()->Node3D:
	return weapons[current_weapon_index]
func get_current_weapon_index()->int: return current_weapon_index
func take_damage(amount:float)->void:
	var remaining:=maxf(amount,0.0)
	var absorbed:=minf(armor,remaining)
	armor-=absorbed
	remaining-=absorbed
	health=maxf(0.0,health-remaining)
	if amount > 0.0: _spawn_floor_blood(amount)
func heal(amount:float)->float:
	var previous:=health
	health=minf(max_health,health+maxf(amount,0.0))
	return health-previous
func use_antidote()->bool:
	if antidotes<=0:return false
	var used:bool=infection_runtime.call("use_antidote")
	if used:antidotes-=1
	return used
func add_ammo_to_current_weapon(amount:int)->int:return get_current_weapon().call("add_reserve_ammo",amount)
func add_ammo_for_weapon(weapon_name:String,amount:int)->int:
	for weapon in weapons:
		if weapon.call("get_weapon_name")==weapon_name:
			return int(weapon.call("add_reserve_ammo",amount))
	return 0
func add_antidote(amount:int=1)->bool:
	if antidotes>=max_antidotes:return false
	antidotes=mini(max_antidotes,antidotes+maxi(amount,0))
	return true
func absorb_mutagen(delta_seconds:float)->float:return infection_runtime.call("absorb_mutagen",delta_seconds)
func get_mutation()->float:return infection_runtime.call("get_mutation")
func _update_camera(delta:float)->void:camera_rig.rotate_y(deg_to_rad(Input.get_axis("camera_left","camera_right")*camera_rotation_speed*delta))
func _update_move(delta:float)->void:
	var d:=_move_direction()
	if _roll_remaining>0.0:
		_roll_remaining=maxf(0.0,_roll_remaining-delta);velocity.x=_roll_direction.x*roll_speed;velocity.z=_roll_direction.z*roll_speed
	elif Input.is_action_just_pressed("roll") and d.length_squared()>0.0001 and _roll_cooldown_remaining<=0.0:
		_roll_direction=d.normalized();_roll_remaining=roll_duration;_roll_cooldown_remaining=roll_cooldown
	else:
		var target:=d*(sprint_speed if Input.is_action_pressed("sprint") else move_speed)
		var accel:=ground_acceleration if d.length_squared()>0.0001 else ground_deceleration
		velocity.x=move_toward(velocity.x,target.x,accel*delta);velocity.z=move_toward(velocity.z,target.z,accel*delta)
	velocity.y=0.0 if is_on_floor() else velocity.y-gravity_acceleration*delta
	move_and_slide()
	if _roll_remaining>0.0: _push_roll_contacts()
func _push_roll_contacts()->void:
	for i in get_slide_collision_count():
		var collision:=get_slide_collision(i)
		var collider:=collision.get_collider()
		if collider!=null and collider.has_method("apply_player_push"):
			var direction:Vector3=collider.global_position-global_position
			direction.y=0.0
			if direction.length_squared()<0.001: direction=_roll_direction
			collider.call("apply_player_push",direction.normalized(),roll_push_strength)
	for node in get_tree().get_nodes_in_group("infected"):
		if not node is Node3D: continue
		var enemy:=node as Node3D
		var offset:Vector3=enemy.global_position-global_position
		offset.y=0.0
		if offset.length()<=roll_push_radius and enemy.has_method("apply_player_push"):
			var direction:Vector3=offset.normalized() if offset.length_squared()>0.001 else _roll_direction
			enemy.call("apply_player_push",direction,roll_push_strength)

func _move_direction()->Vector3:
	var input:=Input.get_vector("move_left","move_right","move_up","move_down")
	var f:Vector3=-camera.global_transform.basis.z;f.y=0;f=f.normalized()
	var r:Vector3=camera.global_transform.basis.x;r.y=0;r=r.normalized()
	var d:Vector3=r*input.x+f*-input.y
	return d.normalized() if d.length_squared()>1.0 else d
func _update_aim()->void:
	var delta:=get_viewport().get_mouse_position()-get_viewport().get_visible_rect().size*0.5
	if delta.length_squared()<=4:return
	var r:Vector3=camera.global_transform.basis.x;r.y=0;r=r.normalized()
	var f:Vector3=-camera.global_transform.basis.z;f.y=0;f=f.normalized()
	var d:=r*delta.x+f*-delta.y
	if d.length_squared()>0.0001:aim_pivot.look_at(aim_pivot.global_position+d.normalized(),Vector3.UP)

func _spawn_floor_blood(amount:float)->void:
	var count:=clampi(ceili(amount/8.0),2,6)
	for i in count:
		var mark:=MeshInstance3D.new()
		var mesh:=ImmediateMesh.new()
		var material:=StandardMaterial3D.new()
		material.albedo_color=Color(0.34,0.0,0.015,0.92);material.roughness=1.0;material.cull_mode=BaseMaterial3D.CULL_DISABLED
		mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES,material)
		var points:=randi_range(7,11)
		var width:=randf_range(0.08,0.24)
		var height:=width*randf_range(0.45,1.7)
		for p in points:
			var a0:=TAU*float(p)/points;var a1:=TAU*float(p+1)/points
			var r0:=randf_range(0.45,1.2);var r1:=randf_range(0.45,1.2)
			mesh.surface_add_vertex(Vector3.ZERO)
			mesh.surface_add_vertex(Vector3(cos(a0)*width*r0,sin(a0)*height*r0,0))
			mesh.surface_add_vertex(Vector3(cos(a1)*width*r1,sin(a1)*height*r1,0))
		mesh.surface_end();mark.mesh=mesh;get_tree().current_scene.add_child(mark)
		mark.global_position=Vector3(global_position.x,0.025,global_position.z)+Vector3(randf_range(-0.5,0.5),0,randf_range(-0.5,0.5))
		mark.rotation_degrees=Vector3(-90,randf_range(0,360),0)
