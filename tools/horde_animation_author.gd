extends RefCounted
## Build-time rig and clips for the Horde blob (ADR-0016).
##
## The Horde is a dome on a skirt of tentacles. Its skeleton is a core
## (Hips > Body > Crown) and eight radial tentacles of two segments. Clips:
## Idle (breathing), Walk (rippling crawl), Run (ram surge), Summon (gather,
## burst and pulse; the impulse fires at SUMMON_PEAK) and Death (deflate).
## Walk and Run keep the core level like a centipede: only the tentacle legs
## step, each on its own phase, while the dome lumps wobble out of sync.
## It has no attack clip: the Horde attacks by ramming.

const FPS := 30.0
const TENTACLES := 8
const SUMMON_PEAK := 0.45
const CRAWL_HZ := 2.2
const RAM_HZ := 3.6
const CRAWL_STEP := 1.1 # metres covered per crawl cycle
const RAM_STEP := 2.4
const LUMPS := 6 # bodies and heads of the dome: each breathes and wobbles on its own

var _floor_y := -0.55
var _top_y := 0.55
var _radius := 0.93
var _rest := {}


func crawl_speed() -> float:
	return CRAWL_HZ * CRAWL_STEP


func ram_speed() -> float:
	return RAM_HZ * RAM_STEP


func build_skeleton(vertices: PackedVector3Array) -> Skeleton3D:
	var bounds := AABB(vertices[0], Vector3.ZERO)
	for vertex in vertices:
		bounds = bounds.expand(vertex)
	_floor_y = bounds.position.y
	_top_y = bounds.end.y
	_radius = maxf(bounds.size.x, bounds.size.z) * 0.5
	var height := _top_y - _floor_y
	var skeleton := Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	_add(skeleton, "Root", "", Vector3(0.0, _floor_y, 0.0))
	_add(skeleton, "Hips", "Root", Vector3(0.0, _floor_y + height * 0.1, 0.0))
	_add(skeleton, "Body", "Hips", Vector3(0.0, _floor_y + height * 0.36, 0.0))
	_add(skeleton, "Crown", "Body", Vector3(0.0, _floor_y + height * 0.68, 0.0))
	for k in LUMPS:
		var lump_angle := _lump_angle(k)
		var lump_out := Vector3(sin(lump_angle), 0.0, cos(lump_angle))
		_add(skeleton, "L%d" % k, "Body", lump_out * _radius * 0.45 + Vector3(0.0, _floor_y + height * (0.5 + 0.12 * float(k % 2)), 0.0))
	for i in TENTACLES:
		var angle := TAU * float(i) / float(TENTACLES)
		var out := Vector3(sin(angle), 0.0, cos(angle))
		_add(skeleton, "T%d_A" % i, "Hips", out * _radius * 0.32 + Vector3(0.0, _floor_y + height * 0.1, 0.0))
		_add(skeleton, "T%d_B" % i, "T%d_A" % i, out * _radius * 0.64 + Vector3(0.0, _floor_y + height * 0.05, 0.0))
	skeleton.reset_bone_poses()
	for index in skeleton.get_bone_count():
		_rest[skeleton.get_bone_name(index)] = skeleton.get_bone_rest(index)
	return skeleton


func _add(skeleton: Skeleton3D, bone: String, parent: String, global_origin: Vector3) -> void:
	var index := skeleton.add_bone(bone)
	var origin := global_origin
	if not parent.is_empty():
		var parent_index := skeleton.find_bone(parent)
		skeleton.set_bone_parent(index, parent_index)
		origin -= skeleton.get_bone_global_rest(parent_index).origin
	skeleton.set_bone_rest(index, Transform3D(Basis.IDENTITY, origin))


