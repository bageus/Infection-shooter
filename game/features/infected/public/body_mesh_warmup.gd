extends RefCounted
## Builds the body geometry of one enemy kind before a fight. The first enemy of a kind pays for it
## (about 0.8 s, one frame) because body_part_mesh caches the derived geometry per mesh; every later
## one prepares from the cache in under a millisecond. A scene is built, so the cache fills, and freed
## at once, before any other code can see it.


## Returns false when the scene is missing. `host` only needs to be in the tree.
static func warm(host: Node, scene_path: String) -> bool:
	if not ResourceLoader.exists(scene_path):
		return false
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return false
	var holder := Node3D.new()
	holder.visible = false
	host.add_child(holder)
	# Without a visual budget the enemy prepares its body parts in _ready, which fills the cache.
	holder.add_child(packed.instantiate())
	holder.free()
	return true
