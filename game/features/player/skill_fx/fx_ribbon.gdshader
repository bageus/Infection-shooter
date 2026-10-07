shader_type spatial;
// A camera-facing strip (UV.x along, UV.y across) with a hot core and a soft
// halo: lightning links and claw slashes. With sweep > 0 the strip is drawn
// in along its length by `progress` and tapers at both ends (a slash).
render_mode blend_premul_alpha, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 color : source_color = vec4(0.35, 0.7, 1.0, 1.0);
uniform vec4 core_color : source_color = vec4(0.95, 0.98, 1.0, 1.0);
uniform float glow : hint_range(0.0, 1.0) = 1.0;
uniform float sweep = 0.0;
uniform float brightness = 1.8;

instance uniform float progress = 0.0;
instance uniform float alpha = 1.0;

void fragment() {
	float across = abs(UV.y - 0.5) * 2.0;
	float body = 1.0;
	if (sweep > 0.5) {
		float head = progress * 2.2;
		float taper = sin(PI * clamp(UV.x, 0.0, 1.0));
		across /= max(taper, 0.05);
		body = step(UV.x, head) * smoothstep(head - 1.4, head - 0.2, UV.x);
		body *= 1.0 - smoothstep(0.55, 1.0, progress);
	}
	float core = exp(-across * across * 14.0);
	float halo = exp(-across * across * 2.5) * 0.55;
	float cover = (core + halo) * body * alpha * COLOR.a;
	vec3 tone = mix(color.rgb, core_color.rgb, core) * brightness;
	ALBEDO = tone * clamp(cover, 0.0, 1.0);
	ALPHA = clamp(cover, 0.0, 1.0) * (1.0 - glow);
}
