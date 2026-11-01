extends CharacterBody3D

const MUTATION_BALANCE := preload("res://game/features/infection/public/mutation_balance.gd")
const CONSUMABLES := preload("res://game/features/player/player_consumables.gd")
const HERO_START := preload("res://game/features/player/hero_spawn_start.gd")

signal projectile_blood(position: Vector3, direction: Vector3, weapon: String, excluded: Array[RID], source_id: int)
signal blood_wounded(position: Vector3, excluded: Array[RID])
signal wounded_moved(previous: Vector3, current: Vector3, excluded: Array[RID])
signal blood_death(position: Vector3, excluded: Array[RID], death_id: int)
var blood_drop_distance := 0.45
var _blood_motion_start := Vector3.ZERO
## Health lost to damage and not yet healed. Raising max health leaves a gap
## below the cap that is not a wound, so only this makes the player bleed.
var _wound := 0.0

signal blast_stun_started(duration: float, intensity: float)
signal blast_stun_ended()
## Health actually restored (after caps and skill bonuses); source is
## &"medkit" for medkit pickups and empty for other healing.
@warning_ignore("unused_signal")
signal healed(amount: float, source: StringName)
var _antidote_action := preload("res://game/features/player/player_antidote.gd").new()

const CONTROL_LOSS := preload("res://game/features/player/mutation_control_loss.gd")
const MUTATION_EFFECTS := preload("res://game/features/player/mutation_skill_effects.gd")
const SCOPE_RAISE := preload("res://game/features/player/scope_raise_state.gd")
const WEAPON_STANCE := preload("res://game/features/player/player_weapon_stance.gd")
const ANIMATION_SELECTION := preload("res://game/features/player/player_animation_selection.gd")
const PLAYER_AUDIO := preload("res://game/features/player/player_audio.gd")
const HEAL_FEEDBACK := preload("res://game/features/player/player_heal_feedback.gd")
@export var move_speed: float = 5.4
var _walk_speed_multiplier := 1.0
@export var sprint_speed: float = 8.1
## Body strength for pushing items (prop_weight_v1); 1.0 moves up to 22 kg.
@export var push_strength: float = 1.0
var _intended_motion := Vector3.ZERO
@export var ground_acceleration: float = 18.0
@export var ground_deceleration: float = 13.0
## The dodge plays a hips-and-legs animation (ADR-0044), so it lasts long
## enough to read: about the same distance as before (~3.1 m) at a slower pace.
@export var roll_speed: float = 5.7
@export var roll_duration: float = 0.55
@export var roll_cooldown: float = 0.65
## Seconds from the start of a dodge roll during which no damage lands.
@export var roll_iframes: float = 0.35
var _iframes_remaining: float = 0.0
const MUTATION_DASH_SPEED := 13.0
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
@export var max_antidotes: int = 5
@onready var camera_rig: Node3D = $CameraRig
@onready var camera: Camera3D = $CameraRig/Camera3D
@onready var aim_pivot: Node3D = $AimPivot
@onready var body_visual: Node3D = $Body
@onready var weapons: Array[Node3D] = [$AimPivot/Pistol,$AimPivot/Uzi,$AimPivot/Shotgun,$AimPivot/GrenadeLauncher,$AimPivot/AkRifle,$AimPivot/M4Rifle,$AimPivot/SniperRifle,$AimPivot/Minigun]
@onready var infection_runtime: Node = $InfectionRuntime
@onready var weapon_mount: Node = $WeaponMount
var _footstep_surface: Callable
var _biomass_footstep_surface: Callable
var audio: Node
var weapon_stance := WEAPON_STANCE.new()
var _animation_selection := ANIMATION_SELECTION.new()
var _scope_raise := SCOPE_RAISE.new()
var _shot_recoil := preload("res://game/features/player/shot_recoil.gd").new()
var _shooting_camera := preload("res://game/features/player/shooting_camera_state.gd").new()
var health: float
var armor: float
var antidotes: int
## Settings toggle: antidote syringes are not spent while it is on.
var infinite_antidotes: bool = false
var current_weapon_index: int = 0
var _roll_direction := Vector3.ZERO
var _roll_pace := 0.0
var _mutation_dash_motion := preload("res://game/features/player/mutation_dash_motion.gd").new()
var _roll_remaining: float = 0.0
var _roll_cooldown_remaining: float = 0.0
var _aim_point := Vector3.ZERO
var _camera_distance := 0.0
var _view_adjustment := preload("res://game/features/player/camera_adjustment.gd").new()
var _stun_remaining := 0.0
var _stun_intensity := 0.0
var _stun_rotation := 0
var _stun_ringing: AudioStreamPlayer
var _original_master_volume := 0.0
var mutation_effects: Node
var _mutation_control := CONTROL_LOSS.new()
var _mutation_menu_open := false
var _slot_weapons: Array[int] = [0, -1, -1] ## Weapon index per slot, -1 when empty; a new game starts with the pistol only.
var _emergency_key := false
var _manual_hero_spawn: Dictionary = {}
var effects_root: Node3D
var impact_pool: Node
var _drop_weapon_command: Callable

