
module render_2d;

import gl;
import math;
import memory;
import platform;
import string;
import meta;
import stb_image;
import stb_truetype;

struct render_2d_api
{
    context render_2d_context;

    shaders  render_2d_shader_buffer;
    textures render_2d_texture_buffer;
    sprites  render_2d_gl_sprite_buffer;
    circles  render_2d_gl_circle_buffer;

    shader_sprite render_2d_shader;
    shader_circle render_2d_shader;
    shader_sprite_info render_2d_shader_info;
    shader_circle_info render_2d_shader_info;

    gl_empty_vertex_array u32;

    context_buffer gl_uniform_buffer2;
    sprite_buffer  gl_uniform_buffer2;
    circle_buffer  gl_uniform_buffer2;

    sprite_cache render_2d_sprite_info[32 * 32];
    sprite_atlas render_2d_texture;
    sprite_atlas_texture_index u32;
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
    min_alpha     f32;
}

struct render_2d_shader_info
{
    vertex_source_write_timestamp   u64;
    fragment_source_write_timestamp u64;
    shader_index                    u32;
}

struct render_2d_shader
{
    handle u32;

    main_texture s32;
}

struct render_2d_shader_buffer
{
    expand base           render_2d_shader[];
           required_count usize;
}

struct render_2d_texture
{
    expand base gl_texture;
}

struct render_2d_texture_buffer
{
    expand base           render_2d_texture[];
           required_count usize;
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
    atlas_texture_index u32;
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
           shader_index       u32[];
           texture_index      u32[];
           required_count usize;
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
           shader_index       u32[];
           texture_index      u32[];
           required_count usize;
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

    resize_buffer(gl, render.context_buffer ref, render_2d_gl_buffer.context_buffer, {} render_2d_context[]);
    resize_buffer(gl, render.sprite_buffer ref, render_2d_gl_buffer.sprite_buffer, {} render_2d_gl_sprite[]);
    resize_buffer(gl, render.circle_buffer ref, render_2d_gl_buffer.circle_buffer, {} render_2d_gl_circle[]);

    // load shaders from embedded text on release
    if not lang_debug
    {
        var result = reload_shader(gl, render.shader_sprite ref, "render 2d sprite", get_type_info(render_2d_gl_vertex_attribute), get_type_info(render_2d_gl_buffer), render_2d_gl_shader_sprite_vert, false, render_2d_gl_shader_sprite_frag, tmemory);
        require(result.ok);

        result = reload_shader(gl, render.shader_circle ref, "render 2d sprite", get_type_info(render_2d_gl_vertex_attribute), get_type_info(render_2d_gl_buffer), render_2d_gl_shader_sprite_vert, false, render_2d_gl_shader_sprite_frag, tmemory);
        require(result.ok);
    }

    render.sprite_atlas.base = gl_create_texture_2d(2048, 2048, {} u8[]);
}

