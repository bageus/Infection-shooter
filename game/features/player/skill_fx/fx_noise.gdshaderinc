// Value noise helpers shared by the procedural skill effects.

float fx_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec2 fx_hash2(vec2 p) {
	return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453);
}

float fx_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(fx_hash(i), fx_hash(i + vec2(1.0, 0.0)), f.x), mix(fx_hash(i + vec2(0.0, 1.0)), fx_hash(i + vec2(1.0)), f.x), f.y);
}

float fx_fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 4; i++) {
		value += amplitude * fx_noise(p);
		p = p * 2.03 + vec2(11.7, 5.3);
		amplitude *= 0.5;
	}
	return value;
}

float fx_noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	vec2 offset = vec2(37.0, 17.0) * i.z;
	float a = mix(mix(fx_hash(i.xy + offset), fx_hash(i.xy + offset + vec2(1.0, 0.0)), f.x), mix(fx_hash(i.xy + offset + vec2(0.0, 1.0)), fx_hash(i.xy + offset + vec2(1.0)), f.x), f.y);
	offset += vec2(37.0, 17.0);
	float b = mix(mix(fx_hash(i.xy + offset), fx_hash(i.xy + offset + vec2(1.0, 0.0)), f.x), mix(fx_hash(i.xy + offset + vec2(0.0, 1.0)), fx_hash(i.xy + offset + vec2(1.0)), f.x), f.y);
	return mix(a, b, f.z);
}

// Distance to the nearest of a jittered grid of points, and that cell's id.
vec2 fx_cells(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float best = 8.0;
	float id = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 cell = vec2(float(x), float(y));
			vec2 point = cell + fx_hash2(i + cell) * 0.8 + 0.1;
			float d = length(point - f);
			if (d < best) {
				best = d;
				id = fx_hash(i + cell);
			}
		}
	}
	return vec2(best, id);
}

// Premultiplied output: glow 1 adds light, 0 covers like paint.
vec4 fx_premul(vec3 color, float cover, float glow) {
	cover = clamp(cover, 0.0, 1.0);
	return vec4(color * cover, cover * (1.0 - glow));
}
