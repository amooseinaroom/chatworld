
struct string255
{
    count       u8;
    expand base u8[255];
}

func to_string255(text string) (result string255)
{
    var result string255;
    assert(text.count <= result.base.count);
    copy_array({ text.count, result.base.base } u8[], text);
    result.count = text.count cast(u8);

    return result;
}

func to_string(text string255) (result string)
{
    return { text.count, text.base.base } string;
}

func is(left string255, right string255) (ok b8)
{
    return to_string(left) is to_string(right);
}

func is_not(left string255, right string255) (ok b8)
{
    return to_string(left) is_not to_string(right);
}

struct string63
{
    count       u8;
    expand base u8[63];
}

func to_string63(text string) (result string63)
{
    var result string63;
    assert(text.count <= result.base.count);
    copy_array({ text.count, result.base.base } u8[], text);
    result.count = text.count cast(u8);

    return result;
}

func to_string(text string63) (result string)
{
    return { text.count, text.base.base } string;
}

func is(left string63, right string63) (ok b8)
{
    return to_string(left) is to_string(right);
}

func is_not(left string63, right string63) (ok b8)
{
    return to_string(left) is_not to_string(right);
}

func edit_string_begin(text_edit editable_text ref, text string255 ref)
{
    text_edit.buffer.count = text.base.count;
    text_edit.buffer.base = text.base.base;
}

func edit_string_end(text_edit editable_text, text string255 ref)
{
    text.count = text_edit.used_count cast(u8);
}

func edit_string_begin(text_edit editable_text ref, text string63 ref)
{
    text_edit.buffer.count = text.base.count;
    text_edit.buffer.base = text.base.base;
}

func edit_string_end(text_edit editable_text, text string63 ref)
{
    text.count = text_edit.used_count cast(u8);
}

def chat_text_color_idle     = [ 10, 10, 10, 255 ] rgba8;
def chat_text_color_shouting = [ 235, 30, 30, 255 ] rgba8;
def chat_box_color_idle      = [ 245, 245, 245, 255 ] rgba8;
def chat_box_color_shouting  = [ 255, 255, 135, 255 ] rgba8;

func apply_alpha(color rgba8, alpha f32) (result rgba8)
{
    color.a = (color.a * alpha) cast(u8);
    return color;
}

func get_chat_message_colors(text network_message_chat_text, alpha f32) (text_color rgba8, box_color rgba8)
{
    if text.is_shouting
        return apply_alpha(chat_text_color_shouting, alpha), apply_alpha(chat_box_color_shouting, alpha);
    else
        return apply_alpha(chat_text_color_idle, alpha), apply_alpha(chat_box_color_idle, alpha);
}

func skip_space(iterator string ref)
{
    try_skip_set(iterator, " \t\n\r");
}

func skip_name(iterator string ref) (name string)
{
    var name_blacklist = " \t\n\r\\\"\'+-*/.,:;~{}[]()<>|&!?=^°%";
    var name = try_skip_until_set(iterator, name_blacklist, false);
    return name;
}

func get_line_number(token string, text string) (line u32)
{
    assert((text.base <= token.base) and ((token.base + token.count) <= (text.base + text.count)));

    var line u32 = 1;
    var iterator = text;
    while iterator.base < token.base
    {
        if try_skip(iterator ref, "\n")
            line += 1;
        else
            advance(iterator ref);
    }

    return line;
}

func bit32(index u32) (mask u32)
{
    assert(index < 32);
    return 1 bit_shift_left index;
}

func bit64(index u64) (mask u64)
{
    assert(index < 64);
    return 1 bit_shift_left index;
}