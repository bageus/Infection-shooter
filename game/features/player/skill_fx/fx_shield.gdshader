shader_type spatial;
// Armor flash: a hex-plated bubble around the player that lights up at the
// rim and fades as `progress` runs out.
render_mode blend_premul_alpha, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 color : source_color = vec4(0.3, 0.8, 1.0, 1.0);

instance uniform float progress = 0.0;
instance uniform float alpha = 1.0;

varying vec3 local;

void vertex() {
	local = VERTEX;
}

float hex_edge(vec2 p) {
	vec2 s = vec2(1.0, 1.7320508);
	vec2 a = mod(p, s) - s * 0.5;
	vec2 b = mod(p - s * 0.5, s) - s * 0.5;
	vec2 g = dot(a, a) < dot(b, b) ? a : b;
	vec2 h = abs(g);
	float d = max(dot(h, s * 0.5), h.x);
	return smoothstep(0.42, 0.5, d);
}

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float fresnel = pow(1.0 - facing, 2.2);
	float angle = atan(local.z, local.x);
	vec2 hex_uv = vec2(angle * 3.0, local.y * 9.0);
	float lines = hex_edge(hex_uv) * (1.0 - smoothstep(0.6, 0.95, abs(normalize(local).y)));
	float wave = exp(-pow((local.y - (1.05 - progress * 5.0)) * 3.0, 2.0));
	float life = 1.0 - smoothstep(0.3, 1.0, progress);
	float flash = 1.0 - smoothstep(0.0, 0.25, progress);
	float cover = (fresnel * 0.9 + lines * (0.25 + wave * 0.6) + flash * 0.2) * life * alpha;
	vec3 tone = color.rgb * (1.2 + wave + flash);
	ALBEDO = tone * clamp(cover, 0.0, 1.0);
	ALPHA = clamp(cover, 0.0, 1.0) * 0.25;
}
