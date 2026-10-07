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

void vertex() {
	level = clamp(VERTEX.y / height, 0.0, 1.0);
}

void fragment() {
	float rim = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 2.5);
	float edge = 1.0 - smoothstep(0.0, 0.12, level);
	ALBEDO = mix(tint.rgb, vec3(1.0), edge * 0.35);
	ALPHA = clamp((0.07 + rim * 0.3 + edge * 0.45) * fade, 0.0, 1.0);
}
