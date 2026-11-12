shader_type spatial;
render_mode unshaded, blend_add;

// Red rim glow added over the enemy while it is berserk.
uniform vec3 rage_color : source_color = vec3(0.9, 0.08, 0.02);

void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	ALBEDO = rage_color * (0.25 + rim);
}
