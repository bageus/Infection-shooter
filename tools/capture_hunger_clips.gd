extends SceneTree
## Renders contact sheets of the Hunger's Mixamo clips (ADR-0045).
##
##   xvfb-run -a godot --path . --rendering-method gl_compatibility \
##     --fixed-fps 30 --script res://tools/capture_hunger_clips.gd -- <out_dir>
##
## One sheet per group (stand, low, transitions, actions): a row per clip, eight
## frames evenly spaced over the clip, seen from the side.

const RIG := preload("res://models/objects/characters/enemy/game/Hunger_rig.tscn")
const CLIPS := preload("res://models/objects/characters/enemy/game/Hunger_mixamo.res")
const FRAMES := 8
const CELL := Vector2i(300, 260)
const FLOOR_LIFT := 0.951
const GROUPS := {
	"stand": ["Idle", "Walk", "Run", "RunLunge", "Scream", "HitReaction"],
	"low": ["FoursRun", "Crawl", "FoursIdle", "CrawlIdle", "CrawlAttack", "BiteLoop"],
	"transitions": ["DropToFours", "RiseFromFours", "CollapseToCrawl", "FoursToCrawl", "BiteDown", "BiteUp"],
	"actions": ["AttackRight", "AttackLeft", "AttackRight2", "AttackLeft2", "TurnRight", "TurnLeft", "Agonize"],
}

var _out_dir := "/tmp/hunger_clips"
var _view: SubViewport


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_out_dir = args[0]
	call_deferred("_capture")


func _capture() -> void:
	DirAccess.make_dir_recursive_absolute(_out_dir)
	var stage := Node3D.new()
	root.add_child(stage)
	_build_stage(stage)
	_view = _make_view(stage)
	var rig := RIG.instantiate() as Node3D
	rig.position.y = FLOOR_LIFT
	rig.rotation_degrees.y = 90.0 # faces +X, across the side view
	stage.add_child(rig)
	var player := rig.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	player.add_animation_library(&"mx", CLIPS)
	var only := OS.get_cmdline_user_args()[1] if OS.get_cmdline_user_args().size() > 1 else ""
	for group: String in GROUPS:
		if not only.is_empty() and only != group:
			continue
		var sheet := Image.create(CELL.x * FRAMES, CELL.y * GROUPS[group].size(), false, Image.FORMAT_RGBA8)
		var row := 0
		for clip_name: String in GROUPS[group]:
			var animation := CLIPS.get_animation(clip_name)
			player.play("mx/" + clip_name)
			player.pause()
			for frame in FRAMES:
				player.seek(animation.length * float(frame) / float(FRAMES - 1 if animation.loop_mode == Animation.LOOP_NONE else FRAMES), true)
				for i in 2:
					await process_frame
				await RenderingServer.frame_post_draw
				var image := _view.get_texture().get_image()
				image.convert(Image.FORMAT_RGBA8)
				sheet.blit_rect(image, Rect2i(Vector2i.ZERO, CELL), Vector2i(frame * CELL.x, row * CELL.y))
			row += 1
		sheet.save_png(_out_dir.path_join(group + ".png"))
	print("Sheets written to ", _out_dir)
	quit(0)


func _make_view(stage: Node3D) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = CELL
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	viewport.world_3d = stage.get_world_3d()
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.2
	viewport.add_child(camera)
	camera.look_at_from_position(Vector3(0.0, 0.95, -6.0), Vector3(0.0, 0.95, 0.0))
	camera.current = true
	return viewport


func _build_stage(stage: Node3D) -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.82, 0.84, 0.86)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.7, 0.7, 0.72)
	var world := WorldEnvironment.new()
	world.environment = environment
	stage.add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	stage.add_child(light)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(8.0, 8.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.45, 0.47, 0.5)
	plane.material = material
	floor_mesh.mesh = plane
	stage.add_child(floor_mesh)
