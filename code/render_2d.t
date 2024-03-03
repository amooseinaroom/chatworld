
module render_2d;

import gl;
import math;
import memory;
import platform;

struct render_2d_api
{      
    context render_2d_context;

    textures render_2d_texture_buffer;
    sprites  render_2d_gl_sprite_buffer;
    circles  render_2d_gl_circle_buffer;

    shader_sprite render_2d_shader_sprite;
    shader_circle render_2d_shader_circle;

    gl_empty_vertex_array u32;

    context_buffer gl_uniform_buffer;
    sprite_buffer  gl_uniform_buffer;
    circle_buffer  gl_uniform_buffer;
}

struct render_2d_context
{
    viewport_size vec2;    
    draw_offset   vec2;
    draw_scale    vec2;
}

struct render_2d_texture
{
    expand baxe gl_texture;
}

struct render_2d_texture_buffer
{
    expand base               render_2d_texture[];
           require_used_count usize;           
}

struct render_2d_position
{
    pivot     vec2;
    alignment vec2;
    depth     f32;
}

struct render_2d_gl_sprite
{
    color           vec4;
    pivot           vec2;
    size            vec2;
    alignment       vec2;
    depth           f32;
    _unused         f32;
    texture_box_min vec2;
    texture_box_max vec2;    
}

struct render_2d_gl_sprite_buffer
{
    expand base               render_2d_gl_sprite[];
           require_used_count usize;           
}

struct render_2d_gl_circle
{
    color  vec4;
    center vec2;
    radius f32;
    depth  f32;
}

struct render_2d_gl_circle_buffer
{
    expand base               render_2d_gl_circle[];
           require_used_count usize;           
}

enum render_2d_gl_buffer
{
    context_buffer;
    sprite_buffer; 
    circle_buffer;
}

enum render_2d_gl_vertex_attribute
{
}

struct render_2d_shader_sprite
{
    handle u32;

    sprite_texture s32;    
}

struct render_2d_shader_circle
{
    handle u32;    
}

def render_2d_gl_shader_sprite_vert = import_text_file("glsl/render_2d_sprite.vert.glsl");
def render_2d_gl_shader_sprite_frag = import_text_file("glsl/render_2d_sprite.frag.glsl");
def render_2d_gl_shader_circle_vert = import_text_file("glsl/render_2d_circle.vert.glsl");
def render_2d_gl_shader_circle_frag = import_text_file("glsl/render_2d_circle.frag.glsl");

func init(render render_2d_api ref, gl gl_api ref, tmemory memory_arena ref)
{
    glGenVertexArrays(1, render.gl_empty_vertex_array ref);

    var result = reload_shader(gl, render.shader_sprite, "render 2d sprite", get_type_info(render_2d_gl_vertex_attribute), get_type_info(render_2d_gl_buffer), render_2d_gl_shader_sprite_vert, false, render_2d_gl_shader_sprite_frag, tmemory);
    assert(result.ok);

    result = reload_shader(gl, render.shader_circle, "render 2d circle", get_type_info(render_2d_gl_vertex_attribute), get_type_info(render_2d_gl_buffer), render_2d_gl_shader_circle_vert, false, render_2d_gl_shader_circle_frag, tmemory);
    assert(result.ok);
}

func frame(render render_2d_api ref, context render_2d_context, tmemory memory_arena ref)
{
    render.context = context;

    {
        render.sprites.base = {} render_2d_gl_sprite[];
        reallocate_array(tmemory, render.sprites.base ref, maximum(render.sprites.count, render.sprites.require_used_count * 2));
        render.sprites.require_used_count = 0;
    }

    {
        render.circles.base = {} render_2d_gl_circle[];
        reallocate_array(tmemory, render.circles.base ref, maximum(render.circles.count, render.circles.require_used_count * 2));
        render.circles.require_used_count = 0;
    }
    
    {
        render.textures.base = {} render_2d_texture[];
        var texture_count = maximum(32, render.textures.count);

        if render.textures.require_used_count > render.textures.count
            texture_count *= 2;

        reallocate_array(tmemory, render.textures.base ref, texture_count);
        render.textures.require_used_count = 0;
    }
}

