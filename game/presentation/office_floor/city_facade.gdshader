shader_type spatial;
// Decorative city has baked facade illumination independent of office lights.
render_mode unshaded, cull_back;
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
	float variant = floor(min(style.r, 0.999) * 3.0);
	vec2 grid = vec2(horizontal / (2.2 + variant * 0.4), facade_position.y / 3.2);
	vec2 cell = fract(grid);
	vec2 aa = min(fwidth(grid), vec2(0.1));
	float border = variant < 1.0 ? 0.035 : 0.10;
	float pane = smoothstep(border, border + aa.x, cell.x) * (1.0 - smoothstep(1.0-border-aa.x, 1.0-border, cell.x));
	pane *= smoothstep(0.11, 0.11 + aa.y, cell.y) * (1.0 - smoothstep(0.94-aa.y, 0.94, cell.y));
	pane *= 1.0 - step(0.5, abs(facade_normal.y));
	float seed = dot(floor(grid), vec2(12.9898, 78.233)) + style.b * 97.0;
	float occupied = step(0.78, fract(sin(seed) * 43758.5453));
	float reflection = 0.5 + 0.5 * sin(horizontal * 0.06 + facade_position.y * 0.03 + style.b * 6.0);
	vec3 concrete = mix(vec3(0.24, 0.30, 0.39), vec3(0.45, 0.49, 0.56), style.r);
	vec3 glass = mix(vec3(0.11, 0.19, 0.29), vec3(0.29, 0.40, 0.53), reflection);
	vec3 warm = vec3(0.78, 0.59, 0.32);
	float divider = step(0.48, cell.x) * step(cell.x, 0.53);
	vec3 window = mix(glass, warm, occupied * 0.85);
	window = mix(window, vec3(0.12, 0.17, 0.24), divider * 0.65);
	vec3 surface = mix(concrete, window, pane);
	float side_shade = 0.82 + 0.18 * max(facade_normal.z, 0.0);
	surface *= side_shade;
	float haze = style.g * 0.76;
	ALBEDO = mix(surface, vec3(0.34, 0.44, 0.58), haze);
}
