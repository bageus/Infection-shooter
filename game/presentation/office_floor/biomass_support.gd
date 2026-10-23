extends RefCounted
## What really stands behind a patch of biomass on a wall or an object
## (ADR-0062). The edge fit works on the receiver's bounding box, so a window
## frame (box = the whole opening) or an object that broke apart still looked
## whole. This samples a coarse grid across the patch with short rays through its
## plane and keeps the answer as a small mask the shader discards by: mass over
## empty space is cut, never left hanging.

const COLUMNS := 12
const ROWS := 18
## Rays run this far in front of and behind the plane of the patch.
const REACH := 0.12
const WORLD_MASK := 7
## Below this share of supported samples the receiver has no collision to go
## by (props whose collision is off), so the mask is left out rather than
## hiding the whole patch.
const MIN_SHARE := 0.1


## frame: the patch's global transform; rect: the patch (or fused group) in local
## units. Returns {support: ImageTexture, support_rect: Vector4}, or {} when there
## is nothing to go by.
static func sample(frame: Transform3D, rect: Rect2, space: PhysicsDirectSpaceState3D) -> Dictionary:
	if space == null or rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return {}
	var normal := frame.basis.z.normalized()
	var image := Image.create(COLUMNS, ROWS, false, Image.FORMAT_L8)
	var supported := 0
	for row in ROWS:
		for column in COLUMNS:
			var local := Vector3(rect.position.x + (column + 0.5) / COLUMNS * rect.size.x, rect.position.y + (row + 0.5) / ROWS * rect.size.y, 0.0)
			var at := frame * local
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(at + normal * REACH, at - normal * REACH, WORLD_MASK))
			var solid := not hit.is_empty() and not hit["collider"] is CharacterBody3D and (hit["normal"] as Vector3).dot(normal) > 0.2
			image.set_pixel(column, row, Color.WHITE if solid else Color.BLACK)
			supported += 1 if solid else 0
	if float(supported) / (COLUMNS * ROWS) < MIN_SHARE:
		return {}
	return {"support": ImageTexture.create_from_image(image), "support_rect": Vector4(rect.position.x, rect.position.y, rect.size.x, rect.size.y)}