func frame(platform platform_api ref, gl gl_api ref, render render_2d_api ref, context render_2d_context, sprite_paths string[], tmemory memory_arena ref)
{
    render.context = context;

    {
        render.sprites.base = {} render_2d_gl_sprite[];
        render.sprites.shader_index = {} u32[];
        render.sprites.texture_index = {} u32[];

        var count = maximum(render.sprites.count, render.sprites.required_count * 2);

        reallocate_array(tmemory, render.sprites.base ref, count);
        reallocate_array(tmemory, render.sprites.shader_index ref, count);
        reallocate_array(tmemory, render.sprites.texture_index ref, count);

        render.sprites.required_count = 0;
    }

    {
        render.circles.base = {} render_2d_gl_circle[];
        render.circles.shader_index = {} u32[];
        render.circles.texture_index = {} u32[];

        var count = maximum(render.circles.count, render.circles.required_count * 2);

        reallocate_array(tmemory, render.circles.base ref, count);
        reallocate_array(tmemory, render.circles.shader_index ref, count);
        reallocate_array(tmemory, render.circles.texture_index ref, count);
        render.circles.required_count = 0;
    }

    {
        render.shaders.base = {} render_2d_shader[];

        var shader_count = maximum(32, render.shaders.count);

        if render.shaders.required_count > render.shaders.count
            shader_count *= 2;

        reallocate_array(tmemory, render.shaders.base ref, shader_count);
        render.shaders.required_count = 0;
        clear(to_u8_array(render.shaders.base));
    }

    {
        render.textures.base = {} render_2d_texture[];
        var texture_count = maximum(32, render.textures.count);

        if render.textures.required_count > render.textures.count
            texture_count *= 2;

        reallocate_array(tmemory, render.textures.base ref, texture_count);
        render.textures.required_count = 0;
        clear(to_u8_array(render.textures.base));
    }

    var tmemory_frame = temporary_begin(tmemory);

    // hot reload shaders while deubbing
    if lang_debug
    {
        frame_shader(platform, gl, render, render.shader_sprite ref, render.shader_sprite_info ref, "render 2d sprite", "code/glsl/render_2d_sprite.vert.glsl", "code/glsl/render_2d_sprite.frag.glsl", tmemory);

        frame_shader(platform, gl, render, render.shader_circle ref, render.shader_circle_info ref, "render 2d circle", "code/glsl/render_2d_circle.vert.glsl", "code/glsl/render_2d_circle.frag.glsl", tmemory);
    }

    render.shader_sprite_info.shader_index = get_shader_index(render, render.shader_sprite);
    render.shader_circle_info.shader_index = get_shader_index(render, render.shader_circle);

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

    render.sprite_atlas_texture_index = get_texture_index(render, render.sprite_atlas);

    temporary_end(tmemory, tmemory_frame);
}

func frame_shader(platform platform_api ref, gl gl_api ref, render render_2d_api ref, shader render_2d_shader ref, info render_2d_shader_info ref, name string, vertex_source_path string, fragment_source_path string, tmemory memory_arena ref) (ok b8)
{
    var vertex_source string;
    var fragment_source string;

    var ok = true;
    var file_info = platform_get_file_info(platform, vertex_source_path);
    ok and= file_info.ok and (file_info.write_timestamp is_not info.vertex_source_write_timestamp);
    if ok
        info.vertex_source_write_timestamp = file_info.write_timestamp;

    file_info = platform_get_file_info(platform, fragment_source_path);
    ok or= file_info.ok and (file_info.write_timestamp is_not info.fragment_source_write_timestamp);
    if ok
        info.fragment_source_write_timestamp = file_info.write_timestamp;

    if ok
    {
        var result = try_platform_read_entire_file(platform, tmemory, vertex_source_path);
        ok and= result.ok;
        vertex_source = result.data;
    }

    if ok
    {
        var result = try_platform_read_entire_file(platform, tmemory, fragment_source_path);
        ok and= result.ok;
        fragment_source = result.data;
    }

    if ok
    {
        var result = reload_shader(gl, shader, name, get_type_info(render_2d_gl_vertex_attribute), get_type_info(render_2d_gl_buffer), vertex_source, false, fragment_source, tmemory);
        ok and= result.ok;
    }

    return ok;
}

func get_shader_index(render render_2d_api ref, shader render_2d_shader) (shader_index u32)
{
    var found_shader_index = u32_invalid_index;
    var used_count = minimum(render.shaders.count, render.shaders.required_count);
    loop var shader_index u32; used_count
    {
        if render.shaders[shader_index].handle is shader.handle
        {
            found_shader_index = shader_index;
            break;
        }
    }

    if found_shader_index is u32_invalid_index
    {
        render.shaders.required_count += 1;

        if render.shaders.required_count < render.shaders.count
        {
            found_shader_index = (render.shaders.required_count - 1) cast(u32);
            render.shaders[found_shader_index] = shader;
        }
    }

    return found_shader_index;
}

func get_texture_index(render render_2d_api ref, texture render_2d_texture) (texture_index u32)
{
    var found_texture_index = u32_invalid_index;
    var used_count = minimum(render.textures.count, render.textures.required_count);
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
        render.textures.required_count += 1;

        if render.textures.required_count < render.textures.count
        {
            found_texture_index = (render.textures.required_count - 1) cast(u32);
            render.textures.required_count += 1;
            render.textures[found_texture_index] = texture;
        }
    }

    return found_texture_index;
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