func _ready() -> void:
	floor_snap_length = 0.45
	# A freshly loaded map starts with the camera at its closest allowed distance, snapped without a zoom-in.
	_camera_distance=camera_min_distance
	camera.position=camera.position.normalized()*_camera_distance
	health=max_health
	armor=0.0
	antidotes=starting_antidotes
	_animation_selection.configure(self, aim_pivot, weapon_stance)
	$AnimationDriver.call("configure_clip_selector", _animation_selection.select_clip)
	_select_weapon(0)
	# AK and M4 take the same ammo type, so they spend and refill one reserve.
	weapons[5].call("share_reserve_with", weapons[4])
	mutation_effects = MUTATION_EFFECTS.new()
	add_child(mutation_effects)
	mutation_effects.call("configure", self, infection_runtime, weapons)
	configure_world(effects_root, impact_pool)
	audio = PLAYER_AUDIO.new()
	audio.name = "PlayerAudio"
	add_child(audio)
	audio.configure(self, camera_rig, $AnimationDriver)
	audio.configure_skills(infection_runtime)
	audio.set("glass_surface_query", _footstep_surface)
	audio.set("biomass_surface_query", _biomass_footstep_surface)
	var heal_feedback := HEAL_FEEDBACK.new()
	heal_feedback.name = "HealFeedback"
	add_child(heal_feedback)
	heal_feedback.configure(self)
func _physics_process(delta: float) -> void:
	weapon_stance.tick(delta, _has_presentation_activity())
	if _stun_remaining > 0.0:
		_stun_remaining = maxf(0.0, _stun_remaining - delta)
		if _stun_remaining == 0.0:
			camera_rig.position = Vector3.ZERO
			AudioServer.set_bus_volume_db(0, _original_master_volume)
			if is_instance_valid(_stun_ringing): _stun_ringing.stop()
			blast_stun_ended.emit()
		elif is_instance_valid(_stun_ringing):
			_stun_ringing.volume_db = -19.0 + 6.0 * _stun_intensity + linear_to_db(clampf(_stun_remaining / 0.8, 0.0001, 1.0))
	_roll_cooldown_remaining=maxf(0.0,_roll_cooldown_remaining-delta)
	_iframes_remaining=maxf(0.0,_iframes_remaining-delta)
	var control_lost: bool = infection_runtime.call("is_control_lost")
	_mutation_control.tick(delta, control_lost)
	if control_lost:
		_roll_remaining = 0.0
		_iframes_remaining = 0.0
		if Input.is_action_just_pressed("antidote"):
			use_antidote()
	if not _mutation_menu_open and not control_lost:
		_handle_actions()
	_update_camera(delta)
	if control_lost:
		_aim_uncontrolled()
	else:
		_update_aim()
	weapon_mount.call("aim_at", _aim_point)
	_update_move(delta)
	var w:=get_current_weapon()
	var fire_pressed := w != null and not Input.is_key_pressed(KEY_ALT) and not _mutation_menu_open and _roll_remaining <= 0.0 and (control_lost or (Input.is_action_pressed("fire") if bool(w.call("wants_continuous_fire")) else Input.is_action_just_pressed("fire")))
	if w != null and _scope_raise.step(delta, _scope_magnification(w) > 1.0, fire_pressed and not control_lost):
		_fire_weapon(w)
	elif fire_pressed and control_lost:
		_fire_weapon(w)
## Skill presentation asks for a short camera pull (see shooting_camera_state).
func camera_kick(amount: float) -> void:
	_shooting_camera.kick(amount)
