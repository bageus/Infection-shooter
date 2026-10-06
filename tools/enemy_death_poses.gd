extends RefCounted
## Build-time key poses of the directional enemy deaths (ADR-0033), in the
## parameter space of tools/enemy_animation_author.gd (degrees, model frame:
## +Z is the front, +X the character's left; positive hips_pitch tips forward).
## The game turns and slides the body so these falls line up with the blow.


## Carried by its own momentum: the legs fold mid-stride, the body pitches
## onto its face, one arm flung ahead, the other trailing at the side.
static func forward_keys(stance: Dictionary, hips_height: float) -> Array:
	var hit := stance.duplicate()
	hit.merge({
		"lean": 26.0, "chest_pitch": 6.0, "neck": 10.0, "head": 18.0, "head_turn": 6.0,
		"L_flex": 4.0, "R_flex": 22.0, "L_abd": 10.0, "R_abd": 14.0, "L_elbow": 12.0, "R_elbow": 18.0,
		"L_swing": -14.0, "L_knee": 22.0, "R_swing": 30.0, "R_knee": 34.0,
		"hips_pitch": 8.0, "hips_z": 0.08 * hips_height, "hips_y": -0.04 * hips_height,
	}, true)
	var stumble := hit.duplicate()
	stumble.merge({
		"lean": 30.0, "head": 4.0, "hips_pitch": 30.0, "hips_y": -0.34 * hips_height, "hips_z": 0.22 * hips_height,
		"L_swing": 18.0, "L_knee": 88.0, "R_swing": 34.0, "R_knee": 70.0, "L_ankle": -18.0, "R_ankle": -12.0,
		"L_flex": 48.0, "R_flex": 34.0, "L_abd": 26.0, "R_abd": 20.0, "L_elbow": 34.0, "R_elbow": 40.0,
	}, true)
	var lying := 0.13 * hips_height - hips_height
	var fall := stumble.duplicate()
	fall.merge({
		"lean": -6.0, "chest_pitch": -4.0, "neck": -8.0, "head": -14.0, "head_turn": 52.0, "head_tilt": 0.0,
		"hips_pitch": 86.0, "hips_y": lying + 0.03 * hips_height, "hips_z": 0.46 * hips_height, "hips_roll": 4.0,
		"L_swing": -4.0, "L_knee": 26.0, "R_swing": 2.0, "R_knee": 40.0, "L_ankle": 34.0, "R_ankle": 30.0,
		"L_abd_leg": 6.0, "R_abd_leg": 10.0,
		"L_flex": 164.0, "L_abd": 26.0, "L_elbow": 18.0, "R_flex": -14.0, "R_abd": 18.0, "R_elbow": 12.0,
	}, true)
	var bounce := fall.duplicate()
	bounce.merge({"hips_pitch": 91.0, "hips_y": lying + 0.06 * hips_height, "L_knee": 34.0, "R_knee": 48.0, "head": -18.0}, true)
	var rest := fall.duplicate()
	rest.merge({"hips_pitch": 89.0, "hips_y": lying - 0.03 * hips_height, "head_turn": 60.0, "L_knee": 20.0, "R_knee": 32.0}, true)
	return [[0.0, stance], [0.12, hit], [0.38, stumble], [0.64, fall], [0.78, bounce], [1.0, rest]]


## Thrown off its feet: the torso snaps back, arms and legs fly forward and
## the body lands flat on its back without first buckling at the knees.
static func back_keys(stance: Dictionary, hips_height: float) -> Array:
	var impact := stance.duplicate()
	impact.merge({
		"lean": -28.0, "chest_pitch": -10.0, "neck": -14.0, "head": -34.0, "twist": 6.0,
		"L_flex": 58.0, "R_flex": 66.0, "L_abd": 30.0, "R_abd": 34.0, "L_elbow": 24.0, "R_elbow": 20.0,
		"L_swing": 22.0, "R_swing": 14.0, "L_knee": 14.0, "R_knee": 18.0,
		"hips_pitch": -18.0, "hips_z": -0.12 * hips_height, "hips_y": -0.02 * hips_height,
	}, true)
	var airborne := impact.duplicate()
	airborne.merge({
		"lean": -14.0, "head": -20.0, "hips_pitch": -58.0, "hips_y": -0.3 * hips_height, "hips_z": -0.36 * hips_height,
		"L_swing": 46.0, "R_swing": 36.0, "L_knee": 22.0, "R_knee": 34.0, "L_ankle": 14.0, "R_ankle": 10.0,
		"L_flex": 88.0, "R_flex": 96.0, "L_abd": 52.0, "R_abd": 58.0,
	}, true)
	var lying := 0.13 * hips_height - hips_height
	var land := airborne.duplicate()
	land.merge({
		"lean": 4.0, "chest_pitch": 0.0, "neck": 6.0, "head": 10.0, "head_turn": -18.0, "twist": 2.0,
		"hips_pitch": -92.0, "hips_y": lying, "hips_z": -0.52 * hips_height,
		"L_swing": 20.0, "R_swing": 12.0, "L_knee": 18.0, "R_knee": 30.0, "L_ankle": 16.0, "R_ankle": 20.0,
		"L_flex": -8.0, "R_flex": -14.0, "L_abd": 82.0, "R_abd": 70.0, "L_elbow": 10.0, "R_elbow": 14.0,
	}, true)
	var bounce := land.duplicate()
	bounce.merge({"hips_pitch": -97.0, "hips_y": lying + 0.06 * hips_height, "L_swing": 28.0, "R_swing": 20.0, "head": 18.0}, true)
	var rest := land.duplicate()
	rest.merge({"hips_pitch": -90.0, "head_turn": -28.0, "L_swing": 10.0, "R_swing": 6.0, "L_knee": 14.0, "R_knee": 26.0}, true)
	return [[0.0, stance], [0.1, impact], [0.32, airborne], [0.56, land], [0.7, bounce], [1.0, rest]]
