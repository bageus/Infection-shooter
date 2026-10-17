extends RefCounted
## Build rig damage geometry separately from animation playback.
const BODY_PARTS := preload("res://game/features/infected/body_parts.gd")

static func animation(actor: Node) -> void:
	var driver: Node = actor.get_node_or_null("AnimationDriver")
	if driver != null:
		driver.call("prepare_visual")


static func parts(actor: Node) -> void:
	if actor._parts != null or actor.has_meta("visual_parts_prepared"):
		return
	actor.set_meta("visual_parts_prepared", true)
	var component := BODY_PARTS.new()
	component.name = "BodyParts"
	actor.add_child(component)
	var size: float = actor.body_visual.scale.x if actor.body_visual != null else 1.0
	if component.setup(actor, actor.body_visual, actor.max_health * actor.dismember_strength_scale * size):
		actor._parts = component
		component.part_severed.connect(actor._on_part_severed)
	else:
		component.queue_free()


static func ensure(actor: Node) -> void:
	animation(actor)
	parts(actor)
