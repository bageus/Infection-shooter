shader_type spatial;
// Berserk eyes behind the mask: a soft, dim red glow that flickers, never a
// sharp point. Camera-facing quad, additive.
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.1, 0.04, 1.0);
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
instance uniform float phase = 0.0;

void vertex() {
	float s = length(MODEL_MATRIX[0].xyz);
	vec3 world = MODEL_MATRIX[3].xyz + (INV_VIEW_MATRIX[0].xyz * VERTEX.x + INV_VIEW_MATRIX[1].xyz * VERTEX.y) * s;
	// Nudged toward the camera so the mask surface never hides the glow.
	world += normalize(INV_VIEW_MATRIX[3].xyz - world) * 0.04;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

void fragment() {
	vec2 d = (UV - 0.5) * vec2(1.0, 1.6);
	float glow = exp(-dot(d, d) * 14.0);
	float flicker = 0.65 + 0.2 * sin(TIME * 6.1 + phase) + 0.15 * sin(TIME * 15.7 + phase * 2.0);
	ALBEDO = color.rgb;
	ALPHA = clamp(glow * flicker * intensity, 0.0, 1.0);
}
