extends RefCounted
## Stops every positional ambience loop and gives the audio thread a moment to let go of the streams,
## so the engine's "resources still in use at exit" error does not fail a test that only ran a map.


static func release(tree: SceneTree) -> void:
	for player: Node in tree.root.find_children("*", "AudioStreamPlayer3D", true, false):
		(player as AudioStreamPlayer3D).stop()
	await tree.create_timer(0.3).timeout
