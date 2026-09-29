shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D atlas : source_color, filter_linear, repeat_disable;
uniform int frame_index = 0;
uniform float opacity : hint_range(0.0, 1.0) = 0.85;

void fragment() {
    int column = frame_index % 3;
    int row = frame_index / 3;
    vec2 cell_uv = clamp(UV, vec2(0.001), vec2(0.999));
    vec2 uv = (cell_uv + vec2(float(column), float(row))) / vec2(3.0, 2.0);
    vec4 sample_color = texture(atlas, uv);
    ALBEDO = sample_color.rgb;
    EMISSION = sample_color.rgb * (0.42 * (1.0 - float(frame_index) / 6.0));
    ALPHA = sample_color.a * opacity;
}