# Dome by height (Hips/Body/Crown), skirt by angular sector and radius.
func weights(vertices: PackedVector3Array, skeleton: Skeleton3D) -> Array:
	var bone_count := skeleton.get_bone_count()
	var height := _top_y - _floor_y
	var result := []
	for vertex in vertices:
		var row := PackedFloat32Array()
		row.resize(bone_count)
		var radial := Vector2(vertex.x, vertex.z).length() / _radius
		var y := (vertex.y - _floor_y) / height
		var skirt := _smooth(0.42, 0.18, y) * _smooth(0.22, 0.42, radial)
		var crown := _smooth(0.55, 0.85, y)
		var hips := _smooth(0.3, 0.12, y) * (1.0 - _smooth(0.22, 0.42, radial))
		var upper := 1.0 - skirt
		var azimuth := fposmod(atan2(vertex.x, vertex.z), TAU)
		var lump_share := _smooth(0.25, 0.5, y) * _smooth(0.12, 0.4, radial) * upper
		var lump_weights := []
		var lump_total := 0.0
		for k in LUMPS:
			var gap := absf(angle_difference(azimuth, _lump_angle(k)))
			var near := 1.0 - _smooth(0.0, TAU / float(LUMPS) * 1.4, gap)
			lump_weights.append(near)
			lump_total += near
		var lump_mix := minf(0.75, lump_total) * lump_share
		upper -= lump_mix
		for k in LUMPS:
			if lump_total > 0.0:
				row[skeleton.find_bone("L%d" % k)] = lump_mix * float(lump_weights[k]) / lump_total
		row[skeleton.find_bone("Crown")] = upper * crown
		row[skeleton.find_bone("Body")] = upper * (1.0 - crown) * (1.0 - hips)
		row[skeleton.find_bone("Hips")] = upper * (1.0 - crown) * hips
		if skirt > 0.0:
			var sector := fposmod(atan2(vertex.x, vertex.z), TAU) / TAU * float(TENTACLES)
			var first := int(floorf(sector)) % TENTACLES
			var second := (first + 1) % TENTACLES
			var blend := sector - floorf(sector)
			var outer := _smooth(0.45, 0.72, radial)
			for pick: Array in [[first, 1.0 - blend], [second, blend]]:
				var share: float = skirt * float(pick[1])
				row[skeleton.find_bone("T%d_A" % int(pick[0]))] += share * (1.0 - outer)
				row[skeleton.find_bone("T%d_B" % int(pick[0]))] += share * outer
		result.append(row)
	return result


func build_library(skeleton: Skeleton3D) -> AnimationLibrary:
	var library := AnimationLibrary.new()
	library.add_animation(&"Idle", _bake(skeleton, _idle, 2.6, true))
	library.add_animation(&"Walk", _bake(skeleton, _crawl, 1.0 / CRAWL_HZ, true))
	library.add_animation(&"Run", _bake(skeleton, _ram, 1.0 / RAM_HZ, true))
	library.add_animation(&"Summon", _bake(skeleton, _summon, 1.6, false))
	library.add_animation(&"Death", _bake(skeleton, _death, 1.5, false))
	return library


# A pose is {bone: [Quaternion, scale]} plus "hips_offset".
func _idle(t: float) -> Dictionary:
	var breath := sin(t / 2.6 * TAU)
	var pose := _base()
	pose.Body = [Quaternion.IDENTITY, Vector3(1.0 + 0.03 * breath, 1.0 - 0.025 * breath, 1.0 + 0.03 * breath)]
	pose.Crown = [Quaternion(Vector3.BACK, deg_to_rad(4.0 * sin(t / 2.6 * TAU * 2.0))), Vector3.ONE * (1.0 + 0.04 * breath)]
	_ripple(pose, t / 2.6 * TAU, 6.0, 4.0, 1.0)
	_wobble(pose, t / 2.6 * TAU, 1.0)
	return pose


func _crawl(t: float) -> Dictionary:
	var phase := t * CRAWL_HZ * TAU
	var pose := _base()
	_ripple(pose, phase, 22.0, 14.0, 2.0, false, true)
	_wobble(pose, phase, 1.0)
	return pose


