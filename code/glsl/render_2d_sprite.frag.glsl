
#version 330

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

    if (color.a == 0)
        discard;

    // color.rgb = mix(vec3((color.r + color.g + color.b) / 3), color.rgb, fragment.saturation);

    out_color = color;
}