extends RefCounted
## Door hint badges: the locked-door icon and the one-way "no entry" sign.
## Both are depth-tested and pushed toward the player, so a character standing
## in front of the door hides them instead of being covered by them.

const BADGE := preload("res://game/core/world_badge/public/world_badge.gd")
const NO_ENTRY_ICON := preload("res://assets/interface/icon/no_entry.png")
const NO_ENTRY_TINT := Color("d8453a")
# Badge centre height in the door's local space, its size, and the offset toward the player.
const HEIGHT := 1.1
const SCALE := 0.8
const FORWARD := 0.3
const RANGE := 3.0

var no_entry: Node3D


static func make(door: Node3D, icon: Texture2D, tint: Color, node_name: String) -> Node3D:
	var badge := BADGE.icon(icon, Rect2(), tint, HEIGHT, true)
	badge.name = node_name
	badge.scale = Vector3.ONE * SCALE
	door.add_child(badge)
	return badge


static func toward_player(badge: Node3D, local_player: Vector3) -> void:
	badge.position.z = signf(local_player.z) * FORWARD


func update_no_entry(door: Node3D, shown: bool, local_player: Vector3) -> void:
	if shown and no_entry == null:
		no_entry = make(door, NO_ENTRY_ICON, NO_ENTRY_TINT, "NoEntryIcon")
	if no_entry != null:
		no_entry.visible = shown
		toward_player(no_entry, local_player)