func draw_sprite(render render_2d_api ref, sprite_id u32, shader_index u32 = u32_invalid_index, transform render_2d_transform, color = [ 1, 1, 1, 1 ] vec4)
{
    assert(sprite_id);

    if shader_index is u32_invalid_index
        shader_index = render.shader_sprite_info.shader_index;

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
    draw_texture_box(render, shader_index, transform, size, color, render.sprite_atlas_texture_index, texture_box);
}

func draw_texture_box(render render_2d_api ref, shader_index = u32_invalid_index, transform render_2d_transform, size vec2, color = [ 1, 1, 1, 1 ] vec4, texture_index u32, texture_box box2)
{
    render.sprites.required_count += 1;

    if shader_index is u32_invalid_index
        shader_index = render.shader_sprite_info.shader_index;

    if shader_index >= render.shaders.count
        return;

    if texture_index >= render.textures.count
        return;

    if render.sprites.required_count > render.sprites.count
        return;

    assert(shader_index < render.shaders.required_count);
    assert(texture_index < render.textures.required_count);

    var sprite = render.sprites[render.sprites.required_count - 1] ref;
    render.sprites.shader_index[render.sprites.required_count - 1]  = shader_index;
    render.sprites.texture_index[render.sprites.required_count - 1] = texture_index;

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

func draw_circle(render render_2d_api ref, shader_index = u32_invalid_index, center vec2, radius f32, depth f32, color = [ 1, 1, 1, 1 ] vec4)
{
    render.circles.required_count += 1;

    var texture_index u32 = 0;

    if shader_index is u32_invalid_index
        shader_index = render.shader_circle_info.shader_index;

    if shader_index >= render.shaders.count
        return;

    if texture_index >= render.textures.count
        return;

    if render.circles.required_count > render.circles.count
        return;

    assert(shader_index < render.shaders.required_count);
    assert(texture_index < render.textures.required_count);

    var circle = render.circles[render.circles.required_count - 1] ref;
    render.circles.shader_index[render.circles.required_count - 1] = shader_index;
    render.circles.texture_index[render.circles.required_count - 1] = texture_index;

    circle.color  = color;
    circle.center = center;
    circle.radius = radius;
    circle.depth  = depth;
}

def render_2d_font_line_advance_pixel_height = 32 cast(s32);

func frame_font(platform platform_api ref, render render_2d_api ref, font render_2d_font ref, font_paths string[], tmemory memory_arena ref)
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

    font.atlas_texture_index = get_texture_index(render, font.atlas);
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

            draw_texture_box(render, transform, size, color, font.atlas_texture_index, texture_box);

            font.cursor.baseline_x += glyph.x_advance;
        }
    }
}