func _ram(t: float) -> Dictionary:
	var phase := t * RAM_HZ * TAU
	var pose := _base()
	pose.Hips = [Quaternion(Vector3.RIGHT, deg_to_rad(9.0)), Vector3.ONE]
	pose.Body = [Quaternion.IDENTITY, Vector3(0.9, 0.92, 1.18)]
	pose.Crown = [Quaternion(Vector3.RIGHT, deg_to_rad(-14.0)), Vector3(0.95, 0.9, 1.1)]
	_ripple(pose, phase, 34.0, 26.0, 2.0, true, true)
	_wobble(pose, phase, 0.6)
	return pose


func _summon(t: float) -> Dictionary:
	var u := t / 1.6
	var pose := _base()
	var gather := _smooth(0.0, 0.35, u) * (1.0 - _smooth(0.38, SUMMON_PEAK, u))
	var burst := _smooth(0.36, SUMMON_PEAK, u) * (1.0 - _smooth(0.72, 1.0, u))
	var pulse := sin(clampf((u - SUMMON_PEAK) / 0.3, 0.0, 1.0) * TAU * 1.5) * burst
	var body_scale := Vector3(1.0 + 0.1 * gather + 0.22 * burst + 0.06 * pulse, 1.0 - 0.18 * gather + 0.26 * burst + 0.08 * pulse, 1.0 + 0.1 * gather + 0.22 * burst + 0.06 * pulse)
	pose.hips_offset = Vector3(0.0, -0.06 * gather, 0.0)
	pose.Body = [Quaternion.IDENTITY, body_scale]
	pose.Crown = [Quaternion(Vector3.RIGHT, deg_to_rad(-8.0 * burst)), Vector3.ONE * (1.0 + 0.3 * burst + 0.1 * pulse)]
	for i in TENTACLES:
		var angle := TAU * float(i) / float(TENTACLES)
		var axis := _lift_axis(angle)
		var lift := -14.0 * gather + 6.0 * burst + 5.0 * pulse * sin(angle * 3.0)
		pose["T%d_A" % i] = [Quaternion(axis, deg_to_rad(lift)), Vector3(1.0, 1.0, 1.0)]
		pose["T%d_B" % i] = [Quaternion(axis, deg_to_rad(-22.0 * gather + 34.0 * burst + 10.0 * pulse)), Vector3.ONE]
	return pose


func _death(t: float) -> Dictionary:
	var u := t / 1.5
	var pose := _base()
	var spasm := (1.0 - _smooth(0.0, 0.35, u)) * sin(u * 40.0)
	var collapse := _smooth(0.15, 0.8, u)
	pose.hips_offset = Vector3(0.0, -0.12 * collapse, 0.0)
	pose.Body = [Quaternion(Vector3.BACK, deg_to_rad(6.0 * spasm)), Vector3(1.0 + 0.25 * collapse, 1.0 - 0.62 * collapse, 1.0 + 0.25 * collapse)]
	pose.Crown = [Quaternion(Vector3.RIGHT, deg_to_rad(20.0 * collapse)), Vector3.ONE * (1.0 - 0.45 * collapse)]
	for i in TENTACLES:
		var angle := TAU * float(i) / float(TENTACLES)
		var axis := _lift_axis(angle)
		var twitch := 12.0 * spasm * sin(angle * 5.0 + u * 30.0)
		pose["T%d_A" % i] = [Quaternion(axis, deg_to_rad(-6.0 * collapse + twitch)), Vector3.ONE]
		pose["T%d_B" % i] = [Quaternion(axis, deg_to_rad(-10.0 * collapse - twitch * 0.5)), Vector3.ONE]
	return pose


