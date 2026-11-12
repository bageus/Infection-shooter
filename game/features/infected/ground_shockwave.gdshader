shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
// Slam shockwave: a flat unit ring whose vertices are pushed up by a travelling
// crest, so the floor looks lifted as the wave passes (ADR-0016). Unshaded and
// ~4k triangles per wave to stay cheap on integrated GPUs.

uniform vec4 tint : source_color = vec4(0.6, 0.46, 0.34, 0.8);
uniform float front = 0.0;  // crest position, 0..1 of the max radius
uniform float band = 0.2;   // crest width in the same units
uniform float lift = 0.6;   // crest height in metres
uniform float fade = 1.0;

varying float rise;
varying float reach;

void vertex() {
	float r = length(VERTEX.xz);
	float d = (r - front) / band;
	// Sharp leading edge, long trailing slope that settles back to the floor.
	float profile = d > 0.0 ? exp(-d * d * 6.0) : exp(d * 1.4);
	float angle = atan(VERTEX.z, VERTEX.x);
	// Broken, uneven slabs instead of a smooth ripple.
	float slabs = 0.65 + 0.35 * sin(angle * 13.0 + r * 40.0) * sin(angle * 7.0 - r * 23.0);
	rise = profile * slabs;
	reach = exp(-abs(d) * 0.6);
	VERTEX.y += rise * lift * (1.0 - 0.5 * front);
}

void fragment() {
	vec3 dust = tint.rgb;
	ALBEDO = mix(dust * 0.4, dust * 1.25, rise) + vec3(1.0, 0.75, 0.45) * pow(rise, 4.0) * 0.5;
	ALPHA = clamp(reach, 0.0, 1.0) * fade * tint.a;
}
