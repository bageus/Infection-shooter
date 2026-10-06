shader_type spatial;
// Overlay on the player model for passive mutations. It reads the model's own
// albedo to find the parts it changes:
// - metal (Hardened Tissue): the navy-blue clothing turns grey brushed metal;
// - bone (Bone Armor): segmented ivory bone plates grow over the body.
render_mode blend_mix, depth_draw_never, cull_back;

uniform sampler2D base_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform float metal : hint_range(0.0, 1.0) = 0.0;
uniform float bone : hint_range(0.0, 1.0) = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec3 base = texture(base_albedo, UV).rgb;
	float luma = dot(base, vec3(0.3, 0.55, 0.15));
	// Navy cloth: blue clearly above red and green, but not the pale lenses.
	float navy = smoothstep(0.03, 0.08, base.b - max(base.r, base.g)) * (1.0 - smoothstep(0.32, 0.42, base.b));
	// Mask lenses (bright, cold blue-cyan) stay uncovered.
	float lens = smoothstep(0.38, 0.5, base.b) * smoothstep(0.08, 0.16, base.b - base.r) * smoothstep(0.28, 0.36, base.g);

	vec3 color = vec3(0.0);
	float alpha = 0.0;
	float metallic = 0.0;
	float roughness = 0.8;

	if (metal > 0.0) {
		float brushed = noise(UV * vec2(900.0, 40.0)) * 0.12;
		vec3 steel = vec3(0.46, 0.48, 0.5) * (0.65 + luma * 3.2) + brushed;
		float m = navy * metal;
		color = mix(color, steel, m);
		alpha = max(alpha, m);
		metallic = mix(metallic, 0.85, m);
		roughness = mix(roughness, 0.32, m);
	}
	if (bone > 0.0) {
		// Bone plates in patches; each plate is a stack of rounded ribs with
		// dark seams between them, so the patch reads as segmented bone.
		vec2 p = UV * 80.0;
		float warp = noise(p * 0.25) * 1.6;
		float band = abs(fract(p.y * 0.5 + warp) - 0.5) * 2.0;
		float seam = smoothstep(0.7, 0.92, band);
		float cluster = smoothstep(0.42, 0.5, noise(UV * 7.0 + 3.7));
		float b = cluster * bone * (1.0 - lens);
		float shade = (0.78 + 0.22 * noise(p * 1.7)) * mix(1.0, 0.7, band);
		vec3 ivory = mix(vec3(0.93, 0.9, 0.81) * shade, vec3(0.2, 0.17, 0.14), seam);
		color = mix(color, ivory, b);
		alpha = max(alpha, b);
		metallic = mix(metallic, 0.0, b);
		roughness = mix(roughness, 0.55, b);
	}
	ALBEDO = color;
	ALPHA = clamp(alpha, 0.0, 1.0);
	METALLIC = metallic;
	ROUGHNESS = roughness;
}
