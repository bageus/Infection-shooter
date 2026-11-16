extends RefCounted
## The reload clips bake one fall for the ejected magazine and then slide it along the floor, always the same way.
## Each reload bends the fall a little (sideways drift, the way it lies) and ends the clip's part at the landing:
## from there `rest()` gives the place on the floor where a loose copy is left, so it neither slides nor follows the hero.
const DRIFT_METRES := 0.14
const FALL_SECONDS := 0.4
const REST_META := &"magazine_rest"
const LAND_META := &"magazine_land_time"


## Rebuilds the `Magazine_Removed_*` tracks of `animation` from the authored keys with fresh random offsets.
static func vary(animation: Animation, rng: RandomNumberGenerator) -> void:
	var tracks := {}
	for track in animation.get_track_count():
		if String(animation.track_get_path(track)).contains("Magazine_Removed_") and animation.track_get_key_count(track) >= 3:
			tracks[animation.track_get_type(track)] = track
	if not tracks.has(Animation.TYPE_POSITION_3D) or not tracks.has(Animation.TYPE_ROTATION_3D) or not tracks.has(Animation.TYPE_SCALE_3D):
		return
	var position: int = tracks[Animation.TYPE_POSITION_3D]
	var rotation: int = tracks[Animation.TYPE_ROTATION_3D]
	var points := _base(animation, position)
	var land := 0
	for index in points.size():
		if (points[index] as Vector3).y <= (points[points.size() - 1] as Vector3).y + 0.005:
			land = index
			break
	var landed := animation.track_get_key_time(position, land)
	var landed: Vector3 = points[land] as Vector3 + Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)) * DRIFT_METRES
	for index in points.size():
		var fall := smoothstep(landed - FALL_SECONDS, landed, animation.track_get_key_time(position, index))
		animation.track_set_key_value(position, index, landed if index >= land else (points[index] as Vector3).lerp(Vector3(landed.x, (points[index] as Vector3).y, landed.z), fall))
	# It ends lying the way the clip leaves it at the very end, turned a random way round.
	var turns := _base(animation, rotation)
	var lying := (Quaternion(Vector3.UP, rng.randf_range(-PI, PI)) * (turns[turns.size() - 1] as Quaternion)).normalized()
	for index in turns.size():
		var fall := smoothstep(landed - FALL_SECONDS, landed, animation.track_get_key_time(rotation, index))
		animation.track_set_key_value(rotation, index, (turns[index] as Quaternion).slerp(lying, fall))
	_hide_after(animation, tracks[Animation.TYPE_SCALE_3D], landed)
	animation.set_meta(REST_META, Transform3D(Basis(lying), landed))
	animation.set_meta(LAND_META, landed)


## Where the magazine lies after `vary`, in the model's space, and the clip time it lands at (-1 without a magazine).
static func rest(animation: Animation) -> Transform3D:
	return animation.get_meta(REST_META, Transform3D.IDENTITY)


static func land_time(animation: Animation) -> float:
	return float(animation.get_meta(LAND_META, -1.0))


static func _base(animation: Animation, track: int) -> Array:
	var key := "drop_base_%d" % track
	if not animation.has_meta(key):
		var values := []
		for index in animation.track_get_key_count(track):
			values.append(animation.track_get_key_value(track, index))
		animation.set_meta(key, values)
	return animation.get_meta(key)


# The clip's own magazine disappears at the landing (the last two scale keys are the authored fade at the clip's end).
static func _hide_after(animation: Animation, track: int, time: float) -> void:
	var count := animation.track_get_key_count(track)
	if animation.has_meta("drop_hidden_%d" % track) or count < 2:
		return
	animation.set_meta("drop_hidden_%d" % track, true)
	animation.track_set_key_time(track, count - 2, time)
	animation.track_set_key_time(track, count - 1, time + 0.02)
