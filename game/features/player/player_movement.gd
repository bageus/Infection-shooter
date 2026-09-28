extends CharacterBody3D
const MUTATION_EFFECTS := preload("res://game/features/player/mutation_skill_effects.gd")
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
@export var camera_zoom_step: float = 1.5
@export var camera_min_distance: float = 9.0
@export var camera_max_distance: float = 24.0
@export var gravity_acceleration: float = 24.0
@export var max_health: float = 100.0
@export var max_armor: float = 100.0
@export var starting_antidotes: int = 2
@export var max_antidotes: int = 3
@onready var camera_rig: Node3D = $CameraRig
@onready var camera: Camera3D = $CameraRig/Camera3D
@onready var aim_pivot: Node3D = $AimPivot
@onready var body_visual: Node3D = $Body
@onready var weapons: Array[Node3D] = [$AimPivot/Pistol,$AimPivot/Uzi,$AimPivot/Shotgun,$AimPivot/GrenadeLauncher]
@onready var infection_runtime: Node = $InfectionRuntime
var health: float
var armor: float
var antidotes: int
var current_weapon_index: int = 0
var _roll_direction := Vector3.ZERO
var _roll_remaining: float = 0.0
var _roll_cooldown_remaining: float = 0.0
var _aim_point := Vector3.ZERO
var _camera_distance := 0.0
var _stun_remaining := 0.0
var _stun_intensity := 0.0
var _stun_rotation := 0
var _stun_ringing: AudioStreamPlayer
var _original_master_volume := 0.0
var mutation_effects: Node
var _mutation_menu_open := false
var _slot_weapons: Array[int] = [0, 1, 2]
var _emergency_key := false
func _ready() -> void:
	floor_snap_length = 0.45
	_camera_distance=camera.position.length()
	health=max_health
	armor=max_armor
	antidotes=starting_antidotes
	_select_weapon(0)
	mutation_effects = MUTATION_EFFECTS.new()
	add_child(mutation_effects)
	mutation_effects.call("configure", self, infection_runtime, weapons)
func _physics_process(delta: float) -> void:
	if _stun_remaining > 0.0:
		_stun_remaining = maxf(0.0, _stun_remaining - delta)
		if _stun_remaining == 0.0:
			camera_rig.position = Vector3.ZERO
			AudioServer.set_bus_volume_db(0, _original_master_volume)
			if is_instance_valid(_stun_ringing): _stun_ringing.stop()
	if absf(camera.position.length()-_camera_distance)>0.001:
		camera.position=camera.position.normalized()*lerpf(camera.position.length(),_camera_distance,1.0-exp(-8.0*delta))
	_roll_cooldown_remaining=maxf(0.0,_roll_cooldown_remaining-delta)
	if not _mutation_menu_open:
		_handle_actions()
	_update_camera(delta)
	_update_aim()
	_update_move(delta)
	var w:=get_current_weapon()
	if w != null and not _mutation_menu_open and _roll_remaining <= 0.0 and (Input.is_action_pressed("fire") if bool(w.call("wants_continuous_fire")) else Input.is_action_just_pressed("fire")):
		if int(w.call("get_magazine_ammo")) == 0:
			mutation_effects.call("refill_organic_magazine")
		w.call("try_fire_at", _aim_point)
func _unhandled_input(event: InputEvent) -> void:
	if get_tree().paused:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_camera_distance=clampf(_camera_distance-camera_zoom_step,camera_min_distance,camera_max_distance)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_camera_distance=clampf(_camera_distance+camera_zoom_step,camera_min_distance,camera_max_distance)
			get_viewport().set_input_as_handled()
