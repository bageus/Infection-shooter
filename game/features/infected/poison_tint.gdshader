shader_type spatial;
// Overlay on a poisoned infected: a sickly green wash, stronger at the rim and
// slowly pulsing, over the body's own shading.
render_mode blend_mix, unshaded, depth_draw_never, cull_back, shadows_disabled;

uniform vec4 tint : source_color = vec4(0.3, 0.8, 0.12, 1.0);
uniform float strength : hint_range(0.0, 1.0) = 0.24;
instance uniform float fade = 1.0;

void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	float pulse = 0.85 + 0.15 * sin(TIME * 4.0);
	ALBEDO = tint.rgb;
	ALPHA = clamp((strength + rim * 0.3) * pulse * fade, 0.0, 1.0);
}
