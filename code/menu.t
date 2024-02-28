import font;

struct menu_state
{
    ui ui_system ref;

    characters platform_character[];

    acitve_text_edit_id ui_id;
}

enum menu_layer
{
    back = 1000;
    text;
}

// is srgb
// def menu_color_edit       = [ 190, 235, 95, 255 ] rgba8;
// def menu_color_idle       = [ 95, 235, 210, 255 ] rgba8;
// def menu_color_background = [ 140, 95, 235, 255 ] rgba8;
// def menu_color_hot        = [ 235, 95, 120, 255 ] rgba8;
def menu_color_edit        = [ 131, 211, 29, 255 ] rgba8;
def menu_color_idle        = [ 29, 211, 164, 255 ] rgba8;
def menu_color_background  = [ 66, 29, 211, 255 ] rgba8;
def menu_color_hot         = [ 211, 29, 47, 255 ] rgba8;
def menu_color_text_idle   = menu_color_background;
def menu_color_text_active = menu_color_hot;


def name_color = [ 250, 250, 250, 255 ] rgba8;
// def idle_color = [ 50, 255, 255, 255 ] rgba8;
// def hot_color  = [ 255, 255, 50, 255 ] rgba8;
// def edit_color = [ 50, 255, 50, 255 ] rgba8;

func menu_button(menu menu_state ref, id ui_id, font ui_font, cursor font_cursor ref, text string, is_toggled = false) (ok b8)
{
    var ui = menu.ui;

	var box = draw_box_begin(ui);
	print(ui, menu_layer.text, menu_color_text_idle, font, cursor, text);
	box = draw_box_end(ui, box);

    advance_line(font.info, cursor);
    advance_line(font.info, cursor);

    var color = menu_color_idle;
    if id_is_hot(ui, id) or id_is_active(ui, id)
        color = menu_color_hot;
    else if is_toggled
        color = menu_color_edit;

	draw_rounded_box(ui, menu_layer.back, color, grow(box, 8), 6);

	return button(ui, id, box, 0);
}

func menu_text_edit(menu menu_state ref, id ui_id, font ui_font, cursor font_cursor ref, text_edit editable_text ref) (ok b8)
{
    var ui = menu.ui;

    var text_color = menu_color_text_idle;
    if menu.acitve_text_edit_id is id
    {
        edit_text(text_edit, menu.characters ref);
        text_color = menu_color_text_active;
    }

    var color = menu_color_idle;
    if menu.acitve_text_edit_id is id
        color = menu_color_edit;
    if id_is_hot(ui, id) or id_is_active(ui, id)
    {
        color = menu_color_hot;
        text_color = menu_color_text_idle;
    }

    var text = get_text(text_edit deref);

    var box = draw_box_begin(ui);
    print(ui, menu_layer.text, text_color, font, cursor, " ");
	print(ui, menu_layer.text, text_color, font, cursor, text);
	box = draw_box_end(ui, box);

    advance_line(font.info, cursor);
    advance_line(font.info, cursor);

    // box.max.y = maximum(box.max.y, box.min.y + 10);
    box.max.x = maximum(box.max.x, box.min.x + 100);

	draw_rounded_box(ui, menu_layer.back, color, grow(box, 8), 6);

    var ok = button(ui, id, box, 0);
    if ok
        menu.acitve_text_edit_id = id;

    return ok;
}