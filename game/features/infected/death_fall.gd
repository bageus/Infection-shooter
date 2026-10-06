extends RefCounted
## Which way a killed infected falls (ADR-0033). The body keeps its running
## momentum and gets the push of the killing blow: bullets from afar barely
## push, so a charging infected falls forward on its face; a close shotgun
## blast throws it backward; a grenade throws it away from the explosion.
## The maths is pure; landing() and throw() apply it to the dying body.

const DEATH := &"death"
const DEATH_FORWARD := &"death_forward"
const DEATH_BACK := &"death_back"
## Push of one killing hit in m/s on a standard-size body.
const WEAPON_PUSH := {"PISTOL": 0.4, "UZI": 0.4, "RIFLE": 0.6, "SHOTGUN": 9.0, "GRENADE LAUNCHER": 2.0}
## The shotgun pushes fully up to SHOTGUN_CLOSE metres and fades out by SHOTGUN_FAR.
const SHOTGUN_CLOSE := 3.0
const SHOTGUN_FAR := 10.0
const SHOTGUN_FAR_SHARE := 0.15
## Blast push at the edge and at the centre of the explosion.
const BLAST_PUSH_MIN := 3.5
const BLAST_PUSH_MAX := 10.0
## Share of the movement speed the falling body carries.
const MOMENTUM_SHARE := 0.6
## Below this the body simply collapses where it stands.
const COLLAPSE_SPEED := 0.2
## Thrown at least this hard, a body falls backward as thrown rather than slumping.
const THROWN_SPEED := 2.5
## Metres the body travels along the floor per m/s of fall speed.
const SLIDE_PER_SPEED := 0.17
const MAX_SLIDE := 1.8


static func hit_push(weapon: String, direction: Vector3, distance: float) -> Vector3:
	var strength := float(WEAPON_PUSH.get(weapon, 0.4))
	if weapon == "SHOTGUN":
		var fade := clampf((distance - SHOTGUN_CLOSE) / (SHOTGUN_FAR - SHOTGUN_CLOSE), 0.0, 1.0)
		strength *= lerpf(1.0, SHOTGUN_FAR_SHARE, fade)
	return _flat(direction).normalized() * strength


## factor is 1 at the blast centre and 0 at its edge.
static func blast_push(origin: Vector3, position: Vector3, factor: float) -> Vector3:
	var away := _flat(position - origin)
	if away.length_squared() < 0.0001:
		return Vector3.ZERO
	return away.normalized() * lerpf(BLAST_PUSH_MIN, BLAST_PUSH_MAX, clampf(factor, 0.0, 1.0))


## Returns {state: death clip state, turn: yaw radians that line the clip's fall
## up with the fall direction, slide: planar travel of the body}.
static func resolve(momentum: Vector3, push: Vector3, forward: Vector3, size: float) -> Dictionary:
	var fall := _flat(momentum) * MOMENTUM_SHARE + _flat(push) / pow(maxf(size, 0.5), 1.5)
	var speed := fall.length()
	var facing := _flat(forward).normalized()
	if speed < COLLAPSE_SPEED or facing.is_zero_approx():
		return {"state": DEATH, "turn": 0.0, "slide": Vector3.ZERO}
	var direction := fall / speed
	var ahead := direction.dot(facing) >= 0.0
	var state := DEATH_FORWARD if ahead else (DEATH_BACK if speed >= THROWN_SPEED else DEATH)
	var clip_fall := facing if ahead else -facing
	return {
		"state": state,
		"turn": clip_fall.signed_angle_to(direction, Vector3.UP),
		"slide": direction * minf(speed * SLIDE_PER_SPEED, MAX_SLIDE),
	}


## Planar travel cut short of walls and furniture in the way.
static func landing(body: CollisionObject3D, slide: Vector3, radius: float) -> Vector3:
	var distance := slide.length()
	if distance < 0.02 or not body.is_inside_tree():
		return Vector3.ZERO
	var direction := slide / distance
	var from := body.global_position
	var query := PhysicsRayQueryParameters3D.create(from, from + direction * (distance + radius), 1, [body.get_rid()])
	var hit := body.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		distance = maxf(0.0, from.distance_to(hit["position"]) - radius)
	return direction * distance


## The body turns into the fall and travels with it while it goes down.
static func throw(body: Node3D, turn: float, travel: Vector3) -> void:
	var turning := absf(turn) > 0.01
	var moving := not travel.is_zero_approx()
	if not turning and not moving:
		return
	var tween := body.create_tween().set_parallel()
	if turning:
		tween.tween_property(body, "rotation:y", body.rotation.y + turn, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if moving:
		tween.tween_property(body, "global_position", body.global_position + travel, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


static func _flat(vector: Vector3) -> Vector3:
	return Vector3(vector.x, 0.0, vector.z)
