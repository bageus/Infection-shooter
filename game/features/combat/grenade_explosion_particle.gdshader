shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D particle_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float opacity : hint_range(0.0, 1.0) = 0.5;
uniform float uv_drift : hint_range(0.0, 0.1) = 0.0;
uniform bool fire_particle = false;
uniform bool spark_particle = false;
uniform float growth : hint_range(1.0, 4.0) = 1.5;

varying float age;
varying float seed;

float noise(vec2 p) {
    vec2 cell = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    vec2 k = vec2(127.1, 311.7);
    float a = fract(sin(dot(cell, k)) * 43758.5453);
    float b = fract(sin(dot(cell + vec2(1.0, 0.0), k)) * 43758.5453);
    float c = fract(sin(dot(cell + vec2(0.0, 1.0), k)) * 43758.5453);
    float d = fract(sin(dot(cell + vec2(1.0), k)) * 43758.5453);
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
    age = clamp(INSTANCE_CUSTOM.y, 0.0, 1.0);
    seed = fract(float(INSTANCE_ID) * 0.6180339);
    float angle = seed * 6.28318 + age * (seed - 0.5) * 1.8;
    if (!spark_particle) {
        VERTEX.xy = mat2(vec2(cos(angle), sin(angle)), vec2(-sin(angle), cos(angle))) * VERTEX.xy;
    }
    VERTEX.xy *= mix(0.65, 1.4, seed) * mix(0.55, growth, sqrt(age));
    if (spark_particle) {
        VERTEX.x *= 0.35;
        VERTEX.y *= 2.4;
    }
}

void fragment() {
    vec2 flow = vec2(noise(UV * 6.0 + vec2(seed * 23.0, -age * 3.0)),
                     noise(UV * 6.0 + vec2(age * 2.0, seed * 17.0))) - 0.5;
    vec2 uv = clamp(UV + flow * uv_drift,
                    vec2(0.0), vec2(1.0));
    vec4 sample_color = texture(particle_texture, uv);
    float fade = smoothstep(0.0, 0.05, age) * (1.0 - smoothstep(0.3, 1.0, age));
    vec3 color = sample_color.rgb * tint.rgb;
    float alpha = sample_color.a;
    if (fire_particle) {
        color *= mix(vec3(1.35, 1.2, 0.95), vec3(0.65, 0.2, 0.05), age);
        EMISSION = color * (1.0 - age) * 2.8;
        alpha *= mix(0.75, 1.0, noise(uv * 10.0 + age * 5.0));
    } else if (spark_particle) {
        alpha = 1.0 - smoothstep(0.1, 0.5, length(UV - vec2(0.5)));
        color = tint.rgb;
        EMISSION = color * (1.0 - age) * 3.5;
    } else {
        color *= mix(0.6, 1.2, age);
    }
    ALBEDO = color;
    ALPHA = alpha * tint.a * opacity * fade;
}
