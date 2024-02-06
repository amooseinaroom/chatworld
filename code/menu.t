
func menu_button(ui ui_system ref, id ui_id, font ui_font, cursor font_cursor ref, text string) (ok b8)
{
	var box = draw_box_begin(ui);	
	print(ui, 11, font, cursor, text);
	box = draw_box_end(ui, box);

    advance_line(font.info, cursor);
    advance_line(font.info, cursor);

    var color = [ 50, 255, 255, 255 ] rgba8;
    if id_is_hot(ui, id) or id_is_active(ui, id)
        color = [ 255, 255, 50, 255 ] rgba8;
	
	draw_rounded_box(ui, 10, color, grow(box, 8), 6);

	return button(ui, id, box, 0);
}