## Settings: light camera shake on shots; recoil of the weapon and body stays on.
func set_camera_shake_enabled(enabled: bool) -> void:
	_shot_recoil.shake_enabled = enabled

func warm_up_skill_fx(parent: Node3D) -> void:
	mutation_effects.get("vfx").call("warm_up", parent)

func _unhandled_input(event: InputEvent) -> void:
	if get_tree().paused:
		return
	if _view_adjustment.handle_input(self, event):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.is_echo() and event.keycode == KEY_TAB:
		if not _mutation_menu_open and not infection_runtime.call("is_control_lost"):
			infection_runtime.call("put_on_gas_mask")
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		weapon_stance.record_mouse_motion(event.relative)
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_camera_distance=clampf(_camera_distance-camera_zoom_step,camera_min_distance,camera_max_distance)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_camera_distance=clampf(_camera_distance+camera_zoom_step,camera_min_distance,camera_max_distance)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT and not _mutation_menu_open and not infection_runtime.call("is_control_lost"):
			_scope_raise.toggle(_scope_magnification(get_current_weapon()) > 1.0)
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
	if Input.is_action_just_pressed("melee") and _roll_remaining <= 0.0 and not bool(infection_runtime.call("is_control_lost")) and mutation_effects.call("melee") != &"": _play_sound(&"attack_swing")
func _select_weapon(index:int)->void:
	if index<0 or index>=_slot_weapons.size() or _slot_weapons[index]<0: return
	var old:=get_current_weapon()
	if old!=null: old.call("cancel_reload")
	current_weapon_index=index
	_scope_raise.reset()
	weapon_stance.select_weapon(_slot_weapons[index])
	for i in weapons.size(): weapons[i].visible=i==_slot_weapons[index]
	weapon_mount.call("select_weapon", get_current_weapon())
	if audio != null and old != get_current_weapon():
		audio.play(&"weapon_switch")

func _fire_weapon(weapon: Node3D) -> bool:
	var previous := weapon_stance.begin_fire_attempt()
	$AnimationDriver.call("configure_clip_selector", _animation_selection.select_clip)
	weapon_mount.call("sync_weapon", weapon)
	var fired := bool(weapon.call("try_fire_at", _aim_point))
	weapon_stance.finish_fire_attempt(fired, previous)
	if fired:
		_shooting_camera.shot(String(weapon.call("get_weapon_name")))
		_shot_recoil.shot(String(weapon.call("get_weapon_name")), -weapon.get_node("Muzzle").global_basis.z)
	return fired

func _has_presentation_activity() -> bool:
	if _roll_remaining > 0.0 or bool(infection_runtime.call("is_control_lost")):
		return true
	for action in ["move_left", "move_right", "move_up", "move_down", "fire", "reload", "weapon_1", "weapon_2", "weapon_3", "weapon_4", "roll", "camera_left", "camera_right"]:
		if Input.is_action_pressed(action):
			return true
	return false

# Public v1 command used by the HUD's slot buttons.
func select_weapon_slot(index: int) -> bool:
	if get_tree().paused or _mutation_menu_open or infection_runtime.call("is_control_lost") or infection_runtime.call("is_defeated"):
		return false
	if index < 0 or index >= _slot_weapons.size() or _slot_weapons[index] < 0:
		return false
	_select_weapon(index)
	return true

# Public scene wiring v1 for the office floor; forwards to the spent casing pool.
func configure_floor_debris(floor_view: Node3D) -> void:
	$AimPivot/SpentCasings.call("configure_floor_debris", floor_view)

# Public scene wiring v1; owned by the mission composition.
func configure_world(container: Node3D, impacts: Node) -> void:
	effects_root = container
	impact_pool = impacts
	if weapons.is_empty():
		return
	for gun in weapons:
		gun.call("configure_world", container, impacts)
	$AimPivot/SpentCasings.call("configure_world", container, impacts)
	if is_instance_valid(mutation_effects):
		mutation_effects.call("configure_world", container)

func configure_footstep_surface(query: Callable, biomass_query := Callable()) -> void:
	_footstep_surface = query
	_biomass_footstep_surface = biomass_query
	if is_instance_valid(audio):
		audio.set("glass_surface_query", query)
		audio.set("biomass_surface_query", biomass_query)

func configure_weapon_drop(command: Callable) -> void:
	_drop_weapon_command = command

func get_current_weapon()->Node3D:
	return weapons[_slot_weapons[current_weapon_index]]

