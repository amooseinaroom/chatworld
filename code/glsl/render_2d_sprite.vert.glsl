#version 330

layout (std140, column_major) uniform context_buffer
{
    vec2 viewport_size;
    vec2 draw_offset;
    vec2 draw_scale;
};

struct render_2d_gl_sprite
{
    vec4 color;

    vec2  pivot;
    vec2  size;
    vec2  alignment;
    float depth;
    float _unused;
    
    vec2 texture_box_min;
    vec2 texture_box_max;    
};

layout (std140, column_major) uniform sprite_buffer
{
    render_2d_gl_sprite sprites[1];
};

out fragment_type
{
    vec2  uv;
    vec4  color;
    float saturation;
} fragment;

void main()
{
    vec2 vertices[6] = vec2[6](
        vec2(0, 0),
        vec2(1, 0),
        vec2(1, 1),
        
        vec2(0, 0),
        vec2(1, 1),
        vec2(0, 1)
    );

    render_2d_gl_sprite sprite = sprites[gl_InstanceID];
    
    vec2 box_min = sprite.pivot - sprite.size * sprite.alignment;
    vec2 box_max = box_min + sprite.size;

    vec2 blend = vertices[gl_VertexID];
    vec2 position = mix(box_min, box_max, blend);

    // to viewport position
    // TODO: maybe try make it pixel perfect?    
    position = (position * draw_scale + draw_offset);

    // float depth = position.y / viewport_size.y;

    vec2 clip_position = (position / viewport_size) * 2 - 1;

    fragment.color = sprite.color;

    gl_Position = vec4(clip_position, sprite.depth, 1);
}