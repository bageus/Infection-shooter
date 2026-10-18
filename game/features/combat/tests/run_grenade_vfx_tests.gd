extends SceneTree
## Runtime checks for the procedural grenade launcher fire, flash, smoke
## and the lingering smoke column, without any imported sprite sheet.

const EXPLOSION := preload("res://game/features/combat/grenade_explosion_v1.tscn")
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
	_expect(blast.find_children("Flipbook*", "", false, false).is_empty(), "Explosion uses only procedural particles, without a sheet.")
	var embers := blast.get_node("FireEmbers") as GPUParticles3D
	_expect(embers.draw_pass_1 != null and embers.process_material != null, "Procedural fire has geometry and motion.")
	_expect(blast.get_node("ImpactLight").light_energy > 0.0, "Explosion keeps its gameplay flash.")
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
