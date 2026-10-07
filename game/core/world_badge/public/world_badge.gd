extends Node3D
## HUD-style badge floating over a world object: a key cap that keeps playing a
## press animation, or an atlas icon in a panel cell. A small SubViewport draws
## the face with the combat HUD palette and a billboarded Sprite3D shows it
## above walls and props. Hidden badges stop rendering.

const SCRIPT_PATH := "res://game/core/world_badge/public/world_badge.gd"
const FONT := preload("res://assets/interface/fonts/body.ttf")
# Mirrors presentation/prototype_hud/hud_palette.gd (core cannot depend on it).
const PANEL := Color("151a1ce0")
const CELL_ACTIVE := Color("242a2cf0")
const KEY_SIDE := Color("0b0e0ff0")
const BORDER := Color("646760b3")
const ACCENT := Color("a52d30")
const INK := Color("e2dfd4")
const SHADOW := Color(0, 0, 0, 0.4)
const PRESS_PERIOD := 1.25
const PRESS_TIME := 0.24
const PIXEL_SIZE := 0.011
const TINT_SHADER := """
shader_type canvas_item;
uniform vec4 tint : source_color = vec4(1.0);
void fragment() {
	vec4 texel = texture(TEXTURE, UV);
	float light = max(texel.r, max(texel.g, texel.b));
	COLOR = vec4(tint.rgb * light, texel.a * tint.a);
}
"""


class KeyFace:
	extends Control
	const CAP := Vector2(62, 58)
	const DEPTH := 9.0
	var label := ""
	var press := 0.0

	func _draw() -> void:
		var origin := Vector2((size.x - CAP.x) * 0.5, (size.y - CAP.y - DEPTH) * 0.5)
		var side := _box(KEY_SIDE, BORDER)
		draw_style_box(_box(SHADOW, Color.TRANSPARENT), Rect2(origin + Vector2(0, DEPTH + 3), CAP))
		draw_style_box(side, Rect2(origin + Vector2(0, DEPTH), CAP))
		var cap_rect := Rect2(origin + Vector2(0, DEPTH * 0.8 * press), CAP)
		draw_style_box(_box(CELL_ACTIVE.lerp(ACCENT, press), BORDER.lerp(ACCENT, press)), cap_rect)
		var font_size := 34 if label.length() <= 1 else (24 if label.length() <= 3 else 16)
		var text_size := FONT.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var baseline := cap_rect.position + Vector2((CAP.x - text_size.x) * 0.5, (CAP.y + FONT.get_ascent(font_size) - FONT.get_descent(font_size)) * 0.5)
		draw_string(FONT, baseline, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, INK)

	func _box(fill: Color, border: Color) -> StyleBoxFlat:
		var box := StyleBoxFlat.new()
		box.bg_color = fill
		box.border_color = border
		box.set_border_width_all(2 if border.a > 0.0 else 0)
		box.set_corner_radius_all(7)
		box.anti_aliasing = true
		return box


class IconFace:
	extends Control
	var texture: Texture2D
	var region := Rect2()
	var tint := INK
	var _material: ShaderMaterial

	func _draw() -> void:
		var frame := StyleBoxFlat.new()
		frame.bg_color = PANEL
		frame.border_color = BORDER
		frame.set_border_width_all(2)
		frame.set_corner_radius_all(8)
		frame.shadow_color = SHADOW
		frame.shadow_size = 4
		var cell := Rect2(Vector2(6, 6), size - Vector2(12, 12))
		draw_style_box(frame, cell)
		draw_rect(Rect2(cell.position + Vector2(2, 8), Vector2(3, cell.size.y - 16)), ACCENT)

	func build_icon() -> void:
		_material = ShaderMaterial.new()
		var shader := Shader.new()
		shader.code = TINT_SHADER
		_material.shader = shader
		_material.set_shader_parameter("tint", tint)
		var icon := TextureRect.new()
		if region.has_area():
			var atlas := AtlasTexture.new()
			atlas.atlas = texture
			atlas.region = region
			icon.texture = atlas
		else:
			icon.texture = texture
		icon.material = _material
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon.offset_left = 20
		icon.offset_top = 16
		icon.offset_right = -16
		icon.offset_bottom = -16
		add_child(icon)


var face: Control
var _viewport: SubViewport
var _sprite: Sprite3D
var _animated := false
var _time := 0.0


static func key(label: String, height := 0.0) -> Node3D:
	var badge: Node3D = load(SCRIPT_PATH).new()
	var key_face := KeyFace.new()
	key_face.label = label
	badge.call("_build", key_face, Vector2i(96, 96), true, height)
	return badge


static func icon(texture: Texture2D, region: Rect2, tint: Color, height := 0.0) -> Node3D:
	var badge: Node3D = load(SCRIPT_PATH).new()
	var icon_face := IconFace.new()
	icon_face.texture = texture
	icon_face.region = region
	icon_face.tint = tint
	badge.call("_build", icon_face, Vector2i(120, 120), false, height)
	icon_face.build_icon()
	return badge


func set_label(label: String) -> void:
	if face is KeyFace and (face as KeyFace).label != label:
		(face as KeyFace).label = label
		face.queue_redraw()
		_sync_render()


func press_amount() -> float:
	return (face as KeyFace).press if face is KeyFace else 0.0


func _build(new_face: Control, pixels: Vector2i, animated: bool, height: float) -> void:
	name = "WorldBadge"
	position.y = height
	_animated = animated
	_viewport = SubViewport.new()
	_viewport.size = pixels
	_viewport.transparent_bg = true
	_viewport.disable_3d = true
	_viewport.gui_disable_input = true
	_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
	add_child(_viewport)
	face = new_face
	face.size = Vector2(pixels)
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport.add_child(face)
	_sprite = Sprite3D.new()
	_sprite.texture = _viewport.get_texture()
	_sprite.pixel_size = PIXEL_SIZE
	_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sprite.shaded = false
	_sprite.no_depth_test = true
	_sprite.render_priority = 10
	_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	add_child(_sprite)


func _ready() -> void:
	_sync_render()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and _viewport != null:
		_sync_render()


func _process(delta: float) -> void:
	_time = fmod(_time + delta, PRESS_PERIOD)
	var key_face := face as KeyFace
	key_face.press = sin(PI * _time / PRESS_TIME) if _time < PRESS_TIME else 0.0
	key_face.queue_redraw()


func _sync_render() -> void:
	var shown := is_inside_tree() and is_visible_in_tree()
	if not shown:
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_time = 0.0
	elif _animated:
		_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	else:
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	set_process(shown and _animated)
