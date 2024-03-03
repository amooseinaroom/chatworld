#version 330

layout (std140, column_major) uniform context_buffer
{
    vec2 viewport_size;
    vec2 draw_offset;
    vec2 draw_scale;
};

struct render_2d_gl_circle
{
    vec4  color;   
    vec2  center;  
    float radius;  
    float depth; 
};

layout (std140, column_major) uniform circle_buffer
{
    render_2d_gl_circle circles[1];
};

out fragment_type
{
    vec4  color;    
    vec2  position;
    vec2  center;
    float radius;    
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

    render_2d_gl_circle circle = circles[gl_InstanceID];
    
    vec2 half_size = vec2(circle.radius, circle.radius);
    vec2 box_min = circle.center - half_size;
    vec2 box_max = circle.center + half_size;

    vec2 blend = vertices[gl_VertexID];
    vec2 position = mix(box_min, box_max, blend);
    fragment.position = position;

    // TODO: maybe try make it pixel perfect?    
    position = (position * draw_scale + draw_offset);

    vec2 clip_position = (position / viewport_size) * 2 - 1;

    fragment.center = circle.center;
    fragment.radius = circle.radius;
    fragment.color = circle.color;

    gl_Position = vec4(clip_position, circle.depth, 1);
}