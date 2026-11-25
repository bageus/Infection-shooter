extends RefCounted
## One enemy physics step, moved out of infected_capsule.gd so each part can be timed in the F3 frame log.
## Behaviour is unchanged; `e` is the enemy (the capsule) the step runs for.
const CLIMB := preload("res://game/features/infected/enemy_climb_out.gd")
const SCREEN_REACH := preload("res://game/features/infected/enemy_screen_reach.gd")
const CROWD := preload("res://game/features/infected/crowd_separation.gd")


static func run(e, delta: float) -> void:
	var t: int = Time.get_ticks_usec()
	e._pace.recover_hit(delta)
	e._hit_cooldown = maxf(0.0, e._hit_cooldown - delta)
	e._track_blood_motion()
	e._mark_stump_drips()
	e._blast_stun_remaining = maxf(0.0, e._blast_stun_remaining - delta)
	if e._mutation_status.step(e, delta):
		return
	if e._dead:
		e.velocity = Vector3.ZERO
		if e._fall_watch != null and not e._fall_watch.call("step", delta):
			e._fall_watch = null
		return
	if e._emerge_left > 0.0:
		e._emerge_left = CLIMB.step(e, e._emerge_left, delta)
		return
	if e._target == null or not is_instance_valid(e._target) or e._senses.target_down(e, e._target): # a dead hero is neither chased nor hit
		return
	e._senses.refresh_modes(e)
	if e._turn.active() and e._senses.is_chasing():
		e._turn.cancel(e._animation)
	if e._senses.is_unaware() and e._slumber.may_sleep(e, e.global_position.distance_squared_to(e._target.global_position)):
		e._slumber.sleep(e)
		return
	SCREEN_REACH.update(e, e._animation, e._sleeping_far)
	e.audio.tick(delta, e._pace.charging, e.global_position.distance_squared_to(e._target.global_position) < 576.0, e._lod_frame_offset)
	t = PhysicsCost.lap(&"capsule_audio", t)
	if not e._senses.is_chasing():
		e._unaware_tick(delta)
		if not e._senses.is_chasing():
			return
		e._notice_player()
	t = PhysicsCost.lap(&"capsule_unaware_block", t)
	e._tick_pending_hit(delta)
	t = PhysicsCost.lap(&"capsule_pending_hit", t)

	var target_offset: Vector3 = e._target.global_position - e.global_position
	target_offset.y = 0.0
	var distance_sq: float = target_offset.length_squared()
	var physics_frame: int = Engine.get_physics_frames()

	var far: bool = distance_sq > e.sleep_distance * e.sleep_distance
	e._sleeping_far = far
	var lazy: bool = far or (e.offscreen and distance_sq >= e.full_simulation_distance * e.full_simulation_distance)
	var period: int = 12 if far else (4 if lazy else 1)  # a lazy enemy ticks every Nth frame, clocks advance N frames
	if lazy and physics_frame % period != e._lod_frame_offset % period: return
	var step: float = delta * period

	e._attack_cooldown = maxf(0.0, e._attack_cooldown - step)
	e._pace.tick(step, sqrt(distance_sq), e.charge_distance, e.move_speed, e.walk_speed_factor)
	t = PhysicsCost.lap(&"capsule_pace", t)
	e._obstacle_cooldown = maxf(0.0, e._obstacle_cooldown - step)

	var near: bool = distance_sq < e.full_simulation_distance * e.full_simulation_distance
	var ai_divisor: int = 1 if near else 4
	if lazy or physics_frame % ai_divisor == e._ai_tick_offset % ai_divisor:
		e._cached_desired = e._desired_velocity_from_offset(target_offset)
		e._cached_spread = CROWD.spread(e, e.collision_shape)

	e._behaviour_tick(step, target_offset)
	t = PhysicsCost.lap(&"capsule_behaviour_desired", t)
	var desired: Vector3 = Vector3.ZERO if e._blast_stun_remaining > 0.0 else e._cached_desired * (1.0 - e._pace.hit_penalty) * e._authoring.movement_scale()
	if not lazy:
		e._turn_toward_face_direction(delta)
	var spread: Vector3 = e._cached_spread
	e.velocity.x = desired.x + e._push_velocity.x + spread.x
	e.velocity.z = desired.z + e._push_velocity.z + spread.z
	e._push_velocity = e._push_velocity.move_toward(Vector3.ZERO, e.push_decay * delta)
	if lazy:
		# One collision-checked step (no sliding or gravity): still stops at walls and doors.
		e.move_and_collide(Vector3(e.velocity.x, 0.0, e.velocity.z) * step)
		return

	e._apply_gravity(delta)
	t = PhysicsCost.lap(&"capsule_gravity", t)
	if not near and physics_frame % 2 != e._ai_tick_offset % 2:
		e.move_and_collide(e.velocity * delta)
		return
	e._intended_motion = Vector3(e.velocity.x, 0.0, e.velocity.z)
	var t_mark: int = Time.get_ticks_usec()
	e.move_and_slide()
	PhysicsCost.add(&"capsule_slide", Time.get_ticks_usec() - t_mark)
	if near or physics_frame % 4 == e._ai_tick_offset % 4: e._push_chair_contacts()
	t = PhysicsCost.lap(&"capsule_push_chair", t)
	e._breaker.track_progress(e, delta if near else delta * 2.0, not e._route.direct_clear())
	t = PhysicsCost.lap(&"capsule_track", t)
	if near or physics_frame % 4 == e._ai_tick_offset:
		e._try_break_blocking_props(); PhysicsCost.add(&"capsule_props", Time.get_ticks_usec() - t_mark)
