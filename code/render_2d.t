
module render_2d;

import gl;
import math;
import memory;
import platform;
import string;
import stb_image;
import stb_truetype;

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

    sprite_cache render_2d_sprite_info[32 * 32];
    sprite_atlas render_2d_texture;
}

def render_2d_sprite_size = 64 cast(s32);

struct render_2d_sprite_info
{
    id                 u32; // 0 means unused
    unused_frame_count u32;
    is_loaded          b8;
}

struct render_2d_context
{
    viewport_size vec2;
    draw_offset   vec2;
    draw_scale    f32;
    _unused0      f32;
}

struct render_2d_texture
{
    expand base gl_texture;
}

struct render_2d_texture_buffer
{
    expand base               render_2d_texture[];
           require_used_count usize;
}

struct render_2d_glyph
{
    x      s32;
    y      s32;
    width  s32;
    height s32;

    x_draw_offset s32;
    y_draw_offset s32;

    x_advance s32;
}

struct render_2d_glyph_key
{
    utf32_code         u32;
    unused_frame_count u16;
    pixel_height       u8;
    font_index         u8;
}

def render_2d_font_count       = 32;
def render_2d_font_glyph_count = 8192;
def render_2d_glyph_key_unused_frame_count_uninitialized = -1 cast(u16);

struct render_2d_font
{
    glyph_key  render_2d_glyph_key[render_2d_font_glyph_count];
    glyph      render_2d_glyph[render_2d_font_glyph_count];
    used_count u32;

    font_unscaled_line_advance f32[render_2d_font_count];

    settings render_2d_font_settings;
    cursor   render_2d_font_cursor;

    atlas            render_2d_texture;
    atlas_x          s32;
    atlas_y          s32;
    atlas_row_height s32;
}

struct render_2d_font_settings
{
    pixel_height u8;
    font_index   u8;
}

struct render_2d_font_cursor
{
    baseline_x      s32;
    baseline_y      s32;
    line_start_x    s32;
    depth           f32;
    pending_newline b8;
}

struct render_2d_transform
{
    pivot     vec2;
    alignment vec2;
    depth     f32;
    rotation  f32;
    flip_x    b8;
    flip_y    b8;
}

struct render_2d_gl_sprite
{
    color           vec4;
    pivot           vec2;
    size            vec2;
    alignment       vec2;
    depth           f32;
    rotation        f32;
    texture_box_min vec2;
    texture_box_max vec2;
}

struct render_2d_gl_sprite_buffer
{
    expand base               render_2d_gl_sprite[];
           texture_index      u32[];
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
    assert(result.ok, "shader error: %", result.error_messages);

    result = reload_shader(gl, render.shader_circle, "render 2d circle", get_type_info(render_2d_gl_vertex_attribute), get_type_info(render_2d_gl_buffer), render_2d_gl_shader_circle_vert, false, render_2d_gl_shader_circle_frag, tmemory);
    assert(result.ok, "shader error: %", result.error_messages);

    render.sprite_atlas.base = gl_create_texture_2d(2048, 2048, {} u8[]);
}

