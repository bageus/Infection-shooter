shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// Expanding soft ring on the floor under a healed player.
uniform vec4 tint : source_color = vec4(0.42, 0.95, 0.55, 1.0);
uniform float progress : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	float radius = mix(0.18, 0.95, progress);
	float width = mix(0.16, 0.05, progress);
	float ring = smoothstep(width, 0.0, abs(d - radius));
	float fill = (1.0 - smoothstep(0.0, radius, d)) * 0.25;
	float fade = 1.0 - progress;
	ALBEDO = tint.rgb;
	ALPHA = clamp((ring + fill) * fade * fade * tint.a, 0.0, 1.0);
}
