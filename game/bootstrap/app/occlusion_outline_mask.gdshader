shader_type spatial;
// Writes the item's own footprint into the stencil buffer (no colour), so the outline pass leaves its interior untouched.
render_mode unshaded, depth_test_disabled, depth_draw_never, shadows_disabled, cull_disabled;
stencil_mode write, 1;
void fragment() {
    ALBEDO = vec3(0.0);
    ALPHA = 0.0;
}