func frame(platform platform_api ref, render render_2d_api ref, context render_2d_context, sprite_paths string[], tmemory memory_arena ref)
{
    render.context = context;

    {
        render.sprites.base = {} render_2d_gl_sprite[];
        render.sprites.texture_index = {} u32[];
        var count = maximum(render.sprites.count, render.sprites.require_used_count * 2);
        reallocate_array(tmemory, render.sprites.base ref, count);
        reallocate_array(tmemory, render.sprites.texture_index ref, count);
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

    {
        stbi_set_flip_vertically_on_load(1);

        glBindTexture(GL_TEXTURE_2D, render.sprite_atlas.handle);

        var cache = render.sprite_cache ref;
        loop var i u32; cache.count
        {
            if (cache[i].id is_not 0) and (not cache[i].is_loaded)
            {
                assert((cache[i].id - 1) < sprite_paths.count);
                var path = sprite_paths[cache[i].id - 1];
                var result = try_platform_read_entire_file(platform, tmemory, path);
                if not result.ok
                    continue;

                var width  s32;
                var height s32;
                var ignored s32;
                var pixels = stbi_load_from_memory(result.data.base, result.data.count cast(s32), width ref, height ref, ignored ref, 4) cast(rgba8 ref);
                assert((width is render_2d_sprite_size) and (height is render_2d_sprite_size));

                var x = (i mod 32) * render_2d_sprite_size;
                var y = (i / 32) * render_2d_sprite_size;
                glTexSubImage2D(GL_TEXTURE_2D, 0, x, y, render_2d_sprite_size cast(s32), render_2d_sprite_size cast(s32), GL_RGBA, GL_UNSIGNED_BYTE, pixels);

                cache[i].is_loaded = true;
            }
        }

        glBindTexture(GL_TEXTURE_2D, 0);
    }
}

func get_y_sorted_transform(render render_2d_api ref, position vec2, alignemnt = [ 0.5, 0 ] vec2) (result render_2d_transform)
{
    var viewport_y = (position.y * render.context.draw_scale + render.context.draw_offset.y);
    var depth = (viewport_y / render.context.viewport_size.y) * 0.5 + 0.25;
    var result = { position, alignemnt, depth, 0, false, false } render_2d_transform;
    return result;
}

// TODO: ignores rotation for now
func get_viewport_point(render render_2d_api ref, point vec2) (viewport_point vec2)
{
    var viewport_point = point * render.context.draw_scale + render.context.draw_offset;
    return viewport_point;
}

func get_world_point(render render_2d_api ref, viewport_point vec2) (point vec2)
{
    var point = (viewport_point - render.context.draw_offset) * (1.0 / render.context.draw_scale);
    return point;
}

func get_viewport_box(render render_2d_api ref, transform render_2d_transform, size vec2) (box box2)
{    
    var a = transform.pivot + scale(size, -transform.alignment);
    var min = get_viewport_point(render, a);
    var max = get_viewport_point(render, a + size);

    return { min, max } box2;
}

func draw_sprite(render render_2d_api ref, sprite_id u32, transform render_2d_transform, color = [ 1, 1, 1, 1 ] vec4)
{
    assert(sprite_id);

    var cache = render.sprite_cache ref;
    var found_index = u32_invalid_index;
    loop var i u32; cache.count
    {
        if cache[i].id is sprite_id
        {
            found_index = i;
            break;
        }
    }

    if found_index is u32_invalid_index
    {
        var max_unused_frame_count u32;
        loop var i u32; cache.count
        {
            if cache[i].id is 0
            {
                found_index = i;
                break;
            }
            else if (cache[i].unused_frame_count > max_unused_frame_count)
            {
                max_unused_frame_count = cache[i].unused_frame_count;
                found_index = i;
            }
        }

        assert(found_index is_not u32_invalid_index);
        var info = cache[found_index] ref;
        info.id          = sprite_id;
        info.is_loaded   = false;
    }

    var info = cache[found_index] ref;
    assert(info.id is sprite_id);
    info.unused_frame_count = 0;

    if not info.is_loaded
        return;

    var texel_scale = 1.0 / 2048;
    var texture_box box2;
    texture_box.min = [ (found_index mod 32) * render_2d_sprite_size, (found_index / 32) * render_2d_sprite_size ] vec2 + 0.5 * texel_scale;
    texture_box.max = v2(render_2d_sprite_size - 1 * texel_scale) + texture_box.min;

    var size = v2(1.0); // assume sprites are 1 world unit big
    draw_texture_box(render, transform, size, color, render.sprite_atlas, texture_box);
}

func draw_texture_box(render render_2d_api ref, transform render_2d_transform, size vec2, color = [ 1, 1, 1, 1 ] vec4, texture render_2d_texture, texture_box box2)
{
    if render.sprites.require_used_count >= render.sprites.count
    {
        render.sprites.require_used_count += 1;
        return;
    }
    
    var found_texture_index = u32_invalid_index;
    {
        var used_count = minimum(render.textures.count, render.textures.require_used_count);
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
    render.sprites.texture_index[render.sprites.require_used_count] = found_texture_index;
    render.sprites.require_used_count += 1;

    {
        var blend_flip = [ transform.flip_x cast(f32), transform.flip_y cast(f32) ] vec2;
        var min = lerp(texture_box.min, texture_box.max, blend_flip);
        var max = lerp(texture_box.min, texture_box.max, v2(1) - blend_flip);
        texture_box.min = min;
        texture_box.max = max;
    }

    // sprite.texture_index = found_texture_index;
    sprite.color     = color;
    sprite.pivot     = transform.pivot;
    sprite.size      = size;
    sprite.alignment = transform.alignment;
    sprite.depth     = transform.depth;
    sprite.rotation  = transform.rotation;
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

def render_2d_font_line_advance_pixel_height = 32 cast(s32);

func font_frame(platform platform_api ref, render render_2d_api ref, font render_2d_font ref, font_paths string[], tmemory memory_arena ref)
{
    var tmemory_frame = temporary_begin(tmemory);

    if not font.atlas.base.handle
        font.atlas.base = gl_create_texture_2d(2048, 2048, {} u8[], GL_RED, true, [ GL_ONE, GL_ONE, GL_ONE, GL_RED ] u32[]);
    
    var stbtt_info stbtt_fontinfo[render_2d_font_count];
    assert(font_paths.count <= stbtt_info.count);

    loop var i u32; font_paths.count
    {
        var result = try_platform_read_entire_file(platform, tmemory, font_paths[i]);
        if not result.ok
            continue;
        
        stbtt_InitFont(stbtt_info[i] ref, result.data.base, 0);       

        // we store the line advance relative to render_2d_font_line_advance_pixel_height
        // and then we can compute the actual advance when looking at specific pixel_height
        var scale = stbtt_ScaleForPixelHeight(stbtt_info[i] ref, render_2d_font_line_advance_pixel_height);
        var ascent s32;
        var decent s32;
        var line_gab s32;
        stbtt_GetFontVMetrics(stbtt_info[i] ref, ascent ref, decent ref, line_gab ref);
        font.font_unscaled_line_advance[i] = scale * (ascent - decent + line_gab);
    }

    glBindTexture(GL_TEXTURE_2D, font.atlas.base.handle);

    loop var i u32; font.used_count
    {
        var key = font.glyph_key[i] ref;
        if (key.unused_frame_count is render_2d_glyph_key_unused_frame_count_uninitialized)
        {
            assert(key.font_index < font_paths.count);

            // font file was not loaded
            if not stbtt_info[key.font_index].data
                continue;

            var info = stbtt_info[key.font_index] ref;

            var scale = stbtt_ScaleForPixelHeight(info, key.pixel_height);

            var x0 s32;
            var x1 s32;
            var y0 s32;
            var y1 s32;
            stbtt_GetCodepointBitmapBoxSubpixel(info, key.utf32_code, scale, scale, 0, 0, x0 ref, y0 ref, x1 ref, y1 ref);

            var width  = x1 - x0;
            var height = y1 - y0;
            if font.atlas_x + width > render.sprite_atlas.width
            {
                font.atlas_x = 0;
                font.atlas_y += font.atlas_row_height + 1; // plus 1 pixel frame
                font.atlas_row_height = 0;
                assert(font.atlas_x + width <= render.sprite_atlas.width);
            }
            
            assert(font.atlas_y + height <= render.sprite_atlas.height);

            {
                var glyph_pixels u8[];
                var pitch = ((width + 3) bit_and bit_not (3 cast(s32))); // align rows to 4 byte
                reallocate_array(tmemory, glyph_pixels ref, (pitch * height) cast(usize));

                stbtt_MakeCodepointBitmapSubpixel(info, glyph_pixels.base, width, height, pitch, scale, scale, 0, 0, key.utf32_code);

                // flip top-down
                loop var y; height / 2
                {
                    var mirrored_y = height - 1 - y;

                    loop var x; width
                    {
                        var temp = glyph_pixels[y * pitch + x];
                        glyph_pixels[y * pitch + x] = glyph_pixels[mirrored_y * pitch + x];
                        glyph_pixels[mirrored_y * pitch + x] = temp;
                    }
                }

                glTexSubImage2D(GL_TEXTURE_2D, 0, font.atlas_x, font.atlas_y, width, height, GL_RED, GL_UNSIGNED_BYTE, glyph_pixels.base);

                reallocate_array(tmemory, glyph_pixels ref, 0);
            }
            
            var glyph = font.glyph[i] ref;            
            glyph.x = font.atlas_x;
            glyph.y = font.atlas_y;
            glyph.width  = width;
            glyph.height = height;
            glyph.x_draw_offset = x0;
            glyph.y_draw_offset = -y1;

            font.atlas_x += width + 1; // plus 1 pixel frame
            font.atlas_row_height = maximum(font.atlas_row_height, height);

            var x_advance s32;
            var ignored s32;
            stbtt_GetCodepointHMetrics(info, key.utf32_code, x_advance ref, ignored ref);
            glyph.x_advance = ceil(x_advance * scale) cast(s32);

            key.unused_frame_count = 0;
        }
    }

    glBindTexture(GL_TEXTURE_2D, 0);

    temporary_end(tmemory, tmemory_frame);
}

func draw_text(render render_2d_api ref, rotation = 0.0, alignment = [ 0, 0 ] vec2, zoom = 1.0, font render_2d_font ref, color = [ 1, 1, 1, 1 ] vec4, text string)
{
    var texel_scale = [ 1.0 / font.atlas.width, 1.0 / font.atlas.height ] vec2;
    var inverse_draw_scale = (1.0 / render.context.draw_scale);

    var settings = font.settings;
    var iterator = text;
    while iterator.count
    {        
        var result = utf8_advance(iterator ref);

        if font.cursor.pending_newline
        {
            assert(settings.font_index < font.font_unscaled_line_advance.count);
            var line_advance = ceil(font.font_unscaled_line_advance[settings.font_index] * settings.pixel_height / render_2d_font_line_advance_pixel_height) cast(s32);

            font.cursor.baseline_x = font.cursor.line_start_x;
            font.cursor.baseline_y -= line_advance;
            font.cursor.pending_newline = false;            
        }

        if result.code is "\n"[0]
        {
            font.cursor.pending_newline = true;
            continue;
        }

        var found_index = u32_invalid_index;
        loop var i u32; font.used_count
        {
            var key = font.glyph_key[i];
            if (key.font_index is settings.font_index) and (key.pixel_height is settings.pixel_height) and (key.utf32_code is result.code)
            {
                found_index = i;

                if key.unused_frame_count is_not render_2d_glyph_key_unused_frame_count_uninitialized
                    font.glyph_key[i].unused_frame_count = 0;

                // render the glyph
                break;
            }
        }

        if found_index is u32_invalid_index
        {
            assert(font.used_count < font.glyph_key.count);            
            
            var key = font.glyph_key[font.used_count] ref;
            key deref = {} render_2d_glyph_key;
            font.used_count += 1;

            key.font_index         = settings.font_index;
            key.pixel_height       = settings.pixel_height;
            key.utf32_code         = result.code;
            key.unused_frame_count = render_2d_glyph_key_unused_frame_count_uninitialized;
        }
        else if font.glyph_key[found_index].unused_frame_count is_not render_2d_glyph_key_unused_frame_count_uninitialized
        {
            var glyph = font.glyph[found_index];
            var transform render_2d_transform;

            // from viewport to world coordinates
            transform.pivot.x = font.cursor.baseline_x + glyph.x_draw_offset;
            transform.pivot.y = font.cursor.baseline_y + glyph.y_draw_offset;            
            transform.pivot = get_world_point(render, transform.pivot);

            transform.depth = font.cursor.depth;
            transform.rotation = rotation;

            var texture_box box2;
            texture_box.min.x = glyph.x * texel_scale.x;
            texture_box.min.y = glyph.y * texel_scale.y;
            texture_box.max.x = glyph.width  * texel_scale.x + texture_box.min.x;
            texture_box.max.y = glyph.height * texel_scale.y + texture_box.min.y;

            var size = [ glyph.width, glyph.height ] vec2 * inverse_draw_scale;

            transform.alignment = alignment;
            transform.pivot += scale(size, alignment);
            size *= zoom;

            draw_texture_box(render, transform, size, color, font.atlas, texture_box);

            font.cursor.baseline_x += glyph.x_advance;
        }
    }
}

func execute(render render_2d_api ref, gl gl_api ref, tmemory memory_arena ref)
{
    glEnable(GL_DEPTH_TEST);

    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

    var textures = { minimum(render.textures.require_used_count, render.textures.count), render.textures.base.base } render_2d_texture[];
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

        // HACK: we only use one texture
        glUniform1i(render.shader_sprite.sprite_texture, 0);
        glActiveTexture(GL_TEXTURE0);

        loop var texture_index u32; textures.count
        {
            glBindTexture(GL_TEXTURE_2D, textures[texture_index].handle);
            
            loop var sprite_index u32; sprites.count
            {
                if render.sprites.texture_index[sprite_index] is_not texture_index
                    continue;

                bind_uniform_buffer(render.sprite_buffer, sprite_index, 1);

                glDrawArraysInstanced(GL_TRIANGLES, 0, 6, 1); // sprites.count cast(u32));
            }
        }

        glBindTexture(GL_TEXTURE_2D, 0);
    }

    if circles.count
    {
        glUseProgram(render.shader_circle.handle);
        glDrawArraysInstanced(GL_TRIANGLES, 0, 6, circles.count cast(u32));
    }

    glUseProgram(0);
    glBindVertexArray(0);
}


