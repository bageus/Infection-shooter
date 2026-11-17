shader_type spatial;
// Soft round shadow under a character: darkest in the middle, fading to the rim.
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform float strength : hint_range(0.0, 1.0) = 0.55;

varying vec2 spot;

void vertex() {
	spot = VERTEX.xz * 2.0;
}

void fragment() {
	ALBEDO = vec3(0.0);
	ALPHA = pow(1.0 - clamp(length(spot), 0.0, 1.0), 1.6) * strength;
}
