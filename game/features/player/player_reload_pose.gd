extends SkeletonModifier3D
## Reload by hand: the support hand takes an invisible magazine (or shell, for
## the shotgun) from the vest and feeds it into the weapon. Runs after the
## aim turn so the pouch follows the torso. Presentation only.
const FADE_SPEED := 9.0
const POUCH := Vector3(.14, .12, .10)
const POLE := Vector3(.65, .10, .0)
const POLE_RIGHT := Vector3(-.65, .15, .10)
const TUCK := Vector3(-.05, .36, .25)
const TUCK_REACH := .2
var mount: Node
var weight := 0.0
var phase := 0.0
var pouch_target := Vector3.ZERO
var feed_target := Vector3.ZERO
var hand_error := 0.0
var hand_position := Vector3.ZERO
var _spine := -1
var _spine_rest := Basis.IDENTITY


func _process_modification_with_delta(delta: float) -> void:
	var skeleton := get_skeleton()
	var weapon := mount.get("_active") as Node3D if mount != null else null
	var reloading: bool = is_instance_valid(weapon) and weapon.has_method("is_reloading") and weapon.call("is_reloading")
	weight = move_toward(weight, 1.0 if reloading else 0.0, FADE_SPEED * delta)
	if reloading:
		var total := maxf(float(weapon.get("reload_time")), .01)
		phase = clampf(1.0 - float(weapon.get("_reload_remaining")) / total, 0.0, 1.0)
	else:
		phase = 0.0
	if weight <= 0.0 or skeleton == null:
		return
	if _spine < 0:
		_spine = skeleton.find_bone("Spine")
		if _spine < 0:
			return
		_spine_rest = skeleton.get_bone_global_rest(_spine).basis
	var hand_bone := skeleton.find_bone("LeftHand")
	var right_bone := skeleton.find_bone("RightHand")
	var spine_pose := skeleton.get_bone_global_pose(_spine)
	var offset := spine_pose.basis * (_spine_rest.inverse() * POUCH)
	pouch_target = spine_pose.origin + offset
	var tuck_amount := _tuck(phase) * weight
	mount.set("_aim_modifying", true)
	if tuck_amount > 0.0:
		# The gun is brought in towards the chest so the other hand can reach the magazine well.
		var gun_hand := skeleton.get_bone_global_pose(right_bone).origin
		var pulled := spine_pose.origin + spine_pose.basis * (_spine_rest.inverse() * TUCK)
		var goal_right := gun_hand + (pulled - gun_hand).limit_length(TUCK_REACH) * tuck_amount
		mount.equipment_pose.call("_fit_arm", skeleton, "Right", goal_right, POLE_RIGHT)
		mount.call("sync_weapon", weapon)
	var hand := skeleton.get_bone_global_pose(hand_bone).origin
	feed_target = _feed_point(skeleton, weapon)
	var goal := hand.lerp(_reach(phase, hand), weight)
	mount.equipment_pose.call("_fit_arm", skeleton, "Left", goal, POLE)
	mount.call("sync_weapon", weapon)
	mount.set("_aim_modifying", false)
	hand_error = skeleton.get_bone_global_pose(hand_bone).origin.distance_to(goal)
	hand_position = skeleton.get_bone_global_pose(hand_bone).origin


## 0 at the ends of the cycle, 1 while the magazine is fed in.
func _tuck(t: float) -> float:
	return _ease(minf(t / .35, 1.0)) * (1.0 - _ease(clampf((t - .75) / .2, 0.0, 1.0)))


## Hand position along the cycle: out to the vest, grab, over to the weapon, insert, back.
func _reach(t: float, rest: Vector3) -> Vector3:
	if t < .2:
		return rest.lerp(pouch_target, _ease(t / .2))
	if t < .35:
		return pouch_target
	if t < .65:
		var k := _ease((t - .35) / .3)
		return pouch_target.lerp(feed_target, k) + Vector3.UP * .05 * sin(k * PI)
	if t < .8:
		return feed_target + Vector3.UP * .015 * sin((t - .65) / .15 * PI)
	return feed_target.lerp(rest, _ease((t - .8) / .2))


func _feed_point(skeleton: Skeleton3D, weapon: Node3D) -> Vector3:
	if not is_instance_valid(weapon):
		return pouch_target
	var muzzle := weapon.get_node_or_null("Muzzle") as Node3D
	var forward := -muzzle.global_basis.z.normalized() if muzzle != null else -weapon.global_basis.z
	var up := muzzle.global_basis.y.normalized() if muzzle != null else Vector3.UP
	# Pistols take the magazine in the grip; long guns just ahead of the trigger.
	var shift := 0.0 if weapon.call("get_weapon_name") in ["PISTOL", "UZI"] else .04
	var world := weapon.global_position + forward * shift - up * .07
	return skeleton.global_transform.affine_inverse() * world


static func _ease(value: float) -> float:
	var x := clampf(value, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)
