shader_type spatial;
// Baked-looking contact shadow along a wall base: darkest at the wall face,
// fading out over the strip's depth. The quad spans -0.5..0.5 locally, with
// its -Z edge on the wall.
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform float strength : hint_range(0.0, 1.0) = 0.5;

varying float away;

void vertex() {
	away = VERTEX.z + 0.5;
}

void fragment() {
	float shade = pow(1.0 - clamp(away, 0.0, 1.0), 2.2);
	ALBEDO = vec3(0.0);
	ALPHA = shade * strength;
}
