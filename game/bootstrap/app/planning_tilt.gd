extends RefCounted
## Lay planner objects on their side: quarter turns about the object's horizontal X or Z axis.
## The lay is kept as a pose basis below the yaw, so the orientation stays exact;
## Euler angles read back from a laid object (X = 90) are ambiguous and are never used for turns.
const SURFACE := preload("res://game/bootstrap/app/planning_surface_placement.gd")


## Pose before yaw, from the node's current orientation.
static func pose_of(node: Node3D) -> Basis:
	return Basis.from_euler(Vector3(0.0, node.rotation.y, 0.0)).inverse() * node.basis.orthonormalized()


static func turned(pose: Basis, along_x: bool) -> Basis:
	var quarter := Vector3(PI * 0.5, 0.0, 0.0) if along_x else Vector3(0.0, 0.0, PI * 0.5)
	return pose * Basis.from_euler(quarter)


## Orientation is yaw (radians, world up) times pose; the node's scale is kept.
static func write(node: Node3D, yaw: float, pose: Basis) -> void:
	var orientation := Basis.from_euler(Vector3(0.0, yaw, 0.0)) * pose
	node.transform = Transform3D(orientation.scaled(node.scale), node.position)


static func turn(node: Node3D, along_x: bool) -> void:
	write(node, node.rotation.y, turned(pose_of(node), along_x))


## World height of the lowest point of bounds (node-local AABB).
static func bottom_y(node: Node3D, bounds: AABB) -> float:
	return node.global_position.y + (Transform3D(node.global_basis, Vector3.ZERO) * bounds).position.y


## Rest the lowest point on surface_y (or the floor, when it is higher).
static func ground(node: Node3D, bounds: AABB, surface_y: float) -> void:
	node.global_position.y = SURFACE.ground_height(node, bounds, surface_y)
