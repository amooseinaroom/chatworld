
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

def idle_color = [ 50, 255, 255, 255 ] rgba8;
def hot_color  = [ 255, 255, 50, 255 ] rgba8;
def edit_color = [ 50, 255, 50, 255 ] rgba8;

func menu_button(menu menu_state ref, id ui_id, font ui_font, cursor font_cursor ref, text string) (ok b8)
{
    var ui = menu.ui;

	var box = draw_box_begin(ui);	
	print(ui, menu_layer.text, font, cursor, text);
	box = draw_box_end(ui, box);

    advance_line(font.info, cursor);
    advance_line(font.info, cursor);

    var color = idle_color;
    if id_is_hot(ui, id) or id_is_active(ui, id)
        color = hot_color;
	
	draw_rounded_box(ui, menu_layer.back, color, grow(box, 8), 6);

	return button(ui, id, box, 0);
}

func menu_text_edit(menu menu_state ref, id ui_id, font ui_font, cursor font_cursor ref, text_edit editable_text ref) (ok b8)
{
    var ui = menu.ui;

    if menu.acitve_text_edit_id is id
    {
        edit_text(text_edit, menu.characters ref);
    }

    var text = get_text(text_edit deref);

    var box = draw_box_begin(ui);
    print(ui, menu_layer.text, font, cursor, " ");
	print(ui, menu_layer.text, font, cursor, text);
	box = draw_box_end(ui, box);

    advance_line(font.info, cursor);
    advance_line(font.info, cursor);

    var color = idle_color;
    if menu.acitve_text_edit_id is id
        color = edit_color;
    if id_is_hot(ui, id) or id_is_active(ui, id)
        color = hot_color;

    // box.max.y = maximum(box.max.y, box.min.y + 10);
    box.max.x = maximum(box.max.x, box.min.x + 100);
	
	draw_rounded_box(ui, menu_layer.back, color, grow(box, 8), 6);

    var ok = button(ui, id, box, 0);
    if ok
        menu.acitve_text_edit_id = id;

    return ok;
}