func get_weapon_in_slot(index: int) -> int:
	return _slot_weapons[index] if index >= 0 and index < _slot_weapons.size() else -1

func pickup_weapon(index: int) -> bool:
	if index < 0 or index >= weapons.size() or _slot_weapons.has(index):
		return false
	var slot := _slot_weapons.find(-1)
	if slot < 0:
		slot = current_weapon_index
		var previous := _slot_weapons[slot]
		if not _drop_weapon_command.is_valid():
			return false
		var offset := camera.global_basis.x
		offset.y = 0.0
		if not bool(_drop_weapon_command.call(previous, global_position + offset.normalized() * 1.3)):
			return false
		get_current_weapon().call("cancel_reload")
	_slot_weapons[slot] = index
	_select_weapon(slot)
	_play_sound(&"weapon_pickup")
	return true

## Weapon slots, armor and each weapon's reserve carried to the next map of a level chain
## (health and key start fresh).
func export_loadout() -> Dictionary:
	return {"slots": _slot_weapons.duplicate(), "armor": armor, "ammo": weapons.map(func(gun: Node) -> int: return int(gun.call("carried_ammo")))}

func import_loadout(loadout: Dictionary) -> void:
	armor = clampf(float(loadout.get("armor", 0.0)), 0.0, max_armor)
	var ammo: Variant = loadout.get("ammo")
	if ammo is Array and ammo.size() == weapons.size():
		for index in weapons.size():
			weapons[index].call("restore_carried_ammo", int(ammo[index]))
	var slots: Variant = loadout.get("slots")
	if not slots is Array or slots.size() != _slot_weapons.size():
		return
	var seen: Array[int] = []
	for raw in slots:
		var index := int(raw)
		if index < -1 or index >= weapons.size() or (index >= 0 and seen.has(index)):
			return
		seen.append(index)
	if seen[0] < 0: return # Slot 0 always holds a weapon: pickups fill empty slots from the first one.
	_slot_weapons = seen
	_select_weapon(0)

## Manual hero spawn from the planner replaces the start state; automatic settings change nothing.
## Called with {} after a carry from the previous map, to set the stored manual spawn over it.
func apply_hero_spawn(hero: Dictionary) -> void:
	if hero.get("mode") == "manual":
		_manual_hero_spawn = hero
	if not _manual_hero_spawn.is_empty():
		HERO_START.apply(self, _manual_hero_spawn)

## Weapon slot indices the player holds now; empty slots are left out.
func carried_weapon_indices() -> Array[int]:
	var carried: Array[int] = []
	for index in _slot_weapons:
		if index >= 0:
			carried.append(index)
	return carried

## Armor plate collected: the armor bar fills to its maximum.
func pickup_armor() -> void:
	armor = max_armor
	_play_sound(&"medkit_pickup")

func acquire_emergency_key() -> void:
	_emergency_key = true
	_play_sound(&"key_pickup")

# Public sound wiring v1 (ADR-0018): item and pickup sounds on the player.
func play_item_sound(event: StringName) -> void:
	_play_sound(event)

func _play_sound(event: StringName) -> void:
	if audio != null:
		audio.call("play", event)

func has_emergency_key() -> bool:
	return _emergency_key
func get_current_weapon_index()->int: return current_weapon_index
func take_damage(amount: float, damage_type: String = "physical") -> void:
	_apply_damage(amount, damage_type, global_position, Vector3.FORWARD, damage_type)

func get_projectile_material(_shape_index: int = -1) -> String:
	return "flesh"

func take_armor_capped_damage(amount: float) -> void: _apply_damage(amount, "physical", global_position, Vector3.FORWARD, "physical", true) # Colossus: armor soaks the whole blow
func take_projectile_damage(amount: float, point: Vector3, direction: Vector3, weapon: String) -> void:
	_apply_damage(amount, "physical", point, direction, weapon)

func take_blast_damage(amount: float, origin: Vector3) -> void:
	_apply_damage(amount, "fire", global_position, (global_position - origin).normalized(), "GRENADE")

