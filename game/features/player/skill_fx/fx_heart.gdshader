shader_type spatial;
// Second Heart: a camera-facing heart that beats (lub-dub) with a pulse
// ring on each beat.
render_mode blend_premul_alpha, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 color : source_color = vec4(0.95, 0.1, 0.15, 1.0);
uniform float beats_per_second = 1.3;

instance uniform float alpha = 1.0;
instance uniform float clock = 0.0;

float dot2(vec2 v) {
	return dot(v, v);
}

// Inigo Quilez's heart distance, point y up, heart from y 0 to ~1.
float heart(vec2 p) {
	p.x = abs(p.x);
	if (p.y + p.x > 1.0) {
		return sqrt(dot2(p - vec2(0.25, 0.75))) - sqrt(2.0) / 4.0;
	}
	return sqrt(min(dot2(p - vec2(0.0, 1.0)), dot2(p - 0.5 * max(p.x + p.y, 0.0)))) * sign(p.x - p.y);
}

void vertex() {
	float s = length(MODEL_MATRIX[0].xyz);
	vec3 world = MODEL_MATRIX[3].xyz + (INV_VIEW_MATRIX[0].xyz * VERTEX.x + INV_VIEW_MATRIX[1].xyz * VERTEX.y) * s;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

void fragment() {
	float t = fract(clock * beats_per_second);
	float beat = exp(-pow(t * 14.0, 2.0)) + 0.7 * exp(-pow((t - 0.24) * 14.0, 2.0)) + exp(-pow((t - 1.0) * 14.0, 2.0));
	vec2 p = (vec2(UV.x, 1.0 - UV.y) - vec2(0.5, 0.2)) * 1.8 / (1.0 + 0.16 * beat);
	float d = heart(p);
	float body = 1.0 - smoothstep(-0.01, 0.01, d);
	float shade = clamp(0.55 + 0.6 * (p.y - 0.2) - 0.5 * abs(p.x), 0.3, 1.0);
	float shine = exp(-dot2((p - vec2(-0.2, 0.68)) * vec2(5.0, 7.0)));
	float halo = exp(-max(d, 0.0) * 9.0) * (0.35 + 0.5 * beat) * (1.0 - body);
	float ring_d = length(p - vec2(0.0, 0.5)) - (0.45 + t * 0.6);
	float ring = exp(-ring_d * ring_d * 400.0) * (1.0 - t) * 0.8;
	vec3 tone = color.rgb * shade * (1.0 + 0.4 * beat) + vec3(1.0, 0.8, 0.8) * shine * 0.8;
	vec3 glow_tone = color.rgb * 1.6;
	float cover = body;
	vec3 premul = tone * body + glow_tone * (halo + ring);
	ALBEDO = premul * alpha;
	ALPHA = cover * alpha;
}
