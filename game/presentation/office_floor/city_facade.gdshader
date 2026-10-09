shader_type spatial;
render_mode cull_back;

varying vec3 facade_position;
varying vec3 facade_normal;
varying vec3 style;

void vertex() {
	facade_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	facade_normal = NORMAL;
	style = COLOR.rgb;
}

void fragment() {
	float horizontal = abs(facade_normal.x) > 0.5 ? facade_position.z : facade_position.x;
	float variant = floor(style.r * 3.0);
	vec2 grid = vec2(horizontal / (2.2 + variant * 0.4), facade_position.y / 3.2);
	vec2 cell = fract(grid);
	float border = variant < 1.0 ? 0.06 : 0.14;
	float pane = step(border, cell.x) * step(cell.x, 1.0 - border) * step(0.14, cell.y) * step(cell.y, 0.94);
	pane *= 1.0 - step(0.5, abs(facade_normal.y));
	float seed = dot(floor(grid), vec2(12.9898, 78.233)) + style.b * 97.0;
	float occupied = step(0.83, fract(sin(seed) * 43758.5453));
	float reflection = 0.5 + 0.5 * sin(horizontal * 0.045 + facade_position.y * 0.026);
	vec3 concrete = mix(vec3(0.22, 0.28, 0.35), vec3(0.42, 0.46, 0.51), style.r);
	vec3 glass = mix(vec3(0.075, 0.14, 0.22), vec3(0.24, 0.36, 0.47), reflection);
	vec3 lit_window = vec3(0.56, 0.43, 0.26);
	vec3 surface = mix(concrete, mix(glass, lit_window, occupied * 0.60), pane);
	float haze = style.g * 0.74;
	vec3 haze_color = vec3(0.29, 0.39, 0.53);
	ALBEDO = mix(surface, haze_color, haze);
	ROUGHNESS = mix(0.9, 0.48, pane);
	METALLIC = pane * 0.18;
	EMISSION = lit_window * pane * occupied * 0.38 * (1.0 - haze) + haze_color * haze * 0.45;
}