func _apply_damage(amount: float, damage_type: String, point: Vector3, direction: Vector3, weapon: String, armor_capped: bool = false) -> void:
	if amount <= 0.0 or health <= 0.0 or _iframes_remaining > 0.0:
		return
	var remaining: float = mutation_effects.call("on_player_hit", maxf(amount, 0.0), damage_type)
	var absorbed:=remaining if armor_capped and armor > 0.0 else minf(armor,remaining)
	armor=maxf(0.0,armor-absorbed); remaining-=absorbed
	if absorbed > 0.0: _play_sound(&"damage_absorb")
	_wound += minf(remaining, health)
	health=maxf(0.0,health-remaining)
	if health <= 0.0 and mutation_effects.call("survive_lethal"):
		health = MUTATION_BALANCE.value("second_heart", "health")
	if remaining > 0.0:
		var excluded: Array[RID] = [get_rid()]
		projectile_blood.emit(point, direction, weapon, excluded, get_instance_id())
		blood_wounded.emit(global_position, excluded)
		if health <= 0.0:
			blood_death.emit(global_position, excluded, get_instance_id())
## True while damage taken is still unhealed; a full bar never bleeds.
func is_wounded() -> bool:
	return minf(_wound, max_health - health) > 0.01
func heal(amount:float, source: StringName = &"")->float:
	return CONSUMABLES.heal(self, amount, source)
func use_antidote() -> bool:
	return _antidote_action.request(self)

func add_ammo_to_current_weapon(amount:int)->int:return CONSUMABLES.add_ammo_for_weapon(self, str(get_current_weapon().call("get_weapon_name")), amount)
func add_ammo_for_weapon(weapon_name:String,amount:int)->int:
	return CONSUMABLES.add_ammo_for_weapon(self, weapon_name, amount)
func add_antidote(amount:int=1)->bool:
	if antidotes>=max_antidotes:return false
	antidotes=mini(max_antidotes,antidotes+maxi(amount,0))
	return true
func absorb_mutagen(delta_seconds:float)->float:return infection_runtime.call("absorb_mutagen",delta_seconds)
func on_mutagen_cloud(delta_seconds: float) -> void:
	mutation_effects.hybrids.cloud(delta_seconds)
## Settings: which animation the dodge plays, 0 = dive roll, 1 = strafe jump.
func set_dodge_animation_style(style: int) -> void:
	$AnimationDriver.set("dodge_style", clampi(style, 0, 1))
## Settings multiply authored walk speed; applying them repeatedly never compounds it.
func set_walk_tuning(speed_multiplier: float, animation_multiplier: float) -> void:
	_walk_speed_multiplier = clampf(speed_multiplier, 0.5, 1.5) if is_finite(speed_multiplier) else 1.0
	$AnimationDriver.set("leg_playback_multiplier", animation_multiplier)
func mutation_dash() -> void:
	_mutation_dash_motion.begin(self)
func mutation_enemy_killed(enemy: Node3D) -> void:
	mutation_effects.call("on_enemy_killed", enemy)
func get_mutation()->float:return infection_runtime.call("get_mutation")
func get_infection_skill(skill_id: String) -> bool:
	return bool(infection_runtime.call("has_skill", skill_id))
func _update_camera(delta: float) -> void:
	var bonus: Variant = get_current_weapon().get("camera_distance_bonus")
	var view_distance := _camera_distance + (float(bonus) if bonus != null else 0.0)
	view_distance *= 1.0 + _shooting_camera.tick(delta)
	if absf(camera.position.length() - view_distance) > 0.001:
		camera.position = camera.position.normalized() * lerpf(camera.position.length(), view_distance, 1.0 - exp(-8.0 * delta))
	camera_rig.position = _shot_recoil.camera_shake(delta)
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
		_stun_ringing.bus = &"SFX"
		add_child(_stun_ringing)
		_stun_ringing.stream = preload("res://assets/audio/vitals/blast_ringing.ogg")
	_stun_ringing.volume_db = -19.0 + 6.0 * _stun_intensity
	_stun_ringing.play()
	blast_stun_started.emit(_stun_remaining, _stun_intensity)

func _exit_tree() -> void:
	_end_blast_stun()

# Pause, game over and the planner must not keep the muffled, ringing mix.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED:
		_end_blast_stun()

func _end_blast_stun() -> void:
	if _stun_remaining <= 0.0:
		return
	_stun_remaining = 0.0
	camera_rig.position = Vector3.ZERO
	AudioServer.set_bus_volume_db(0, _original_master_volume)
	if is_instance_valid(_stun_ringing):
		_stun_ringing.stop()
	blast_stun_ended.emit()

