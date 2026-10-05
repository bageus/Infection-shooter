shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, shadows_disabled;
uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
uniform vec4 tint : source_color = vec4(0.2, 0.85, 1.0, 0.9);
void fragment() {
    float depth = textureLod(scene_depth, SCREEN_UV, 0.0).r;
    vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
    ndc.z = depth * 2.0 - 1.0;
#endif
    vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
    float nearest = -view.z / view.w;
    if (-VERTEX.z <= nearest + 0.04) discard;
    ALBEDO = tint.rgb;
    ALPHA = tint.a;
}
