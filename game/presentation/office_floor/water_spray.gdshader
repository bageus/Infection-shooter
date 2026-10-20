shader_type spatial;
// Water droplet: a soft capsule stretched along its own velocity (motion
// streak), with a bright glint and a clear blue body. One quad per drop; the
// instance custom data carries the world velocity (xyz) and the drop size (w).
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec3 water : source_color = vec3(0.55, 0.82, 1.0);
uniform float stretch = 0.045;

varying float speed;

void vertex() {
	vec3 center = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 view_velocity = (VIEW_MATRIX * vec4(INSTANCE_CUSTOM.xyz, 0.0)).xyz;
	speed = length(view_velocity);
	vec2 along = normalize(view_velocity.xy + vec2(0.0001, 0.0));
	vec2 across = vec2(-along.y, along.x);
	float size = INSTANCE_CUSTOM.w;
	float length_ = size * (1.0 + speed * stretch * 6.0);
	vec3 point = center + vec3(along * VERTEX.y * length_ + across * VERTEX.x * size, 0.0);
	POSITION = PROJECTION_MATRIX * vec4(point, 1.0);
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	// Capsule: round at both ends, long along y.
	float body = 1.0 - smoothstep(0.55, 1.0, length(vec2(p.x, p.y * 0.55)));
	float glint = smoothstep(0.35, 0.0, length(p - vec2(-0.25, 0.3)));
	float fresnel = smoothstep(0.2, 0.9, abs(p.x));
	vec3 tone = mix(water, vec3(1.0), glint * 0.85 + fresnel * 0.25);
	ALBEDO = tone;
	ALPHA = body * (0.5 + 0.4 * glint + 0.2 * fresnel);
}
