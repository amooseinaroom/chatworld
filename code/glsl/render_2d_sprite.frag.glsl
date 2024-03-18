
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
    vec2  uv;
} fragment;

out vec4 out_color;

uniform sampler2D sprite_texture;

void main()
{
    vec4 sample = texture(sprite_texture, fragment.uv);
    vec4 color = sample * fragment.color;

    // if (color.a < min_alpha)
    // discard;

    // color.rgb = mix(vec3((color.r + color.g + color.b) / 3), color.rgb, fragment.saturation);

    out_color = color;
}