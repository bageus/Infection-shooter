shader_type spatial;
// Second Heart: an anatomical heart ray-marched in the fragment shader (two
// ventricles, both atria, aorta, pulmonary trunk and vena cava as smooth
// signed-distance blobs), lit like wet muscle with fat and coronary vessels
// on its surface. It beats lub-dub, squeezing as it contracts, and sways a
// little so it reads as a solid organ, not a sprite.
render_mode blend_premul_alpha, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

#include "res://game/features/player/skill_fx/fx_noise.gdshaderinc"

uniform vec4 color : source_color = vec4(0.5, 0.045, 0.055, 1.0);
uniform float beats_per_second = 1.2;

instance uniform float alpha = 1.0;
instance uniform float clock = 0.0;

const int STEPS = 48;
const float VIEW_SIZE = 1.7;

void vertex() {
	float s = length(MODEL_MATRIX[0].xyz);
	vec3 world = MODEL_MATRIX[3].xyz + (INV_VIEW_MATRIX[0].xyz * VERTEX.x + INV_VIEW_MATRIX[1].xyz * VERTEX.y) * s;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

float smooth_min(float a, float b, float k) {
	float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
	return mix(b, a, h) - k * h * (1.0 - h);
}

// Ellipsoid distance (approximate, good enough to march).
float ellipsoid(vec3 p, vec3 r) {
	float k0 = length(p / r);
	float k1 = length(p / (r * r));
	return k0 * (k0 - 1.0) / max(k1, 0.0001);
}

// Capped cylinder between a and b.
float tube(vec3 p, vec3 a, vec3 b, float r) {
	vec3 pa = p - a;
	vec3 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h) - r;
}

vec2 rotate2(vec2 v, float angle) {
	float c = cos(angle);
	float s = sin(angle);
	return vec2(c * v.x - s * v.y, s * v.x + c * v.y);
}

// Distance to the whole heart; `part` returns what is nearest (0 muscle, 1 aorta, 2 vein).
float heart_distance(vec3 p, float squeeze, out float part) {
	vec3 q = p;
	q.xy = rotate2(q.xy, -0.38);
	// Ventricles contract: narrower and a touch shorter.
	vec3 v = q;
	v.x /= 1.0 - 0.07 * squeeze;
	float left = ellipsoid(v - vec3(0.06, -0.06, 0.0), vec3(0.34, 0.5, 0.3));
	float right = ellipsoid(v - vec3(-0.2, 0.0, 0.14), vec3(0.27, 0.4, 0.25));
	float body = smooth_min(left, right, 0.12);
	float atria = smooth_min(
		ellipsoid(q - vec3(-0.27, 0.26, -0.02), vec3(0.17, 0.21, 0.17)),
		ellipsoid(q - vec3(0.2, 0.31, -0.06), vec3(0.15, 0.13, 0.13)), 0.08);
	float muscle = smooth_min(body, atria, 0.1);
	float aorta = smooth_min(
		tube(q, vec3(0.04, 0.3, 0.0), vec3(0.06, 0.66, 0.0), 0.085),
		tube(q, vec3(0.06, 0.66, 0.0), vec3(0.25, 0.6, -0.04), 0.075), 0.05);
	float pulmonary = tube(q, vec3(-0.09, 0.3, 0.1), vec3(-0.07, 0.6, 0.06), 0.07);
	float vena = tube(q, vec3(-0.3, 0.3, -0.04), vec3(-0.32, 0.68, -0.04), 0.065);
	float vessels = min(aorta, min(pulmonary, vena));
	part = aorta < vena && aorta < pulmonary && aorta < muscle ? 1.0 : (vena < muscle || pulmonary < muscle ? 2.0 : 0.0);
	return smooth_min(muscle, vessels, 0.06);
}

float scene(vec3 p, float squeeze) {
	float part;
	return heart_distance(p, squeeze, part);
}

vec3 surface_normal(vec3 p, float squeeze) {
	vec2 e = vec2(0.004, -0.004);
	return normalize(
		e.xyy * scene(p + e.xyy, squeeze) + e.yyx * scene(p + e.yyx, squeeze) +
		e.yxy * scene(p + e.yxy, squeeze) + e.xxx * scene(p + e.xxx, squeeze));
}

