shader_type canvas_item;
render_mode unshaded;
uniform sampler2D scene_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
void fragment() {
    // Blur arrives first, then the picture sinks into black.
    float blur = smoothstep(0.0, 0.6, progress) * 4.0;
    vec3 color = textureLod(scene_texture, SCREEN_UV, blur).rgb;
    COLOR = vec4(color * (1.0 - smoothstep(0.35, 1.0, progress)), 1.0);
}
