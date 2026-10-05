shader_type spatial;
uniform vec4 base_color : source_color = vec4(1.0);
uniform sampler2D base_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_texture = false;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap, repeat_enable;
uniform bool use_normal = false;
uniform float normal_scale = 1.0;
uniform bool use_vertex_color = false;
uniform sampler2D roughness_texture : filter_linear_mipmap, repeat_enable;
uniform bool use_roughness = false;
uniform vec4 roughness_channel = vec4(1.0, 0.0, 0.0, 0.0);
uniform sampler2D metallic_texture : filter_linear_mipmap, repeat_enable;
uniform bool use_metallic = false;
uniform vec4 metallic_channel = vec4(1.0, 0.0, 0.0, 0.0);
uniform sampler2D ao_texture : filter_linear_mipmap, repeat_enable;
uniform bool use_ao = false;
uniform vec4 ao_channel = vec4(1.0, 0.0, 0.0, 0.0);
uniform float ao_light_affect = 0.0;
uniform vec3 emission_color : source_color = vec3(0.0);
uniform sampler2D emission_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_emission = false;
uniform float roughness_value = 0.7;
uniform float metallic_value = 0.0;
uniform float specular_value = 0.5;
uniform vec3 uv_scale = vec3(1.0);
uniform vec3 uv_offset = vec3(0.0);
uniform vec2 hole_center = vec2(-10.0);
uniform vec2 viewport_size = vec2(1280.0, 720.0);
uniform float hole_radius = 0.0;
uniform float player_depth = 0.0;
varying float main_view;
void vertex() {
    UV = UV * uv_scale.xy + uv_offset.xy;
    // Keep the authored wall silhouette in shadow cameras.
    main_view = distance(INV_VIEW_MATRIX[3].xyz, MAIN_CAM_INV_VIEW_MATRIX[3].xyz) < 0.01 ? 1.0 : 0.0;
}
void fragment() {
    float edge = 0.0;
    if (main_view > 0.5 && hole_radius > 0.0 && -VERTEX.z < player_depth - 0.05) {
        float distance_px = length((SCREEN_UV - hole_center) * viewport_size);
        float fade = smoothstep(hole_radius * 0.88, hole_radius, distance_px);
        float dither = fract(dot(floor(FRAGCOORD.xy), vec2(0.754877666, 0.569840296)));
        if (fade < dither + 0.0001) discard;
        edge = (1.0 - smoothstep(hole_radius, hole_radius * 1.08, distance_px)) * 0.12;
    }
    vec4 base = base_color;
    if (use_texture) base *= texture(base_texture, UV);
    if (use_vertex_color) base *= COLOR;
    ALBEDO = base.rgb;
    ROUGHNESS = roughness_value;
    if (use_roughness) ROUGHNESS *= dot(texture(roughness_texture, UV), roughness_channel);
    METALLIC = metallic_value;
    if (use_metallic) METALLIC *= dot(texture(metallic_texture, UV), metallic_channel);
    SPECULAR = specular_value;
    if (use_normal) {
        NORMAL_MAP = texture(normal_texture, UV).rgb;
        NORMAL_MAP_DEPTH = normal_scale;
    }
    if (use_ao) {
        AO = dot(texture(ao_texture, UV), ao_channel);
        AO_LIGHT_AFFECT = ao_light_affect;
    }
    EMISSION = emission_color + vec3(0.16, 0.45, 0.55) * edge;
    if (use_emission) EMISSION += texture(emission_texture, UV).rgb;
}