func _update_move(delta:float)->void:
	_mutation_dash_motion.before_move(self, delta)
	var d:=_move_direction()
	if _roll_remaining>0.0:
		_roll_remaining=maxf(0.0,_roll_remaining-delta);velocity.x=_roll_direction.x*_roll_pace;velocity.z=_roll_direction.z*_roll_pace
	elif not bool(infection_runtime.call("is_control_lost")) and Input.is_action_just_pressed("roll") and d.length_squared()>0.0001 and _roll_cooldown_remaining<=0.0:
		_roll_direction=d.normalized();_roll_remaining=roll_duration;_roll_pace=roll_speed;_roll_cooldown_remaining=roll_cooldown;_iframes_remaining=roll_iframes
		mutation_effects.call("on_roll")
		_play_sound(&"player_roll")
		$AnimationDriver.call("play_dodge", _roll_direction, roll_duration)
	else:
		var walk_speed := move_speed * _walk_speed_multiplier
		var target:=d*(sprint_speed if Input.is_action_pressed("sprint") and not bool(infection_runtime.call("is_control_lost")) else walk_speed) * float(mutation_effects.call("movement_multiplier"))
		var accel:=ground_acceleration if d.length_squared()>0.0001 else ground_deceleration
		velocity.x=move_toward(velocity.x,target.x,accel*delta);velocity.z=move_toward(velocity.z,target.z,accel*delta)
	velocity.y=0.0 if is_on_floor() else velocity.y-gravity_acceleration*delta
	_intended_motion=Vector3(velocity.x,0.0,velocity.z)
	move_and_slide()
	_mutation_dash_motion.after_move(self)
	var recoil_motion := _shot_recoil.step(delta)
	if not recoil_motion.is_zero_approx():
		move_and_collide(recoil_motion)
	if is_wounded() and _blood_motion_start.distance_to(global_position) >= blood_drop_distance:
		if _blood_motion_start.distance_to(global_position) < 3.0:
			var excluded: Array[RID] = [get_rid()]
			wounded_moved.emit(_blood_motion_start, global_position, excluded)
		_blood_motion_start = global_position
	elif not is_wounded():
		_blood_motion_start = global_position
	_push_chair_contacts()
	if _roll_remaining>0.0: _push_roll_contacts()
# Sliding zeroes the velocity into an item, so pushes use the intended motion.
func _push_chair_contacts()->void:
	var pushed:={}
	for i in get_slide_collision_count():
		var collider:=get_slide_collision(i).get_collider()
		if collider!=null and not pushed.has(collider) and collider.has_method("push_from_character"):
			pushed[collider]=true
			collider.call("push_from_character",global_position,_intended_motion,push_strength)

func _push_roll_contacts()->void:
	for i in get_slide_collision_count():
		var collision:=get_slide_collision(i)
		var collider:=collision.get_collider()
		if collider!=null and collider.has_method("apply_player_push"):
			var direction:Vector3=collider.global_position-global_position
			direction.y=0.0
			if direction.length_squared()<0.001: direction=_roll_direction
			collider.call("apply_player_push",direction.normalized(),roll_push_strength)
	for node in get_tree().get_nodes_in_group("infected_alive"):
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
	if bool(infection_runtime.call("is_control_lost")):
		return _mutation_control.direction
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
		body_visual.look_at(body_visual.global_position+target_direction,Vector3.UP,true)

func _aim_uncontrolled() -> void:
	var direction: Vector3 = _mutation_control.direction
	if direction.length_squared() < 0.0001:
		return
	_aim_point = aim_pivot.global_position + direction * 8.0
	aim_pivot.look_at(_aim_point, Vector3.UP)
	body_visual.look_at(body_visual.global_position + direction, Vector3.UP, true)

# Public weapon_view_v1: read-only view data, never persisted.
func get_weapon_view() -> Dictionary:
	var weapon := get_current_weapon()
	var magnification := 0.0 if _scope_raise.hidden else _scope_magnification(weapon)
	return {"camera": camera, "target": _aim_point, "magnification": magnification}

func _scope_magnification(weapon: Node3D) -> float:
	var magnification: Variant = weapon.get("scope_magnification") if weapon != null else null
	return float(magnification) if magnification != null else 0.0

func get_camera_adjustment() -> Dictionary:
	return _view_adjustment.snapshot(self)

func set_camera_adjustment(values: Dictionary) -> void:
	_view_adjustment.restore(self, values)