func _handle_actions() -> void:
	if Input.is_action_just_pressed("weapon_1"): _select_weapon(0)
	elif Input.is_action_just_pressed("weapon_2"): _select_weapon(1)
	elif Input.is_action_just_pressed("weapon_3"): _select_weapon(2)
	elif Input.is_action_just_pressed("weapon_4") and _slot_weapons.has(3): _select_weapon(_slot_weapons.find(3))
	if Input.is_action_just_pressed("pickup_weapon"):
		var nearest: Node3D
		var best := 2.4
		for item in get_tree().get_nodes_in_group("weapon_pickups"):
			if item is Node3D:
				var distance := global_position.distance_to((item as Node3D).global_position)
				if distance < best:
					nearest = item as Node3D
					best = distance
		if nearest != null:
			nearest.call("claim", self)
	if Input.is_action_just_pressed("reload"):
		var w:=get_current_weapon()
		if w!=null: w.call("start_reload")
	if Input.is_action_just_pressed("antidote"): use_antidote()
	if Input.is_action_just_pressed("melee"): mutation_effects.call("melee")
func _select_weapon(index:int)->void:
	if index<0 or index>=_slot_weapons.size(): return
	var old:=get_current_weapon()
	if old!=null: old.call("cancel_reload")
	current_weapon_index=index
	for i in weapons.size(): weapons[i].visible=i==_slot_weapons[index]
func get_current_weapon()->Node3D:
	return weapons[_slot_weapons[current_weapon_index]]

func get_weapon_in_slot(index: int) -> int:
	return _slot_weapons[index] if index >= 0 and index < _slot_weapons.size() else -1

func pickup_weapon(index: int) -> bool:
	if index < 0 or index >= weapons.size() or _slot_weapons.has(index):
		return false
	var previous := _slot_weapons[current_weapon_index]
	if not get_tree().current_scene.has_method("drop_weapon_pickup"):
		return false
	var offset := camera.global_basis.x
	offset.y = 0.0
	get_tree().current_scene.call("drop_weapon_pickup", previous, global_position + offset.normalized() * 1.3)
	get_current_weapon().call("cancel_reload")
	_slot_weapons[current_weapon_index] = index
	_select_weapon(current_weapon_index)
	return true

func acquire_emergency_key() -> void:
	_emergency_key = true

func has_emergency_key() -> bool:
	return _emergency_key
func get_current_weapon_index()->int: return current_weapon_index
func take_damage(amount: float, damage_type: String = "physical") -> void:
	var remaining: float = mutation_effects.call("on_player_hit", maxf(amount, 0.0), damage_type)
	var absorbed:=minf(armor,remaining)
	armor-=absorbed
	remaining-=absorbed
	health=maxf(0.0,health-remaining)
	if health <= 0.0 and mutation_effects.call("survive_lethal"):
		health = 1.0
	if amount > 0.0: _spawn_floor_blood(amount)
func heal(amount:float)->float:
	var previous:=health
	if mutation_effects.call("enabled", "assimilation"):
		amount *= 1.25
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
func mutation_dash() -> void:
	_roll_direction = -aim_pivot.global_basis.z
	_roll_direction.y = 0.0
	_roll_direction = _roll_direction.normalized()
	_roll_remaining = 0.4
func mutation_enemy_killed(enemy: Node3D) -> void:
	mutation_effects.call("on_enemy_killed", enemy)
func get_mutation()->float:return infection_runtime.call("get_mutation")
func get_infection_skill(skill_id: String) -> bool:
	return bool(infection_runtime.call("has_skill", skill_id))
func _update_camera(delta: float) -> void:
	var turn := Input.get_axis("camera_left", "camera_right")
	if _stun_remaining > 0.0 and _stun_intensity > 0.35:
		turn = -turn
		camera_rig.position = Vector3(randf_range(-0.06, 0.06), randf_range(-0.04, 0.04), 0) * _stun_intensity
	camera_rig.rotate_y(deg_to_rad(turn * camera_rotation_speed * delta))

func apply_blast_stun(duration: float, intensity: float) -> void:
	if _stun_remaining <= 0.0:
		_original_master_volume = AudioServer.get_bus_volume_db(0)
	_stun_remaining = maxf(_stun_remaining, duration)
	_stun_intensity = clampf(intensity, 0.0, 1.0)
	_stun_rotation = randi_range(1, 3)
	AudioServer.set_bus_volume_db(0, _original_master_volume - 12.0 * _stun_intensity)
	if _stun_ringing == null:
		_stun_ringing = AudioStreamPlayer.new()
		_stun_ringing.name = "BlastRinging"
		add_child(_stun_ringing)
		var tone := AudioStreamWAV.new()
		tone.mix_rate = 22050
		tone.format = AudioStreamWAV.FORMAT_16_BITS
		tone.loop_mode = AudioStreamWAV.LOOP_FORWARD
		tone.loop_begin = 0
		tone.loop_end = 11025
		var samples := PackedByteArray()
		samples.resize(22050)
		for i in 11025:
			samples.encode_s16(i * 2, roundi(sin(float(i) * TAU * 730.0 / 22050.0) * 750.0))
		tone.data = samples
		_stun_ringing.stream = tone
	_stun_ringing.volume_db = -19.0 + 6.0 * _stun_intensity
	_stun_ringing.play()