# Wave of tentacle lifts travelling around the skirt; when `push`, rear
# tentacles stretch backwards to shove the body forward.
# With `scatter` every leg steps on its own phase and stride, not as a wave.
func _ripple(pose: Dictionary, phase: float, lift_degrees: float, curl_degrees: float, waves: float, push := false, scatter := false) -> void:
	for i in TENTACLES:
		var angle := TAU * float(i) / float(TENTACLES)
		var axis := _lift_axis(angle)
		var local := phase - angle * waves
		var vigour := 1.0
		if scatter:
			local = phase + TAU * fposmod(float(i) * 0.618, 1.0)
			vigour = 0.8 + 0.4 * fposmod(float(i) * 0.37, 1.0)
		var lift := lift_degrees * vigour * maxf(0.0, sin(local)) - 4.0
		var sweep := 10.0 * cos(local)
		if push:
			var rear := maxf(0.0, -cos(angle))
			lift += 10.0 * rear * sin(local * 2.0)
			sweep += 18.0 * rear * sin(local)
		pose["T%d_A" % i] = [Quaternion(Vector3.UP, deg_to_rad(sweep)) * Quaternion(axis, deg_to_rad(lift)), Vector3.ONE]
		pose["T%d_B" % i] = [Quaternion(axis, deg_to_rad(curl_degrees * vigour * sin(local - 0.9))), Vector3.ONE]


# Each dome lump breathes (scale) and sways on its own phase; whole cycles only,
# so the clip loops. Bones L0..L5 are children of Body.
func _wobble(pose: Dictionary, phase: float, amount: float) -> void:
	for k in LUMPS:
		var offset := float(k) * 1.9
		var angle := _lump_angle(k)
		var tilt := Vector3(cos(angle), 0.0, -sin(angle))
		var swell := sin(phase + offset)
		pose["L%d" % k] = [
			Quaternion(tilt, deg_to_rad(3.5 * amount * sin(phase * 2.0 + offset * 1.7))),
			Vector3.ONE * (1.0 + 0.045 * amount * swell) + Vector3(0.0, 0.03 * amount * sin(phase + offset + 2.0), 0.0),
		]


static func _lump_angle(k: int) -> float:
	return TAU * (float(k) + 0.5) / float(LUMPS)


func _base() -> Dictionary:
	return {"hips_offset": Vector3.ZERO}


# Axis that lifts a tentacle lying along `angle` (around the vertical).
static func _lift_axis(angle: float) -> Vector3:
	var out := Vector3(sin(angle), 0.0, cos(angle))
	return out.cross(Vector3.UP).normalized()


static func _smooth(edge0: float, edge1: float, value: float) -> float:
	if is_equal_approx(edge0, edge1):
		return 1.0 if value >= edge1 else 0.0
	var t := clampf((value - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _bake(skeleton: Skeleton3D, sampler: Callable, length: float, looping: bool) -> Animation:
	var animation := Animation.new()
	animation.length = length
	animation.loop_mode = Animation.LOOP_LINEAR if looping else Animation.LOOP_NONE
	var rotation_tracks := {}
	var scale_tracks := {}
	for index in skeleton.get_bone_count():
		var bone := skeleton.get_bone_name(index)
		if bone == "Root":
			continue
		var track := animation.add_track(Animation.TYPE_ROTATION_3D)
		animation.track_set_path(track, NodePath("Skeleton3D:" + bone))
		rotation_tracks[bone] = track
		if bone in ["Body", "Crown"] or bone.begins_with("L") and bone.length() == 2:
			var scale_track := animation.add_track(Animation.TYPE_SCALE_3D)
			animation.track_set_path(scale_track, NodePath("Skeleton3D:" + bone))
			scale_tracks[bone] = scale_track
	var hips_track := animation.add_track(Animation.TYPE_POSITION_3D)
	animation.track_set_path(hips_track, NodePath("Skeleton3D:Hips"))
	var frames := maxi(2, ceili(length * FPS))
	for frame in frames + 1:
		var time := minf(length, float(frame) / FPS)
		var pose: Dictionary = sampler.call(fmod(time, length) if looping else time)
		for bone: String in rotation_tracks:
			var entry: Array = pose.get(bone, [Quaternion.IDENTITY, Vector3.ONE])
			animation.rotation_track_insert_key(rotation_tracks[bone], time, (entry[0] as Quaternion).normalized())
			if scale_tracks.has(bone):
				animation.scale_track_insert_key(scale_tracks[bone], time, entry[1])
		animation.position_track_insert_key(hips_track, time, (_rest["Hips"] as Transform3D).origin + (pose.hips_offset as Vector3))
	return animation
