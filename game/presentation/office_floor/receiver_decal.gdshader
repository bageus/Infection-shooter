shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform sampler2D damage : source_color, filter_linear, repeat_disable;
uniform sampler2D scuffs : source_color, filter_linear, repeat_disable;
uniform vec3 bounds_origin;
uniform vec3 bounds_size;
uniform bool glass = false;
varying vec3 local_point;
varying vec3 local_normal;
void vertex() {
	local_point = VERTEX;
	local_normal = NORMAL;
	VERTEX += NORMAL * 0.0008;
}
void fragment() {
	vec3 n = normalize(local_normal);
	vec3 p = clamp((local_point - bounds_origin) / max(bounds_size, vec3(0.0001)), vec3(0.0), vec3(1.0));
	vec2 uv;
	float face;
	if (abs(n.x) > abs(n.y) && abs(n.x) > abs(n.z)) { uv = p.zy; face = n.x >= 0.0 ? 0.0 : 1.0; }
	else if (abs(n.y) > abs(n.z)) { uv = p.xz; face = n.y >= 0.0 ? 2.0 : 3.0; }
	else { uv = p.xy; face = n.z >= 0.0 ? 4.0 : 5.0; }
	uv.y = 1.0 - uv.y;
	if (glass) { face = floor(face * 0.5) * 2.0; }
	uv = (vec2(mod(face, 3.0), floor(face / 3.0)) + (uv * 127.0 + 0.5) / 128.0) / vec2(3.0, 2.0);
	vec4 a = texture(damage, uv);
	vec4 b = texture(scuffs, uv);
	if (glass) { a.rgb = vec3(dot(a.rgb, vec3(0.299, 0.587, 0.114))); }
	float coverage = b.a + a.a * (1.0 - b.a);
	ALBEDO = (b.rgb * b.a + a.rgb * a.a * (1.0 - b.a)) / max(coverage, 0.00001);
	ALPHA = coverage;
	ROUGHNESS = glass ? 0.16 : 0.94;
	SPECULAR = glass ? 0.65 : 0.2;
}
