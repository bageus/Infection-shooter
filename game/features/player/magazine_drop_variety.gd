extends RefCounted
## The reload clips bake one fall for the ejected magazine. Each reload bends that fall a little: a different
## sideways drift, a different spin and a different roll after it lands, so no two drops look alike.
const DRIFT_METRES := 0.14
const SPIN_RADIANS := 1.2
const ROLL_SCALE := Vector2(0.4, 1.6)
const FALL_SECONDS := 0.4


## Rebuilds the `Magazine_Removed_*` tracks of `clip` from the authored keys with fresh random offsets.
static func vary(animation: Animation, rng: RandomNumberGenerator) -> void:
	for track in animation.get_track_count():
		if not String(animation.track_get_path(track)).contains("Magazine_Removed_") or animation.track_get_key_count(track) < 3:
			continue
		var type := animation.track_get_type(track)
		if type == Animation.TYPE_POSITION_3D:
			_vary_position(animation, track, rng)
		elif type == Animation.TYPE_ROTATION_3D:
			_vary_rotation(animation, track, rng)


static func _base(animation: Animation, track: int) -> Array:
	var key := "drop_base_%d" % track
	if not animation.has_meta(key):
		var values := []
		for index in animation.track_get_key_count(track):
			values.append(animation.track_get_key_value(track, index))
		animation.set_meta(key, values)
	return animation.get_meta(key)


static func _vary_position(animation: Animation, track: int, rng: RandomNumberGenerator) -> void:
	var base := _base(animation, track)
	var land := 0
	for index in base.size():
		if (base[index] as Vector3).y <= (base[base.size() - 1] as Vector3).y + 0.005:
			land = index
			break
	var land_time := animation.track_get_key_time(track, land)
	var drift := Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)) * DRIFT_METRES
	var roll := rng.randf_range(ROLL_SCALE.x, ROLL_SCALE.y)
	var landed := base[land] as Vector3
	for index in base.size():
		var time := animation.track_get_key_time(track, index)
		var fall := smoothstep(land_time - FALL_SECONDS, land_time, time)
		var value := base[index] as Vector3 + drift * fall
		if index > land:
			value = landed + (base[index] as Vector3 - landed) * Vector3(roll, 1.0, roll) + drift
		animation.track_set_key_value(track, index, value)


static func _vary_rotation(animation: Animation, track: int, rng: RandomNumberGenerator) -> void:
	var base := _base(animation, track)
	var length := animation.track_get_key_time(track, base.size() - 1)
	var axis := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)).normalized()
	var angle := rng.randf_range(-SPIN_RADIANS, SPIN_RADIANS)
	for index in base.size():
		var share := animation.track_get_key_time(track, index) / maxf(length, 0.001)
		var spin := Quaternion(axis, angle * smoothstep(0.1, 0.45, share))
		animation.track_set_key_value(track, index, (spin * (base[index] as Quaternion)).normalized())