func execute(render render_2d_api ref, gl gl_api ref, tmemory memory_arena ref)
{
    glEnable(GL_DEPTH_TEST);

    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

    var shaders = { minimum(render.shaders.required_count, render.shaders.count), render.shaders.base.base } render_2d_shader[];
    var textures = { minimum(render.textures.required_count, render.textures.count), render.textures.base.base } render_2d_texture[];

    // var sprites = { minimum(render.sprites.required_count, render.sprites.count), render.sprites.base.base } render_2d_gl_sprite[];
    var circles = { minimum(render.circles.required_count, render.circles.count), render.circles.base.base } render_2d_gl_circle[];

    var sprite_count = minimum(render.sprites.required_count, render.sprites.count);
    var circle_count = minimum(render.circles.required_count, render.circles.count);

    if not sprite_count and not circle_count
        return;

    {
        var context_array render_2d_context[];

        // first pass
        reallocate_array(tmemory, context_array ref, 1);
        context_array[0] = render.context;
        context_array[0].min_alpha = 1;

        // second pass
        reallocate_array_to_uniform_buffer_offset_alignment(gl, tmemory, render.context_buffer, context_array ref);
        reallocate_array(tmemory, context_array ref, context_array.count + 1);
        context_array[context_array.count - 1] = render.context;
        context_array[context_array.count - 1].min_alpha = 0;

        resize_buffer(gl, render.context_buffer ref, render_2d_gl_buffer.context_buffer, context_array);
        reallocate_array(tmemory, context_array ref, 0);
    }

    {
        var sprites render_2d_gl_sprite[];

        loop var shader_index u32; shaders.count
        {
            loop var texture_index u32; textures.count
            {
                reallocate_array_to_uniform_buffer_offset_alignment(gl, tmemory, render.sprite_buffer, sprites ref);

                loop var sprite_index u32; sprite_count
                {
                    if (render.sprites.shader_index[sprite_index] is_not shader_index) or (render.sprites.texture_index[sprite_index] is_not texture_index)
                        continue;

                    reallocate_array(tmemory, sprites ref, sprites.count + 1);
                    sprites[sprites.count - 1] = render.sprites[sprite_index];
                }
            }
        }

        resize_buffer(gl, render.sprite_buffer ref, render_2d_gl_buffer.sprite_buffer, sprites);
        reallocate_array(tmemory, sprites ref, 0);
    }

    {
        var circles render_2d_gl_circle[];

        loop var shader_index u32; shaders.count
        {
            loop var texture_index u32; textures.count
            {
                reallocate_array_to_uniform_buffer_offset_alignment(gl, tmemory, render.circle_buffer, circles ref);

                loop var circle_index u32; circle_count
                {
                    if (render.circles.shader_index[circle_index] is_not shader_index) or (render.circles.texture_index[circle_index] is_not texture_index)
                        continue;

                    reallocate_array(tmemory, circles ref, circles.count + 1);
                    circles[circles.count - 1] = render.circles[circle_index];
                }
            }
        }

        resize_buffer(gl, render.circle_buffer ref, render_2d_gl_buffer.circle_buffer, circles);
        reallocate_array(tmemory, circles ref, 0);
    }

    glBindVertexArray(render.gl_empty_vertex_array);

    var context_offset u32;
    loop var pass u32; 2
    {
        uniform_buffer_align_offset(render.context_buffer, context_offset ref);
        bind_uniform_buffer(gl, render.context_buffer, context_offset);
        context_offset += 1;

        glDepthMask((pass is 0) cast(GLboolean));

        var sprite_offset u32;
        loop var shader_index u32; shaders.count
        {
            glUseProgram(render.shaders[shader_index].handle);
            glUniform1i(render.shaders[shader_index].main_texture, 0);

            glActiveTexture(GL_TEXTURE0);

            loop var texture_index u32; textures.count
            {
                var instance_count u32;
                loop var sprite_index u32; sprite_count
                {
                    if (render.sprites.shader_index[sprite_index] is_not shader_index) or (render.sprites.texture_index[sprite_index] is_not texture_index)
                        continue;

                    instance_count += 1;
                }

                if instance_count
                {
                    glBindTexture(GL_TEXTURE_2D, textures[texture_index].handle);

                    uniform_buffer_align_offset(render.sprite_buffer, sprite_offset ref);
                    bind_uniform_buffer(gl, render.sprite_buffer, sprite_offset);
                    glDrawArraysInstanced(GL_TRIANGLES, 0, 6, instance_count);
                }

                sprite_offset += instance_count;
            }
        }

        var circle_offset u32;
        loop var shader_index u32; shaders.count
        {
            glUseProgram(render.shaders[shader_index].handle);
            glUniform1i(render.shaders[shader_index].main_texture, 0);

            glActiveTexture(GL_TEXTURE0);

            loop var texture_index u32; textures.count
            {
                var instance_count u32;
                loop var circle_index u32; circle_count
                {
                    if (render.circles.shader_index[circle_index] is_not shader_index) or (render.circles.texture_index[circle_index] is_not texture_index)
                        continue;

                    instance_count += 1;
                }

                if instance_count
                {
                    glBindTexture(GL_TEXTURE_2D, textures[texture_index].handle);

                    uniform_buffer_align_offset(render.circle_buffer, circle_offset ref);
                    bind_uniform_buffer(gl, render.circle_buffer, circle_offset);
                    glDrawArraysInstanced(GL_TRIANGLES, 0, 6, instance_count);
                }

                circle_offset += instance_count;
            }
        }
    }

    glBindTexture(GL_TEXTURE_2D, 0);

    glDepthMask(GL_TRUE);
    glUseProgram(0);
    glBindVertexArray(0);
}
