shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;
// Quest target marker, one shader for three quads (mode 0 ground reticle, 1 arrow, 2 beam):
// 0 = flat reticle on the floor: steady ring, two expanding pulse rings, four rotating chevrons;
// 1 = camera-facing stack of down chevrons that light up in a chase, bobbing in the script;
// 2 = soft vertical light beam with bands rising along it.

uniform int mode = 0;
uniform vec4 tint : source_color = vec4(1.0, 0.35, 0.12, 1.0);
uniform vec4 hot : source_color = vec4(1.0, 0.92, 0.75, 1.0);
uniform float speed = 1.0;

varying vec2 uv;


void vertex() {
	uv = UV;
	if (mode == 1) {
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	} else if (mode == 2) {
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], MODEL_MATRIX[1],
				vec4(normalize(cross(INV_VIEW_MATRIX[0].xyz, MODEL_MATRIX[1].xyz)), 0.0), MODEL_MATRIX[3]);
	}
}


float ring(float r, float radius, float width) {
	return 1.0 - smoothstep(width * 0.5, width, abs(r - radius));
}


// Chevron line u = c + k*|v| with a hard cut at |v| > reach; returns 0..1 coverage.
float chevron(float u, float v, float c, float k, float width, float reach) {
	float d = abs(u - c - k * abs(v)) / sqrt(1.0 + k * k);
	return (1.0 - smoothstep(width * 0.6, width, d)) * (1.0 - smoothstep(reach - 0.05, reach, abs(v)));
}


vec4 reticle(vec2 p) {
	float r = length(p);
	float t = TIME * speed;
	float alpha = ring(r, 0.62, 0.05) * 0.8;
	for (int i = 0; i < 2; i++) {
		float phase = fract(t * 0.6 + float(i) * 0.5);
		alpha += ring(r, mix(0.3, 0.98, phase), 0.05 + 0.05 * phase) * pow(1.0 - phase, 1.5) * 0.9;
	}
	float angle = atan(p.y, p.x) - t * 0.9;
	float sector = mod(angle + PI * 0.25, PI * 0.5) - PI * 0.25; // four chevrons pointing at the centre
	alpha += chevron(r * cos(sector), r * sin(sector), 0.74, 0.9, 0.07, 0.26);
	alpha += (1.0 - smoothstep(0.0, 0.62, r)) * 0.16; // faint fill inside the ring
	alpha *= 1.0 - smoothstep(0.9, 1.0, r);
	return vec4(mix(tint.rgb, hot.rgb, clamp(alpha - 0.8, 0.0, 1.0)), clamp(alpha, 0.0, 1.0));
}


vec4 arrow(vec2 p) {
	float t = TIME * speed * 3.2;
	float alpha = 0.0;
	float core = 0.0;
	for (int i = 0; i < 3; i++) {
		float c = 0.38 - 0.46 * float(i);
		float lit = 0.3 + 0.7 * pow(0.5 + 0.5 * sin(t - float(i) * 1.5), 2.0); // chase from the top down
		alpha = max(alpha, chevron(p.y, p.x, c, 0.7, 0.2, 0.62) * lit);
		core = max(core, chevron(p.y, p.x, c, 0.7, 0.08, 0.55) * lit);
	}
	return vec4(mix(tint.rgb, hot.rgb, core), alpha);
}


vec4 beam(vec2 p) {
	float fall = pow(1.0 - abs(p.x), 2.5); // brightest on the axis
	float rise = smoothstep(0.0, 0.25, uv.y) * 0.4 + pow(uv.y, 1.5); // uv.y = 1 at the foot
	float bands = 0.65 + 0.35 * sin(uv.y * 24.0 + TIME * speed * 3.0);
	return vec4(mix(tint.rgb, hot.rgb, fall * 0.4), fall * rise * bands * 0.34 * smoothstep(0.0, 0.12, 1.0 - uv.y));
}


void fragment() {
	vec2 p = (uv - 0.5) * 2.0;
	p.y = -p.y; // up is +y
	vec4 color;
	if (mode == 0) {
		color = reticle(p);
	} else if (mode == 1) {
		color = arrow(p);
	} else {
		color = beam(p);
	}
	ALBEDO = color.rgb * 1.2;
	ALPHA = clamp(color.a, 0.0, 1.0);
}
