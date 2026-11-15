extends Node
## The model draws the gun, the hands, the magazines and the backpack with baked clips. This node only keeps the
## gameplay weapon (shots, flash, casings) on the model's muzzle, starts the reload clip and spins the minigun barrels.

const FLASHLIGHT := preload("res://game/features/player/player_flashlight.gd")
const MUZZLE_RISE_DEGREES := 5.0
## The model's barrel runs along +X, the weapon's muzzle marker along -Z.
const BARREL_TURN := Basis(Vector3.UP, -PI * 0.5)
const MAX_RELOAD_SPEED := 3.0
## Weapon name -> clip and node suffix in the model.
const MODEL_GUNS := {"PISTOL": "Pistol", "UZI": "Uzi", "SHOTGUN": "Shotgun", "GRENADE LAUNCHER": "Launcher", "AK": "AK", "M4": "M4", "SNIPER RIFLE": "Sniper", "MINIGUN": "Minigun"}
var skeleton: Skeleton3D
## The player's ShotRecoil, source of the visual kick; null in isolated scenes.
var recoil: RefCounted
var _active: Node3D
var _aim_target := Vector3.INF
var _model: Node3D
var _model_muzzle: Node3D
var _model_barrels: Node3D
var _reload_clip: StringName = &""
var _loaded := 0
var _driver: Node
var _flashlight: Node


func _ready() -> void:
	_model = get_parent().get_node("Body") as Node3D
	skeleton = _model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	if skeleton == null or skeleton.find_bone("RightHand") < 0:
		push_error("Player weapon mount requires Skeleton3D/RightHand")
		return
	_driver = get_parent().get_node_or_null("AnimationDriver")
	recoil = get_parent().get("_shot_recoil")
	_flashlight = FLASHLIGHT.new()
	_flashlight.name = "FlashlightRig"
	add_child(_flashlight)
	var kick := preload("res://game/features/player/player_kick_pose.gd").new()
	kick.name = "KickPose"
	kick.mount = self
	skeleton.add_child(kick)
	skeleton.skeleton_updated.connect(_sync_active)


func select_weapon(weapon: Node3D) -> void:
	_end_reload()
	_active = weapon
	var gun: String = MODEL_GUNS.get(weapon.call("get_weapon_name"), "")
	_model_muzzle = _model.find_child(gun + "_Muzzle", true, false) as Node3D
	_model_barrels = _model.find_child("BarrelCluster", true, false) as Node3D if gun == "Minigun" else null
	_flashlight.attach(_model_muzzle)
	# The weapon's own meshes stay hidden (the model's gun is drawn instead); its markers stay visible, they carry the muzzle flash and smoke.
	var visual := weapon.get_node_or_null("Body") as Node3D
	if visual != null:
		for mesh in visual.find_children("*", "MeshInstance3D", true, false):
			(mesh as MeshInstance3D).hide()
	_loaded = int(weapon.call("get_magazine_ammo"))
	sync_weapon(weapon)


## Puts the weapon's muzzle on the model's muzzle.
func sync_weapon(weapon: Node3D) -> void:
	var muzzle := weapon.get_node_or_null("Muzzle") as Node3D
	if not is_instance_valid(_model_muzzle) or muzzle == null or not _model_muzzle.is_inside_tree() or not weapon.is_inside_tree():
		return
	var at := _model_muzzle.global_transform
	# Before the first clip frame (and between guns in a blend) the model's gun is scaled to nothing.
	if absf(at.basis.determinant()) < 0.001:
		return
	var barrel := Transform3D(at.basis.orthonormalized() * BARREL_TURN, at.origin)
	weapon.global_transform = barrel * muzzle.transform.affine_inverse()


func aim_at(target: Vector3) -> void:
	_aim_target = target
	if is_instance_valid(_active):
		sync_weapon(_active)


func _process(_delta: float) -> void:
	if not is_instance_valid(_active):
		return
	_update_reload()
	var cluster: Variant = _active.get("_barrel_cluster")
	if _model_barrels != null and cluster != null:
		_model_barrels.transform = (cluster as Node3D).transform


func _update_reload() -> void:
	var reloading := bool(_active.call("is_reloading"))
	var ammo := int(_active.call("get_magazine_ammo"))
	# A shotgun takes one shell per cycle: the insert clip restarts with every shell.
	var next_shell: bool = reloading and not _reload_clip.is_empty() and ammo > _loaded
	_loaded = ammo
	if reloading and (_reload_clip.is_empty() or next_shell):
		_start_reload()
	elif not reloading and not _reload_clip.is_empty():
		_end_reload()


func _start_reload() -> void:
	if _driver == null:
		return
	var gun: String = MODEL_GUNS.get(_active.call("get_weapon_name"), "")
	var clip := StringName("Reload_" + gun + ("_Insert" if bool(_active.get("shotgun_shell_reload")) else ""))
	var seconds := maxf(float(_active.get("reload_time")), 0.05)
	# The baked clip is longer than the weapon's reload time: it is played faster, the timing stays the weapon's.
	var speed := minf(float(_driver.call("clip_length", clip)) / seconds, MAX_RELOAD_SPEED)
	var legs: StringName = get_parent().get("_animation_selection").select_clip()
	if float(_driver.call("play_named_one_shot", clip, 0.08, speed, legs)) > 0.0:
		_reload_clip = clip


func _end_reload() -> void:
	if _reload_clip.is_empty() or _driver == null:
		_reload_clip = &""
		return
	_driver.call("cancel_one_shot", _reload_clip)
	_reload_clip = &""


func _sync_active() -> void:
	if not is_instance_valid(_active):
		return
	sync_weapon(_active)
	# Muzzle rise is drawn only here, so aim and bullets keep the unkicked weapon pose.
	var kick := float(recoil.get("kick")) if recoil != null else 0.0
	if kick > 0.0:
		_active.global_basis = Basis(_active.global_basis.x.normalized(), deg_to_rad(MUZZLE_RISE_DEGREES) * kick) * _active.global_basis


func _exit_tree() -> void:
	if is_instance_valid(skeleton) and skeleton.skeleton_updated.is_connected(_sync_active):
		skeleton.skeleton_updated.disconnect(_sync_active)
