extends RefCounted
## The dead hero plays one of the baked death clips (Death_FromRight, Death_Dying, Death_HitToBack, picked at random)
## and holds the last pose. Without those clips (an isolated model) he drops backward from the feet like a plank,
## lands with a small bounce and lies still. Returns after how many seconds the body rests on the floor.
const FALL_SECONDS := 0.55
const BOUNCE_SECONDS := 0.25
const REST_SECONDS := 0.5
## The lying body is lifted by its thickness so the backpack rests on the floor instead of sinking into it.
const LIE_LIFT := 0.2
const META := &"death_fall"
## The screen waits for a death clip this long at most; the rest of a long clip is the body settling.
const CLIP_WAIT_MAX := 2.2
const CLIP_REST_SECONDS := 0.4


static func start(player: Node3D) -> float:
	var body := player.get_node_or_null("Body") as Node3D
	if body == null or body.has_meta(META):
		return 0.0
	body.set_meta(META, true)
	var driver := player.get_node_or_null("AnimationDriver")
	if driver != null and driver.has_method("play_death_clip"):
		var clip_seconds := float(driver.call("play_death_clip"))
		if clip_seconds > 0.0:
			return minf(clip_seconds, CLIP_WAIT_MAX) + CLIP_REST_SECONDS
	var rest := body.basis
	var rest_y := body.position.y
	var tween := player.create_tween()
	# The model faces +Z: a turn of -90 degrees about its X axis lays the head toward its back.
	tween.tween_method(func(angle: float) -> void: body.basis = rest * Basis(Vector3.RIGHT, angle), 0.0, -PI * 0.5, FALL_SECONDS).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(body, "position:y", rest_y + LIE_LIFT, FALL_SECONDS).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_method(func(angle: float) -> void: body.basis = rest * Basis(Vector3.RIGHT, angle), -PI * 0.5, -PI * 0.46, BOUNCE_SECONDS * 0.4)
	tween.tween_method(func(angle: float) -> void: body.basis = rest * Basis(Vector3.RIGHT, angle), -PI * 0.46, -PI * 0.5, BOUNCE_SECONDS * 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	return FALL_SECONDS + BOUNCE_SECONDS + REST_SECONDS
