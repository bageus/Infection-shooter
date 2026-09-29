shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D fire_atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform vec2 grid = vec2(4.0);
uniform float frame : hint_range(0.0, 16.0) = 0.0;
uniform float brightness : hint_range(0.0, 4.0) = 1.8;

void vertex() {
    // Face the game camera while preserving the expanding quad's world scale.
    vec3 s = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
    MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * s.x,
        INV_VIEW_MATRIX[1] * s.y, INV_VIEW_MATRIX[2] * s.z, MODEL_MATRIX[3]);
}

vec4 sample_frame(float index, vec2 uv) {
    vec2 cell = vec2(mod(index, grid.x), floor(index / grid.x));
    vec2 inset = grid / vec2(textureSize(fire_atlas, 0)) * 0.5;
    return texture(fire_atlas, (cell + mix(inset, vec2(1.0) - inset, uv)) / grid);
}

void fragment() {
    float current = clamp(frame, 0.0, 15.0);
    float index = floor(current);
    // Interpolate adjacent frames so a 180 ms burst remains smooth at 30/60 Hz.
    vec4 fire = mix(sample_frame(index, UV), sample_frame(min(index + 1.0, 15.0), UV), fract(current));
    float age = clamp(frame / 16.0, 0.0, 1.0);
    vec3 color = fire.rgb * mix(vec3(1.15, 1.08, 0.9), vec3(0.85, 0.5, 0.25), age);
    ALBEDO = color;
    EMISSION = color * brightness * (1.0 - age * 0.7);
    ALPHA = fire.a * (1.0 - smoothstep(0.72, 1.0, age));
}
