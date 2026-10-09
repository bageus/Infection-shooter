shader_type spatial;
render_mode unshaded, cull_back;
varying vec2 street_uv;
void vertex() { street_uv = UV; }
void fragment() {
	float across = street_uv.y;
	float edge = step(across, 0.08) + step(0.92, across);
	float dash = step(0.6, fract(street_uv.x * 120.0));
	float lane = step(abs(across - 0.5), 0.006) * dash;
	ALBEDO = mix(vec3(0.075, 0.10, 0.15), vec3(0.20, 0.25, 0.31), min(edge, 1.0));
	ALBEDO = mix(ALBEDO, vec3(0.60, 0.50, 0.29), lane);
	float fog = clamp(1.0 - exp(-length(VERTEX) * 0.025), 0.88, 0.99);
	ALBEDO = mix(ALBEDO, vec3(0.34, 0.44, 0.58), fog);
}
