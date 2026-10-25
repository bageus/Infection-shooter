shader_type canvas_item;

// Loss of control: a light blur of the scene and a web of greenish capillaries that
// creeps in from the screen edges. One screen read, one 3x3 cell search per pixel.
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform vec4 vein_color : source_color = vec4(0.30, 0.62, 0.22, 1.0);
uniform float strength = 0.0;
uniform float clock = 0.0;

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

// Distance between the two nearest cell points: near zero on the cell borders, which form the web.
float web(vec2 uv) {
	vec2 cell = floor(uv);
	vec2 local = fract(uv);
	float nearest = 8.0;
	float second = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 offset = vec2(float(x), float(y));
			vec2 point = offset + 0.5 + 0.45 * sin(6.2831 * hash2(cell + offset) + clock * 0.6);
			float d = distance(local, point);
			if (d < nearest) {
				second = nearest;
				nearest = d;
			} else if (d < second) {
				second = d;
			}
		}
	}
	return second - nearest;
}

void fragment() {
	vec2 centered = SCREEN_UV - 0.5;
	float edge = smoothstep(0.12, 0.62, length(centered * vec2(1.0, 0.8)));
	vec3 base = textureLod(screen_texture, SCREEN_UV, 2.0).rgb;
	vec3 sharp = textureLod(screen_texture, SCREEN_UV, 0.0).rgb;
	vec3 scene = mix(sharp, base, 0.55 * strength);
	vec2 grid = vec2(SCREEN_UV.x * 9.0 * (SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x), SCREEN_UV.y * 9.0);
	grid += 0.35 * sin(grid.yx * 2.3 + clock * 0.3);
	float w = web(grid);
	float pulse = 0.85 + 0.15 * sin(clock * 2.4);
	float vein = (1.0 - smoothstep(0.0, 0.05 + 0.04 * edge, w)) * edge * pulse;
	float tint = edge * 0.28;
	vec3 result = mix(scene, vein_color.rgb * 0.55, tint * strength);
	result = mix(result, vein_color.rgb, clamp(vein * 1.1, 0.0, 1.0) * strength);
	COLOR = vec4(result, 1.0);
}
