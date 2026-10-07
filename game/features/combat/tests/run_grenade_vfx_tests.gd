extends SceneTree
## Runtime checks for the grenade launcher explosion: the 12-frame sheet (or
## the layered fallback), procedural smoke and the lingering smoke column.

const EXPLOSION := preload("res://game/features/combat/grenade_explosion_v1.tscn")
const ATLASES := preload("res://game/core/vfx/public/effect_atlases.gd")
const FLIPBOOK := preload("res://game/core/vfx/public/sprite_flipbook.gd")
const SMOKE_SHADER := preload("res://game/core/vfx/public/smoke_puff.gdshader")

const DAMAGE := preload("res://game/features/combat/public/grenade_explosion.gd")
class Recipient extends StaticBody3D:
	func take_damage(_amount: float) -> void:
		pass

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_recipients()
	var stage := Node3D.new()
	root.add_child(stage)
	var blast := EXPLOSION.instantiate() as Node3D
	stage.add_child(blast)
	blast.global_position = Vector3(0, 0.5, 0)
	blast.call("start", Vector3.UP)
	await process_frame
	var sheet := blast.find_children("Flipbook*", "", false, false)
	_expect(sheet.size() == 1, "The explosion plays the 12-frame sheet.")
	_expect(blast.get_node_or_null("Flash") == null, "The sheet replaces the old layered sprites.")
	if sheet.size() == 1:
		# Six rendered frames are enough to leave the flash, even after a first-use hitch.
		for i in 6:
			await process_frame
		_expect(float((sheet[0] as GeometryInstance3D).get_instance_shader_parameter(&"frame_position")) >= 2.0, "The flash frames go by quickly.")
	var spans: Array = ATLASES.GRENADE_EXPLOSION["durations"]
	_expect(float(spans[0]) * 4.0 <= float(spans[spans.size() - 1]), "Flash frames play fast and the closing smoke frames slowly.")
	var wisps := blast.get_node("SmokeWisps") as GPUParticles3D
	_expect(((wisps.draw_pass_1 as PrimitiveMesh).material as ShaderMaterial).shader == SMOKE_SHADER, "Smoke puffs use the procedural smoke shader.")
	await create_timer(0.5).timeout
	var lingering := blast.get_node_or_null("LingeringSmoke") as GPUParticles3D
	_expect(lingering != null and lingering.emitting, "A lingering smoke column rises after the blast.")
	_expect(lingering != null and lingering.lifetime >= 3.0, "The lingering smoke stays for seconds.")
	await create_timer(2.0).timeout
	_expect(is_instance_valid(blast), "The effect stays alive while the smoke lingers.")
	await create_timer(3.0).timeout
	_expect(not is_instance_valid(blast), "The effect frees itself once the smoke is gone.")
	stage.queue_free()
	await process_frame
	print("Grenade VFX tests: %d failure(s)." % failures)
	quit(failures)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _test_recipients() -> void:
	var wall := StaticBody3D.new()
	var damageable := Recipient.new()
	var debris := RigidBody3D.new()
	_expect(not DAMAGE._receives_blast(wall), "Inert walls skip shelter rays")
	_expect(DAMAGE._receives_blast(damageable), "Damage callback keeps its recipient")
	_expect(DAMAGE._receives_blast(debris), "Impulse-only debris remains a recipient")
	debris.freeze = true
	_expect(not DAMAGE._receives_blast(debris), "Frozen inert debris skips shelter rays")
	wall.free()
	damageable.free()
	debris.free()
