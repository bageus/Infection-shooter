shader_type canvas_item;
render_mode unshaded;
uniform sampler2D scene_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float strength : hint_range(0.0, 1.0) = 0.0;
uniform float phase = 0.0;
float hash(float value) {
    return fract(sin(value * 127.1) * 43758.5453);
}
void fragment() {
    vec2 pixel = SCREEN_PIXEL_SIZE;
    float pulse = 0.5 + 0.5 * sin(phase * 5.5);
    float spread = 14.0 * strength * pulse;
    float band = floor(SCREEN_UV.y / (pixel.y * 7.0));
    float moment = floor(phase * 13.0);
    float glitch = step(0.965, hash(band + moment * 31.0)) * strength;
    vec2 uv = clamp(SCREEN_UV + vec2((hash(moment + band) - 0.5) * 12.0 * pixel.x * glitch, 0.0), pixel, vec2(1.0) - pixel);
    float blur = strength * 1.8;
    vec3 base = textureLod(scene_texture, uv, blur).rgb;
    vec2 shift = pixel * spread;
    vec3 ghosts = textureLod(scene_texture, clamp(uv + shift * vec2(1.0, 0.2), pixel, vec2(1.0) - pixel), blur).rgb;
    ghosts += textureLod(scene_texture, clamp(uv + shift * vec2(-0.2, 1.0), pixel, vec2(1.0) - pixel), blur).rgb;
    ghosts += textureLod(scene_texture, clamp(uv + shift * vec2(-1.0, -0.3), pixel, vec2(1.0) - pixel), blur).rgb;
    ghosts += textureLod(scene_texture, clamp(uv + shift * vec2(0.3, -1.0), pixel, vec2(1.0) - pixel), blur).rgb;
    vec3 result = mix(base, ghosts * 0.25, strength * 0.6);
    float fringe = (0.8 + 2.0 * pulse) * strength;
    result.r = mix(result.r, textureLod(scene_texture, clamp(uv + vec2(pixel.x * fringe, 0.0), pixel, vec2(1.0) - pixel), blur).r, 0.25 * strength);
    result.b = mix(result.b, textureLod(scene_texture, clamp(uv - vec2(pixel.x * fringe, 0.0), pixel, vec2(1.0) - pixel), blur).b, 0.25 * strength);
    result *= 1.0 - glitch * 0.08;
    COLOR = vec4(result, 1.0);
}
