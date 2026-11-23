extends RefCounted
## Keeps arms, hands and head out of walls: an extra upper-body collision disc, wider than the capsule,
## sits at arm height, so the capsule stops further from a wall while the legs and slopes stay unchanged.
## (A bigger safe_margin does the same but also lifts the enemy off the floor.) Bullets use the part hitboxes, not this shape.
const GROW := 1.3  # arm reach in Walk/Run is ~0.75-0.9 m from the body axis, capsule radius 0.45
const MAX_CAPSULE_RADIUS := 0.6  # shortcut: skips giants (Horde), whose reach is already inside their capsule


static func add(enemy: CharacterBody3D, collision_shape: CollisionShape3D) -> void:
	var capsule := collision_shape.shape as CapsuleShape3D
	if capsule == null or capsule.radius > MAX_CAPSULE_RADIUS:
		return
	var disc := CylinderShape3D.new()
	disc.radius = capsule.radius * GROW
	disc.height = capsule.height * 0.45
	var node := CollisionShape3D.new()
	node.name = "WallStandoff"
	node.shape = disc
	node.position = collision_shape.position + Vector3(0.0, capsule.height * 0.2, 0.0)
	enemy.add_child(node)