func get_y_sorted_position(render render_2d_api ref, position vec2, alignemnt = [ 0.5, 0 ] vec2) (result render_2d_position)
{
    var viewport_y = (position.y * render.context.draw_scale.y + render.context.draw_offset.y);
    var depth = (viewport_y / render.context.viewport_size.y) * 0.5;
    var result = { position, alignemnt, depth } render_2d_position;
    return result;
}

func draw_texture_box(render render_2d_api ref, position render_2d_position, size vec2, color = [ 1, 1, 1, 1 ] vec4, texture render_2d_texture, texture_box box2)
{
    if render.sprites.require_used_count >= render.sprites.count
    {
        render.sprites.require_used_count += 1;
        return;
    }
    
    {
        var used_count = minimum(render.textures.count, render.textures.require_used_count);
        
        var found_texture_index = u32_invalid_index;
        loop var texture_index u32; used_count
        {
            if render.textures[texture_index].handle is texture.handle
            {
                found_texture_index = texture_index;
                break;
            }
        }

        if found_texture_index is u32_invalid_index
        {
            if render.textures.require_used_count >= render.textures.count
            {
                render.textures.require_used_count += 1;
                return;
            }

            found_texture_index = render.textures.require_used_count cast(u32);
            render.textures.require_used_count += 1;
            render.textures[found_texture_index] = texture;
        }
    }

    var sprite = render.sprites[render.sprites.require_used_count] ref;
    render.sprites.require_used_count += 1;

    // sprite.texture_index = found_texture_index;    
    sprite.color     = color;
    sprite.pivot     = position.pivot;
    sprite.size      = size;
    sprite.alignment = position.alignment;    
    sprite.depth     = position.depth;    
    sprite.texture_box_min = texture_box.min;    
    sprite.texture_box_max = texture_box.max;    
}

func draw_circle(render render_2d_api ref, center vec2, radius f32, depth f32, color = [ 1, 1, 1, 1 ] vec4)
{
    if render.circles.require_used_count >= render.circles.count
    {
        render.circles.require_used_count += 1;
        return;
    }

    var circle = render.circles[render.circles.require_used_count] ref;
    render.circles.require_used_count += 1;

    circle.color  = color;
    circle.center = center;
    circle.radius = radius;
    circle.depth  = depth;
}

func execute(render render_2d_api ref, gl gl_api ref, tmemory memory_arena ref)
{
    glEnable(GL_DEPTH_TEST);

    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

    var sprites = { minimum(render.sprites.require_used_count, render.sprites.count), render.sprites.base.base } render_2d_gl_sprite[];

    var circles = { minimum(render.circles.require_used_count, render.circles.count), render.circles.base.base } render_2d_gl_circle[];

    if not sprites.count and not circles.count
        return;

    resize_buffer(gl, render.context_buffer ref, render_2d_gl_buffer.context_buffer, render.context ref, tmemory);

    resize_buffer(gl, render.sprite_buffer ref, render_2d_gl_buffer.sprite_buffer, sprites, tmemory);

    resize_buffer(gl, render.circle_buffer ref, render_2d_gl_buffer.circle_buffer, circles, tmemory);

    bind_uniform_buffer(render.context_buffer);
    bind_uniform_buffer(render.sprite_buffer);
    bind_uniform_buffer(render.circle_buffer);

    glBindVertexArray(render.gl_empty_vertex_array);

    if sprites.count
    {
        glUseProgram(render.shader_sprite.handle);            
        glDrawArraysInstanced(GL_TRIANGLES, 0, 6, sprites.count cast(u32));
    }

    if circles.count
    {
        glUseProgram(render.shader_circle.handle);            
        glDrawArraysInstanced(GL_TRIANGLES, 0, 6, circles.count cast(u32));
    }

    glUseProgram(0);
    glBindVertexArray(0);
}

