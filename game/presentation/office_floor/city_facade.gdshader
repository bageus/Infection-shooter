shader_type spatial;
render_mode cull_back;

varying vec3 facade_position;
varying vec3 facade_normal;

void vertex() {
	facade_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	facade_normal = NORMAL;
}

void fragment() {
	float horizontal = abs(facade_normal.x) > 0.5 ? facade_position.z : facade_position.x;
	vec2 grid = vec2(horizontal / 2.4, facade_position.y / 3.2);
	vec2 cell = fract(grid);
	float pane = step(0.16, cell.x) * step(cell.x, 0.84) * step(0.20, cell.y) * step(cell.y, 0.82);
	pane *= 1.0 - step(0.5, abs(facade_normal.y));
	float seed = dot(floor(grid), vec2(12.9898, 78.233));
	float occupied = step(0.78, fract(sin(seed) * 43758.5453));
	vec3 concrete = vec3(0.24, 0.29, 0.36);
	vec3 glass = mix(vec3(0.055, 0.11, 0.17), vec3(0.18, 0.28, 0.37), cell.y);
	ALBEDO = mix(concrete, glass, pane);
	ROUGHNESS = mix(0.88, 0.38, pane);
	METALLIC = pane * 0.25;
	EMISSION = vec3(0.55, 0.43, 0.26) * pane * occupied * 0.22;
}
