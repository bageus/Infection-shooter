shader_type spatial;
// Constant-width screen-space rim around an item hidden behind a wall; the mask pass keeps its interior clear.
render_mode unshaded, depth_test_disabled, depth_draw_never, shadows_disabled, cull_disabled;
stencil_mode read, compare_not_equal, 1;
uniform vec4 tint : source_color = vec4(1.0, 0.82, 0.1, 1.0);
uniform vec3 centre = vec3(0.0);
uniform float width_px = 3.0;
void vertex() {
    mat4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX;
    POSITION = clip * vec4(VERTEX, 1.0);
    vec4 middle = clip * vec4(centre, 1.0);
    // Away from the item's centre on screen, so every edge of the footprint grows regardless of view angle.
    vec2 push = (POSITION.xy / POSITION.w - middle.xy / middle.w) * VIEWPORT_SIZE;
    if (length(push) > 0.0001) POSITION.xy += normalize(push) * width_px * 2.0 / VIEWPORT_SIZE * POSITION.w;
}
void fragment() {
    ALBEDO = tint.rgb;
    ALPHA = tint.a;
}
