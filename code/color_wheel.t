
import ui;

struct color_hsva
{
    hue        f32;
    saturation f32;
    value      f32;
    alpha      f32;

    color rgbaf32;
}

func evaluate(color color_hsva ref)
{
    // copied from func color_wheel

    def hues =
    [
        [ 1, 0, 0 ] vec3,
        [ 1, 1, 0 ] vec3,
        [ 0, 1, 0 ] vec3,
        [ 0, 1, 1 ] vec3,
        [ 0, 0, 1 ] vec3,
        [ 1, 0, 1 ] vec3,
        [ 1, 0, 0 ] vec3,
    ] vec3[];

    var hue_index_f32 = color.hue * (hues.count - 1);
    var hue_blend = fmod(hue_index_f32, 1.0);
    var hue_index = hue_index_f32 cast(u32);
    var hue_color = lerp(hues[hue_index], hues[hue_index + 1], hue_blend);

    var saturation_color = lerp([ 1, 1, 1 ] vec3, hue_color, color.saturation);

    var color_rgb = lerp([ 0, 0, 0 ] vec3, saturation_color, color.value);

    color.color = vec4_expand(color_rgb, color.alpha);
}

func color_wheel(ui ui_system ref, layer s32 = 0, id ui_id, box box2, color color_hsva ref, with_alpha = true)
{
    draw_box(ui, layer, [ 255, 255, 255, 128 ] rgba8, box);

    def hues =
    [
        [ 1, 0, 0 ] vec3,
        [ 1, 1, 0 ] vec3,
        [ 0, 1, 0 ] vec3,
        [ 0, 1, 1 ] vec3,
        [ 0, 0, 1 ] vec3,
        [ 1, 0, 1 ] vec3,
        [ 1, 0, 0 ] vec3,
    ] vec3[];

    def margin = 4;
    var bar_count = 4 + with_alpha cast(f32);
    var bar_width  = get_size(box).width - (2 * margin);
    var bar_height = floor((get_size(box).height - margin) / bar_count) - margin;

    var bar_index = 1;

    // hue bar
    {
        var bar_box = box2_size(box.min.x + margin, box.max.y - (bar_index * (bar_height + margin)), bar_width, bar_height);
        bar_slider(color.hue ref, id + 0, bar_box, [ 1, 1, 1, 1 ] vec4, layer + 2, ui);

        var slice_width = floor(bar_width / (hues.count - 1));
        var slice_box = box2_size(bar_box.min, slice_width, bar_height);

        loop var i; hues.count - 1
        {
            var quad_infos =
            [
                { layer + 1, 1.0, to_rgba8(vec4_expand(hues[i], 1)) } ui_quad_info,
                { layer + 1, 1.0, to_rgba8(vec4_expand(hues[i + 1], 1)) } ui_quad_info,
                { layer + 1, 1.0, to_rgba8(vec4_expand(hues[i + 1], 1)) } ui_quad_info,
                { layer + 1, 1.0, to_rgba8(vec4_expand(hues[i], 1)) } ui_quad_info,
            ] ui_quad_info[];

            draw_box(ui, quad_infos, slice_box);
            slice_box.min.x += slice_width;
            slice_box.max.x += slice_width;
        }

        bar_index += 1;
    }

    var hue_index_f32 = color.hue * (hues.count - 1);
    var hue_blend = fmod(hue_index_f32, 1.0);
    var hue_index = hue_index_f32 cast(u32);
    var hue_color = lerp(hues[hue_index], hues[hue_index + 1], hue_blend);

    {
        var bar_box = box2_size(box.min.x + margin, box.max.y - (bar_index * (bar_height + margin)), bar_width, bar_height);
        bar_slider(color.saturation ref, id + 1, bar_box, [ 0, 0, 0, 1 ] vec4, layer + 2, ui);

        var quad_infos =
        [
            { layer + 1, 1.0, to_rgba8(vec4_expand([ 1, 1, 1] vec3, 1)) } ui_quad_info,
            { layer + 1, 1.0, to_rgba8(vec4_expand(hue_color, 1)) } ui_quad_info,
            { layer + 1, 1.0, to_rgba8(vec4_expand(hue_color, 1)) } ui_quad_info,
            { layer + 1, 1.0, to_rgba8(vec4_expand([ 1, 1, 1] vec3, 1)) } ui_quad_info,
        ] ui_quad_info[];

        draw_box(ui, quad_infos, bar_box);

        bar_index += 1;
    }

    var saturation_color = lerp([ 1, 1, 1 ] vec3, hue_color, color.saturation);

    {
        var bar_box = box2_size(box.min.x + margin, box.max.y - (bar_index * (bar_height + margin)), bar_width, bar_height);
        bar_slider(color.value ref, id + 2, bar_box, [ 1, 1, 1, 1 ] vec4, layer + 2, ui);

        var quad_infos =
        [
            { layer + 1, 1.0, to_rgba8(vec4_expand([ 0, 0, 0] vec3, 1)) } ui_quad_info,
            { layer + 1, 1.0, to_rgba8(vec4_expand(saturation_color, 1)) } ui_quad_info,
            { layer + 1, 1.0, to_rgba8(vec4_expand(saturation_color, 1)) } ui_quad_info,
            { layer + 1, 1.0, to_rgba8(vec4_expand([ 0, 0, 0] vec3, 1)) } ui_quad_info,
        ] ui_quad_info[];

        draw_box(ui, quad_infos, bar_box);

        bar_index += 1;
    }

    var color_rgb = lerp([ 0, 0, 0 ] vec3, saturation_color, color.value);

    if with_alpha
    {
        var bar_box = box2_size(box.min.x + margin, box.max.y - (bar_index * (bar_height + margin)), bar_width, bar_height);
        bar_slider(color.alpha ref, id + 3, bar_box, [ 1, 1, 1, 1 ] vec4, layer + 2, ui);

        var quad_infos =
        [
            { layer + 1, 1.0, to_rgba8(vec4_expand(color_rgb, 0)) } ui_quad_info,
            { layer + 1, 1.0, to_rgba8(vec4_expand(color_rgb, 1)) } ui_quad_info,
            { layer + 1, 1.0, to_rgba8(vec4_expand(color_rgb, 1)) } ui_quad_info,
            { layer + 1, 1.0, to_rgba8(vec4_expand(color_rgb, 0)) } ui_quad_info,
        ] ui_quad_info[];

        draw_box(ui, quad_infos, bar_box);
        bar_index += 1;
    }
    else
    {
        color.alpha = 1;
    }

    color.color = vec4_expand(color_rgb, color.alpha);

    {
        var slice_box = box2_size(box.min.x + margin, box.max.y - (bar_index * (bar_height + margin)), bar_width, bar_height);
        draw_box(ui, layer + 1, to_rgba8(color.color), slice_box);
    }
}

func bar_slider(value f32 ref, id ui_id, box box2, slider_color vec4, layer s32, ui ui_system ref) (slider_box box2)
{
    var is_hot = box_is_hot(ui, box);
    var result = drag(ui, id, ui.cursor, ui.cursor_left_active, is_hot);
    if result.is_dragging
    {
        value deref = (ui.cursor.x - box.min.x) / (box.max.x - box.min.x);
        value deref = clamp(value deref, 0, 1);
    }

    var slider_box box2;
    slider_box.min.x = lerp(box.min.x, box.max.x, value deref) - 2;
    slider_box.max.x = slider_box.min.x + 5;
    slider_box.max.y = box.max.y;
    slider_box.min.y = box.min.y;

    draw_box_lines(ui, layer, 1, to_rgba8(slider_color), slider_box, 3);

    return slider_box;
}