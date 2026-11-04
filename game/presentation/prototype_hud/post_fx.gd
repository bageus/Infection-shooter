extends CanvasLayer
## Post-processing under the HUD: an always-on cheap grade (tint, vignette, grain)
## and a short chromatic-aberration flash when the player loses health.
##
## Sits on layer -1 so it grades the 3D view only. The hit pass reads the screen
## texture, so its rect is hidden unless a hit is fading out.

const BASE_SHADER := preload("res://game/presentation/prototype_hud/post_fx_base.gdshader")
const HIT_SHADER := preload("res://game/presentation/prototype_hud/post_fx_hit.gdshader")

const HIT_MIN := 0.35
const HIT_PER_HEALTH := 2.0
const HIT_DECAY := 4.0

var hit := 0.0
var enabled := true

var _base: ColorRect
var _hit_rect: ColorRect
var _hit_material: ShaderMaterial
var _last_health := -1.0


func _ready() -> void:
	layer = -1
	_base = _make_rect("Base", BASE_SHADER)
	_hit_rect = _make_rect("Hit", HIT_SHADER)
	_hit_material = _hit_rect.material as ShaderMaterial
	_hit_rect.visible = false
	_base.resized.connect(_update_aspect)
	_update_aspect()


## Hit strength 0..1 for a health loss: a floor so small hits still read, growing with the loss.
static func hit_for_loss(loss: float, max_health: float) -> float:
	if loss <= 0.0 or max_health <= 0.0:
		return 0.0
	return clampf(HIT_MIN + HIT_PER_HEALTH * loss / max_health, 0.0, 1.0)


func set_enabled(value: bool) -> void:
	enabled = value
	if not value:
		hit = 0.0
	_apply()


func update(delta: float, health: float, max_health: float) -> void:
	if _last_health >= 0.0:
		hit = maxf(hit, hit_for_loss(_last_health - health, max_health))
	_last_health = health
	hit = maxf(0.0, hit - delta * HIT_DECAY)
	_apply()


func _apply() -> void:
	var parent := get_parent() as CanvasItem
	var shown := enabled and (parent == null or parent.is_visible_in_tree())
	_base.visible = shown
	_hit_rect.visible = shown and hit > 0.0
	_hit_material.set_shader_parameter("hit", hit)


func _make_rect(node_name: String, shader: Shader) -> ColorRect:
	var rect := ColorRect.new()
	rect.name = node_name
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = shader
	rect.material = material
	add_child(rect)
	return rect


func _update_aspect() -> void:
	if _base.size.y > 0.0:
		(_base.material as ShaderMaterial).set_shader_parameter("aspect", _base.size.x / _base.size.y)
