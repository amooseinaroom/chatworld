
#version 330

layout (std140, column_major) uniform context_buffer
{
    vec2  viewport_size;
    vec2  draw_offset;
    float draw_scale;
    float _unsued;
};

in fragment_type
{
    vec4  color;
    vec2  position;
    vec2  center;
    vec2  viewport_position;
    vec2  viewport_center;
    float radius;
    float viewport_radius;
} fragment;
out vec4 out_color;

void main()
{
    //vec4 sample = texture(diffuse_texture, fragment.uv);
    //vec4 color = sample * fragment.color;

    // color.rgb = mix(vec3((color.r + color.g + color.b) / 3), color.rgb, fragment.saturation);

    // get rid off this discard, since we have no depth test anymore
    float distance = fragment.radius - length(fragment.position - fragment.center);
    if (distance < 0)
        discard;

    float viewport_distance = fragment.viewport_radius - length(fragment.viewport_position - fragment.viewport_center);
    float alpha = min(viewport_distance, 1);

    // if (alpha < min_alpha)
        // discard;

    //out_color = vec4(fragment.color.rgb, fragment.color.a * alpha); //  vec4(1, 0, 0, 1);

    out_color = fragment.color * alpha;
}