void fragment() {
	float t = fract(clock * beats_per_second);
	// Lub, then a smaller dub.
	float beat = exp(-pow(t * 11.0, 2.0)) + 0.65 * exp(-pow((t - 0.27) * 11.0, 2.0)) + exp(-pow((t - 1.0) * 11.0, 2.0));
	float squeeze = clamp(beat, 0.0, 1.0);
	vec2 uv = (vec2(UV.x, 1.0 - UV.y) - 0.5) * VIEW_SIZE;
	uv.y += 0.02;
	// Orthographic march along view -Z; the heart turns a little for depth.
	float yaw = 0.35 * sin(clock * 0.9);
	float pulse = 1.0 + 0.09 * beat;
	float travel = -1.2;
	float nearest = 10.0;
	bool hit = false;
	vec3 point = vec3(0.0);
	for (int i = 0; i < STEPS; i++) {
		vec3 ray = vec3(uv, 1.2 + travel);
		vec3 local = vec3(ray.x * cos(yaw) - ray.z * sin(yaw), ray.y, ray.x * sin(yaw) + ray.z * cos(yaw)) / pulse;
		float d = scene(local, squeeze) * pulse;
		nearest = min(nearest, d);
		if (d < 0.002) {
			hit = true;
			point = local;
			break;
		}
		travel += d;
		if (travel > 2.4) {
			break;
		}
	}
	// Outside the silhouette: only a soft red glow that swells with each beat.
	float glow = exp(-max(nearest, 0.0) * 7.0) * (0.12 + 0.3 * beat);
	if (!hit) {
		float edge = 1.0 - smoothstep(0.0, 0.012, nearest);
		ALBEDO = vec3(0.9, 0.08, 0.1) * glow * alpha;
		ALPHA = max(edge * 0.0, glow * 0.6) * alpha;
	} else {
		float part;
		heart_distance(point, squeeze, part);
		vec3 n = surface_normal(point, squeeze);
		// Fine bumps from the muscle fibres and tissue, so the skin is not glass-smooth.
		vec3 bump_at = point * vec3(26.0, 18.0, 26.0);
		vec3 bump = vec3(
			fx_noise3(bump_at + vec3(0.7, 0.0, 0.0)) - fx_noise3(bump_at - vec3(0.7, 0.0, 0.0)),
			fx_noise3(bump_at + vec3(0.0, 0.7, 0.0)) - fx_noise3(bump_at - vec3(0.0, 0.7, 0.0)),
			fx_noise3(bump_at + vec3(0.0, 0.0, 0.7)) - fx_noise3(bump_at - vec3(0.0, 0.0, 0.7)));
		n = normalize(n + bump * 0.22);
		// Turn the normal back into view space for the lighting.
		vec3 view_n = vec3(n.x * cos(yaw) + n.z * sin(yaw), n.y, -n.x * sin(yaw) + n.z * cos(yaw));
		vec3 light = normalize(vec3(-0.5, 0.7, 0.8));
		float wrap = clamp((dot(view_n, light) + 0.45) / 1.45, 0.0, 1.0);
		// Fat and coronary vessels: ridged lines over the muscle, paler near the top.
		float ridge = 1.0 - abs(fx_noise3(point * vec3(7.0, 5.0, 7.0)) * 2.0 - 1.0);
		float ridge_fine = 1.0 - abs(fx_noise3(point * vec3(15.0, 12.0, 15.0) + 3.0) * 2.0 - 1.0);
		float vessel = max(smoothstep(0.8, 0.93, ridge), smoothstep(0.88, 0.97, ridge_fine) * 0.7) * smoothstep(-0.35, 0.2, point.y + point.x * 0.4);
		float fat = smoothstep(0.0, 0.3, point.y) * smoothstep(0.25, 0.65, fx_fbm(point.xy * 6.0 + point.z * 3.0) + 0.2);
		vec3 muscle = color.rgb * (0.7 + 0.5 * fx_noise3(point * vec3(14.0, 4.0, 14.0)));
		vec3 base = muscle;
		if (part == 1.0) {
			base = vec3(0.62, 0.24, 0.2);
		} else if (part == 2.0) {
			base = vec3(0.36, 0.12, 0.2);
		}
		base = mix(base, vec3(0.86, 0.62, 0.36), fat * 0.75 * step(part, 0.5));
		base = mix(base, vec3(0.82, 0.38, 0.28), vessel * 0.85);
		float rim = pow(1.0 - clamp(view_n.z, 0.0, 1.0), 2.5);
		vec3 half_vec = normalize(light + vec3(0.0, 0.0, 1.0));
		float spec = pow(clamp(dot(view_n, half_vec), 0.0, 1.0), 24.0) * 0.4 * (1.0 - fat);
		float broad = pow(clamp(dot(view_n, half_vec), 0.0, 1.0), 8.0) * 0.18;
		vec3 tone = base * (0.18 + 0.95 * wrap) * (1.0 + 0.35 * beat);
		// Light scattering through thin muscle at the edges: a deep red glow.
		tone += vec3(0.5, 0.035, 0.045) * rim * 0.6;
		tone += vec3(1.0, 0.9, 0.85) * (spec + broad);
		ALBEDO = tone * alpha;
		ALPHA = alpha;
	}
}
