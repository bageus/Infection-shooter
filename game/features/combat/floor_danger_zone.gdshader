shader_type spatial;
// Blast warning on the floor (unit quad, radius 1 at the edge): a hair-thin
// ring at the radius, a faint fill that deepens toward it, and slow waves
// that run out from the centre so the zone reads as live, not painted on.
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 tint : source_color = vec4(1.0, 0.35, 0.25, 1.0);
uniform float wave_speed = 0.5;
uniform float wave_count = 1.6;

instance uniform float fade = 1.0;

void fragment() {
	float r = length((UV - 0.5) * 2.0);
	float line = 1.0 - smoothstep(0.0, 0.014, abs(r - 0.985));
	float rim = pow(clamp(r, 0.0, 1.0), 5.0) * 0.2;
	float phase = fract(r * wave_count - TIME * wave_speed);
	float wave = smoothstep(0.0, 0.1, phase) * (1.0 - smoothstep(0.1, 0.45, phase));
	wave *= smoothstep(0.04, 0.3, r) * (1.0 - smoothstep(0.75, 0.98, r)) * 0.2;
	float cover = (0.05 + rim + wave + line * 0.85) * (1.0 - smoothstep(0.99, 1.0, r)) * fade;
	ALBEDO = mix(tint.rgb, vec3(1.0), line * 0.4);
	ALPHA = clamp(cover, 0.0, 1.0);
}
