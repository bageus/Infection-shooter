shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, skip_vertex_transform;

// Adapted from the supplied Sprite2D shader for a camera-facing 3D cloud.
instance uniform float progress : hint_range(0.0, 1.0) = 0.0;
instance uniform float phase = 0.0;

uniform sampler2D cloud_texture : source_color, filter_linear_mipmap;
uniform float opacity : hint_range(0.0, 1.0) = 0.78;
uniform float swirl_strength : hint_range(0.0, 0.08) = 0.022;
uniform float swirl_speed : hint_range(0.0, 3.0) = 1.0;
uniform vec4 tint : source_color = vec4(1.0);

float hash21(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    float a = hash21(i);
    float b = hash21(i + vec2(1.0, 0.0));
    float c = hash21(i + vec2(0.0, 1.0));
    float d = hash21(i + vec2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void vertex() {
    float life = clamp(progress, 0.0, 1.0);
    vec2 size = vec2(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz));
    // Keep the plane facing the rendering camera without updating every cloud on the CPU.
    VERTEX = vec3(VERTEX.xy * size * (1.0 + life * 0.22), 0.0);
    VERTEX.y += life * 0.28;
    VERTEX += (VIEW_MATRIX * MODEL_MATRIX[3]).xyz;
    NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
    float life = clamp(progress, 0.0, 1.0);
    float activity = pow(1.0 - life, 1.25);
    float t = (TIME + phase) * swirl_speed;

    float n1 = value_noise(UV * 5.0 + vec2(t * 0.19, -t * 0.12));
    float n2 = value_noise(UV * 8.0 + vec2(-t * 0.14, t * 0.17));
    vec2 displacement = (vec2(n1, n2) - vec2(0.5)) * swirl_strength * activity;
    vec4 gas = texture(cloud_texture, clamp(UV + displacement, vec2(0.0), vec2(1.0)));

    float pulse = 1.0 + 0.10 * activity * sin(t * 3.3 + n1 * 6.0);
    float brightness = mix(0.40, 1.30, activity) * pulse;
    float fade = 1.0 - smoothstep(0.15, 1.0, life);
    float breathing = 0.87 + 0.13 * n2;

    ALBEDO = gas.rgb * tint.rgb * brightness;
    EMISSION = ALBEDO * 0.35;
    ALPHA = gas.a * tint.a * opacity * fade * breathing;
}
