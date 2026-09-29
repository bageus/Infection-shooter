shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D particle_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float opacity : hint_range(0.0, 1.0) = 0.5;
uniform float uv_drift : hint_range(0.0, 0.1) = 0.0;

varying float age;

void vertex() {
    age = clamp(INSTANCE_CUSTOM.y, 0.0, 1.0);
    float size_variation = mix(0.7, 1.25, fract(float(INSTANCE_ID) * 0.618));
    VERTEX.xy *= size_variation;
}

void fragment() {
    vec2 uv = clamp(UV + vec2(sin(TIME * 1.2 + UV.y * 8.0), cos(TIME + UV.x * 7.0)) * uv_drift,
                    vec2(0.0), vec2(1.0));
    vec4 sample_color = texture(particle_texture, uv);
    float fade = smoothstep(0.0, 0.12, age) * (1.0 - smoothstep(0.34, 1.0, age));
    ALBEDO = sample_color.rgb * tint.rgb;
    ALPHA = sample_color.a * tint.a * opacity * fade;
}
