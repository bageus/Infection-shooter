shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D spray_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform float opacity : hint_range(0.0, 1.0) = 0.65;
uniform float distortion : hint_range(0.0, 0.2) = 0.045;
uniform float speed : hint_range(0.0, 4.0) = 1.0;

varying float particle_age;
varying float particle_seed;

void vertex() {
    particle_age = INSTANCE_CUSTOM.y;
    particle_seed = float(INSTANCE_ID) * 0.61;
}

float hash21(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise2(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
               mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
    float age = clamp(particle_age, 0.0, 1.0);
    float t = TIME * speed + particle_seed;
    vec2 flow = vec2(noise2(UV * 5.0 + vec2(t * 0.42, -t * 0.27)),
                     noise2(UV * 6.0 + vec2(-t * 0.31, t * 0.39))) - vec2(0.5);
    vec2 uv = clamp(UV + flow * distortion, vec2(0.0), vec2(1.0));
    vec4 tex = texture(spray_texture, uv);
    float fade = smoothstep(0.0, 0.12, age) * (1.0 - smoothstep(0.55, 1.0, age));
    ALBEDO = vec3(0.91, 0.94, 0.96) * COLOR.rgb;
    ALPHA = tex.a * COLOR.a * opacity * fade;
}
