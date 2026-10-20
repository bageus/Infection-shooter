shader_type spatial;
// Skill range: a low, see-through dome over the floor. The rim (where the
// dome meets the floor and its silhouette) glows; the inside stays faint so
// the player and enemies under it remain readable.
render_mode blend_mix, unshaded, depth_draw_never, cull_back, shadows_disabled;

instance uniform vec4 tint : source_color = vec4(1.0, 0.2, 0.2, 1.0);
instance uniform float fade = 1.0;
// Dome height in local units (radius is 1 before scaling).
uniform float height = 0.3;

varying float level;
varying float across;

void vertex() {
	level = clamp(VERTEX.y / height, 0.0, 1.0);
	across = length(VERTEX.xz);
}

void fragment() {
	float rim = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 2.5);
	// A thin bright line where the dome meets the floor, a soft glow above it.
	float edge = 1.0 - smoothstep(0.0, 0.035, level);
	float glow = 1.0 - smoothstep(0.0, 0.2, level);
	// Waves running out from the centre over the dome.
	float phase = fract(across * 1.5 - TIME * 0.5);
	float wave = smoothstep(0.0, 0.1, phase) * (1.0 - smoothstep(0.1, 0.45, phase));
	wave *= smoothstep(0.05, 0.3, across) * (1.0 - smoothstep(0.75, 1.0, across)) * 0.16;
	ALBEDO = mix(tint.rgb, vec3(1.0), edge * 0.5);
	ALPHA = clamp((0.05 + rim * 0.25 + glow * 0.12 + wave + edge * 0.7) * fade, 0.0, 1.0);
}
