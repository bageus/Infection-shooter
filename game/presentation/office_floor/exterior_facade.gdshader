shader_type spatial;
// Procedural window grid for the building skirt below the exterior windows.
// UV.x is the distance along the run from its first window edge, UV.y the depth below the
// window frame bottom (metres), so the cells line up with the 2.0 x 3.0 m window modules.
// COLOR.a is 0 on the narrow end caps, which stay plain concrete.
render_mode unshaded, cull_back, shadows_disabled;

const vec2 CELL = vec2(2.0, 3.0);
const vec3 FOG_COLOR = vec3(0.34, 0.44, 0.58);
varying float world_y;

void vertex() {
	world_y = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	vec2 grid = vec2(UV.x / CELL.x, UV.y / CELL.y);
	vec2 cell = fract(grid);
	vec2 aa = min(fwidth(grid), vec2(0.1));
	vec2 border = vec2(0.048, 0.047);
	float pane = smoothstep(border.x, border.x + aa.x, cell.x) * (1.0 - smoothstep(1.0 - border.x - aa.x, 1.0 - border.x, cell.x));
	pane *= smoothstep(border.y, border.y + aa.y, cell.y) * (1.0 - smoothstep(1.0 - border.y - aa.y, 1.0 - border.y, cell.y));
	float mullion = smoothstep(0.5 - 0.016 - aa.x, 0.5 - 0.016, cell.x) * (1.0 - smoothstep(0.5 + 0.016, 0.5 + 0.016 + aa.x, cell.x));
	pane *= 1.0 - mullion;
	pane = mix(0.0, pane, COLOR.a);
	float sheen = 0.5 + 0.5 * sin(UV.x * 0.35 + UV.y * 0.22);
	vec3 glass = mix(vec3(0.09, 0.16, 0.26), vec3(0.27, 0.38, 0.52), sheen);
	vec3 frame = vec3(0.08, 0.10, 0.13);
	vec3 surface = mix(frame, glass, pane);
	float fog = 1.0 - smoothstep(-65.0, -12.0, world_y);
	ALBEDO = mix(surface, FOG_COLOR, fog * 0.9);
}