func _exit_tree() -> void:
	if _stun_remaining > 0.0:
		AudioServer.set_bus_volume_db(0, _original_master_volume)


func _update_move(delta:float)->void:
	var d:=_move_direction()
	if _roll_remaining>0.0:
		_roll_remaining=maxf(0.0,_roll_remaining-delta);velocity.x=_roll_direction.x*roll_speed;velocity.z=_roll_direction.z*roll_speed
	elif Input.is_action_just_pressed("roll") and d.length_squared()>0.0001 and _roll_cooldown_remaining<=0.0:
		_roll_direction=d.normalized();_roll_remaining=roll_duration;_roll_cooldown_remaining=roll_cooldown
		mutation_effects.call("on_roll")
	else:
		var target:=d*(sprint_speed if Input.is_action_pressed("sprint") else move_speed) * float(mutation_effects.call("movement_multiplier"))
		var accel:=ground_acceleration if d.length_squared()>0.0001 else ground_deceleration
		velocity.x=move_toward(velocity.x,target.x,accel*delta);velocity.z=move_toward(velocity.z,target.z,accel*delta)
	velocity.y=0.0 if is_on_floor() else velocity.y-gravity_acceleration*delta
	move_and_slide()
	_push_chair_contacts()
	if _roll_remaining>0.0: _push_roll_contacts()
func _push_chair_contacts()->void:
	for i in get_slide_collision_count():
		var collision:=get_slide_collision(i)
		var collider:=collision.get_collider()
		if collider!=null and collider.has_method("push_from_character"):
			var movement:=Vector3(velocity.x,0.0,velocity.z)
			collider.call("push_from_character",global_position,movement)

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
	if _mutation_menu_open:
		return Vector3.ZERO
	var input:=Input.get_vector("move_left","move_right","move_up","move_down")
	if _stun_remaining > 0.0 and _stun_intensity > 0.25:
		input = input.rotated(float(_stun_rotation) * PI * 0.5)
	var f:Vector3=-camera.global_transform.basis.z;f.y=0;f=f.normalized()
	var r:Vector3=camera.global_transform.basis.x;r.y=0;r=r.normalized()
	var d:Vector3=r*input.x+f*-input.y
	return d.normalized() if d.length_squared()>1.0 else d
func _update_aim()->void:
	var mouse:=get_viewport().get_mouse_position()
	if _stun_remaining > 0.0 and _stun_intensity > 0.35:
		mouse.x = get_viewport().get_visible_rect().size.x - mouse.x
	var origin:=camera.project_ray_origin(mouse)
	var ray_end:=origin+camera.project_ray_normal(mouse)*200.0
	var query:=PhysicsRayQueryParameters3D.create(origin,ray_end,7)
	query.exclude=[get_rid()]
	var hit:=get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		_aim_point=hit.get("position")
	else:
		# Fallback to the gameplay floor so the cursor always has a world target.
		var direction:=camera.project_ray_normal(mouse)
		if absf(direction.y)>0.0001:
			var t:float=(0.0-origin.y)/direction.y
			_aim_point=origin+direction*maxf(t,0.0)
		else:
			_aim_point=ray_end
	var flat_direction:=_aim_point-global_position
	flat_direction.y=0.0
	if flat_direction.length_squared()>0.0001:
		var target_direction:=flat_direction.normalized()
		aim_pivot.look_at(aim_pivot.global_position+target_direction,Vector3.UP)
		body_visual.look_at(body_visual.global_position+target_direction,Vector3.UP)

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
