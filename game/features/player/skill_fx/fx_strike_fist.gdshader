shader_type spatial;
// Power Strike fist (blood): a clenched fist seen from above, knuckles forward,
// with a bright wet rim and gaps between the fingers. Cracks run through it and
// each shard (instance `cell` >= 0) shows only its own piece of the fist, so the
// pieces can fly apart and fall separately.
render_mode blend_premul_alpha, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

#include "res://game/features/player/skill_fx/fx_noise.gdshaderinc"

const float PAD = 1.5;
const int CELLS = 9;

uniform float brightness = 1.5;

// x = half width, y = half length of the fist, in metres.
instance uniform vec2 size = vec2(0.75, 0.8);
instance uniform float alpha = 1.0;
instance uniform float crack = 0.0;
// -1 draws the whole fist, 0..8 only that piece.
instance uniform float cell = -1.0;
instance uniform float spin = 0.0;

vec2 seed_point(int i) {
	vec2[CELLS] points = vec2[](
		vec2(-0.55, 0.55), vec2(-0.1, 0.65), vec2(0.4, 0.6),
		vec2(-0.45, 0.0), vec2(0.05, 0.1), vec2(0.5, -0.05),
		vec2(-0.3, -0.6), vec2(0.15, -0.55), vec2(0.0, -0.95));
	return points[i];
}

float smin(float a, float b, float k) {
	float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
	return mix(b, a, h) - k * h * (1.0 - h);
}

float sd_box(vec2 p, vec2 b, float r) {
	vec2 d = abs(p) - b + r;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - r;
}

// Fist silhouette, p.y > 0 is the front: a blocky palm, four packed fingers with a
// nearly straight knuckle line, the thumb folded across the side, a thick wrist.
float sd_fist(vec2 p) {
	float d = sd_box(p - vec2(0.0, 0.1), vec2(0.62, 0.5), 0.12);
	for (int i = 0; i < 4; i++) {
		float x = -0.45 + float(i) * 0.3;
		d = smin(d, sd_box(p - vec2(x, 0.5), vec2(0.15, 0.27), 0.1), 0.05);
	}
	d = smin(d, sd_box(p - vec2(0.64, 0.12), vec2(0.18, 0.3), 0.15), 0.08);
	d = smin(d, sd_box(p - vec2(0.0, -0.6), vec2(0.46, 0.4), 0.1), 0.1);
	return d;
}

void vertex() {
	vec3 center = MODEL_MATRIX[3].xyz;
	vec3 forward = normalize(-MODEL_MATRIX[2].xyz);
	vec3 side = normalize(cross(forward, INV_VIEW_MATRIX[3].xyz - center));
	vec3 world = center + side * VERTEX.x * 2.0 * size.x * PAD + forward * VERTEX.y * 2.0 * size.y * PAD;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

void fragment() {
	vec2 p = vec2(UV.x - 0.5, 0.5 - UV.y) * 2.0 * PAD;
	if (cell >= 0.0) {
		vec2 c = seed_point(int(cell + 0.5));
		float s = sin(-spin);
		float k = cos(-spin);
		p = c + mat2(vec2(k, s), vec2(-s, k)) * (p - c);
	}
	float d = sd_fist(p);
	float nearest = 9.0;
	float second = 9.0;
	int owner = 0;
	for (int i = 0; i < CELLS; i++) {
		float dist = length(p - seed_point(i));
		if (dist < nearest) {
			second = nearest;
			nearest = dist;
			owner = i;
		} else if (dist < second) {
			second = dist;
		}
	}
	float inside = 1.0 - smoothstep(-0.01, 0.03, d);
	if (cell >= 0.0 && owner != int(cell + 0.5)) {
		inside = 0.0;
	}
	float n = fx_fbm(p * 3.0 + vec2(0.0, TIME * 1.5));
	float rim = smoothstep(-0.1, 0.0, d);
	// Dark creases between the fingers and under the thumb keep them readable.
	float crease = 0.0;
	for (int i = 0; i < 3; i++) {
		float x = -0.3 + float(i) * 0.3;
		crease += (1.0 - smoothstep(0.0, 0.035, abs(p.x - x))) * smoothstep(-0.05, 0.25, p.y) * (1.0 - smoothstep(0.55, 0.75, p.y));
	}
	crease += (1.0 - smoothstep(0.0, 0.035, abs(p.x - 0.46))) * smoothstep(-0.2, 0.0, p.y) * (1.0 - smoothstep(0.3, 0.4, p.y));
	float cuff = (1.0 - smoothstep(0.0, 0.04, abs(p.y + 0.35)));
	float heat = 0.4 + n * 0.3 + rim * 0.4 - crease * 0.35 - cuff * 0.2;
	float line = (1.0 - smoothstep(0.0, 0.05, second - nearest)) * crack;
	heat += line * 0.6;
	float cover = inside * alpha;
	vec4 outc = fx_premul(fx_blood_ramp(clamp(heat, 0.0, 0.95)) * brightness, cover, 0.15);
	ALBEDO = outc.rgb;
	ALPHA = outc.a;
}
