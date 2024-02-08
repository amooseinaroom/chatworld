
import network;

def game_title = "chat world";

struct program_state
{
    expand default default_program_state;

    game game_state;

    network platform_network;

    is_host b8;    

    server game_server;
    client game_client;

    menu menu_state;    
}

func skip_space(iterator string ref)
{    
    try_skip_set(iterator, " \t\n\r");
}

func game_init program_init_type
{
    state.letterbox_width_over_heigth = 16.0 / 9.0;

    platform_network_init(state.network ref);
    //init(state.server ref, state.network ref);
    //init(client ref, state.network ref);

    var client = state.client ref;
    client.server_address.port = default_server_port;
    client.server_address.ip[0] = 127;
    client.server_address.ip[3] = 1;

    if false
    {
        var tmemory = state.temporary_memory ref;
        var source = platform_read_entire_file(platform, tmemory, "server.txt");

        var address string;
        var port u32;

        var it = source;
        skip_space(it ref);
        while it.count
        {
            if not try_skip(it ref, "server")
                assert(false);            

            skip_space(it ref);

            address = try_skip_until_set(it ref, " \t\n\r");            
            assert(address.count);
            
            if not try_parse_u32(port ref, it ref) and (port <= 65535)
                assert(false);

            skip_space(it ref);
            break;
        }

        if address.count
        {
            var records DNS_RECORD ref;
            var name_buffer u8[512];
            var status = DnsQuery_A(as_cstring(name_buffer, address), DNS_TYPE_A, DNS_QUERY_STANDARD, null, records cast(u8 ref) ref, null);
            var iterator = records;
            while iterator
            {
                client.server_address.ip = iterator.Data.A.IpAddress ref cast(platform_network_ip ref) deref;
                break;
                iterator = iterator.pNext;
            }

            DnsRecordListFree(records, 0);

            client.server_address.port = port cast(u16);
        }
    }
}

func game_update program_update_type
{
    var memory  = state.memory ref;
    var tmemory = state.temporary_memory ref;
    var ui      = state.ui ref;
    var game    = state.game ref;
    var client  = state.client ref;
    var menu = state.menu ref;
    menu.ui = ui;
    menu.characters = { platform.character_count, platform.character_buffer.base } platform_character[];

    var font = state.font;

    if client.state is client_state.disconnected
    {   
        var box = draw_box_begin(ui);
        var cursor = cursor_below_position(font.info, ui.viewport_size.width * 0.5, ui.viewport_size.height * 0.5);

        print(ui, menu_layer.text, font, cursor ref, "user: ");
        edit255_begin(client.user_name_edit ref, client.user_name ref);
        menu_text_edit(menu, location_id(0), font, cursor ref, client.user_name_edit ref);
        edit255_end(client.user_name_edit, client.user_name ref);

        print(ui, menu_layer.text, font, cursor ref, "password: ");
        edit255_begin(client.user_password_edit ref, client.user_password ref);
        menu_text_edit(menu, location_id(0), font, cursor ref, client.user_password_edit ref);
        edit255_end(client.user_password_edit, client.user_password ref);

        if menu_button(menu, location_id(0), font, cursor ref, "Host Server")
        {
            init(state.server ref, platform, state.network ref, client.server_address.port, tmemory);
            init(client, state.network ref, client.server_address);
            state.is_host = true;            
        }

        if menu_button(menu, location_id(0), font, cursor ref, "Connect")
        {            
            init(client, state.network ref, client.server_address);            
        }        
    }
    else
    {
        // update(platform, state);    

        var tiles_per_width = 20;
        var tiles_per_height = tiles_per_width / state.letterbox_width_over_heigth;

        var player = client.players[0] ref;

        client.frame_movement = {} vec2;
        client.frame_delta_seconds = 0;
        
        if game.is_chatting
        {
            client.chat_message_edit.buffer.count = client.chat_message.base.count;
            client.chat_message_edit.buffer.base  = client.chat_message.base.base;            

            edit255_begin(client.chat_message_edit ref, client.chat_message ref);

            edit_text(client.chat_message_edit ref, menu.characters ref);
            
            edit255_end(client.chat_message_edit, client.chat_message ref);
            
            if not platform_key_is_active(platform, platform_key.control) and not platform_key_is_active(platform, platform_key.alt) and not platform_key_is_active(platform, platform_key.shift) and platform_key_was_pressed(platform, platform_key.enter)
            {
                client.send_chat_message = true;
                client.chat_message = client.chat_message;
                game.is_chatting = false;
            }
        }
        else
        {
            if platform_key_was_pressed(platform, platform_key.enter)
            {
                game.is_chatting = true; 
                client.chat_message_edit.edit_offset = 0;
                client.chat_message_edit.used_count  = 0;
                client.chat_message.count            = 0;
            }

            var movement vec2;
            movement.x = platform_key_is_active(platform, "D"[0]) cast(s32) - platform_key_is_active(platform, "A"[0]) cast(s32);
            movement.y = platform_key_is_active(platform, "W"[0]) cast(s32) - platform_key_is_active(platform, "S"[0]) cast(s32);

            movement = normalize_or_zero(movement);

            var movement_speed = 6;
            // player.position += movement * (movement_speed * platform.delta_seconds);

            client.frame_movement = movement * movement_speed;
            client.frame_delta_seconds = platform.delta_seconds;

            var tile_frame = 4;
            if player.position.x > (game.camera_position.x + (tiles_per_width * 0.5) - tile_frame)
                game.camera_position.x = player.position.x - (tiles_per_width * 0.5) + tile_frame;
            else if player.position.x < (game.camera_position.x - (tiles_per_width * 0.5) + tile_frame)
                game.camera_position.x = player.position.x + (tiles_per_width * 0.5) - tile_frame;
            
            if player.position.y > (game.camera_position.y + (tiles_per_height * 0.5) - tile_frame)
                game.camera_position.y = player.position.y - (tiles_per_height * 0.5) + tile_frame;
            else if player.position.y < (game.camera_position.y - (tiles_per_height * 0.5) + tile_frame - 1)
                game.camera_position.y = player.position.y + (tiles_per_height * 0.5) - tile_frame + 1;
        }

        if state.is_host
            tick(platform, state.server ref, state.network ref);

        tick(client, state.network ref, platform.delta_seconds);

        var cursor = cursor_below_position(font.info, 20, ui.viewport_size.height - 20);
        print(ui, 10, font, cursor ref,  "fps: %\nhello world\n", 1.0 / platform.delta_seconds);

        var tile_size = ui.viewport_size.width / tiles_per_width;

        var tile_offset = floor(ui.viewport_size * 0.5 + (game.camera_position * -tile_size));

        loop var y; 100
        {
            loop var x; 100
            {
                var box box2;
                box.min = floor({ x, y } vec2 * tile_size) + tile_offset;
                box.max = ceil(box.min + tile_size);
                var colors = [
                    [ 100, 25, 25, 255 ] rgba8,
                    [ 25, 25, 100, 255 ] rgba8,
                ] rgba8[];

                var color = colors[(x + y) bit_and 1];
                draw_box(ui, 1, color, box);
            }        
        }

        loop var i u32; client.player_count
        {
            var player = client.players[i];
            var player_position = player.position;

            var box box2;
            box.min = floor({ player_position.x - 0.5, player_position.y } vec2 * tile_size) + tile_offset;
            box.max = ceil(box.min + tile_size);        
            var color = [ 128, 128, 255, 255 ] rgba8;
            draw_box(ui, 2, color, box);

            if player.chat_message_timeout > 0
            {
                var aligned_state = draw_aligned_begin(ui, get_point(box, [ 0.5, 1 ] vec2) + [ 0, tile_size * 0.2 ] vec2, [ 0.5, 0 ] vec2);

                var t = pow(player.chat_message_timeout, 0.25);
                var alpha = (255 * t) cast(u8);

                var cursor = cursor_below_position(font.info, 0, 0);
                var text_color = [ 10, 10, 10, alpha ] rgba8;
                print(ui, 11, text_color, font, cursor ref, from_string255(player.chat_message));

                var box = draw_aligned_end(ui, aligned_state);                
                var chat_color = [ 245, 245, 245, alpha ] rgba8;
                draw_rounded_box(ui, 10, chat_color, grow(box, 8), 6);
            }
            
            if (i is 0) and game.is_chatting
            {
                var aligned_state = draw_aligned_begin(ui, get_point(box, [ 0.5, 0 ] vec2) - [ 0, tile_size * 0.2 ] vec2, [ 0.5, 1 ] vec2);

                // var t = pow(player.chat_message_timeout, 0.25);
                var alpha = 255 cast(u8);

                var text = from_string255(client.chat_message);

                var cursor = cursor_below_position(font.info, 0, 0);
                var text_color = [ 10, 10, 10, alpha ] rgba8;

                def caret_width = 3;

                var text_iterator = make_iterator(font.info, text, cursor);
                print(ui, 11, text_color, font, cursor ref, text);
                ui.current_box = grow(ui.current_box, [ caret_width * 2, 0 ] vec2);

                {                    
                    text_iterator.text.count = client.chat_message_edit.edit_offset + 1;                      
                    
                    var previous_x = text_iterator.cursor.x;
                    
                    if text.count
                    {
                        while text_iterator.text.count
                        {
                            advance(text_iterator ref);
                            previous_x = text_iterator.cursor.x;
                        }               
                    }

                    var box box2;                     
                    box.min = [ previous_x, text_iterator.cursor.y - font.info.bottom_margin ] vec2;
                    box.max = box.min + [ 0, font.info.max_glyph_height ] vec2;
                    draw_box(ui, 12, [ 20, 255, 20, 196 ] rgba8, grow(box, caret_width));
                }
                
                var box = draw_aligned_end(ui, aligned_state);                
                var chat_color = [ 245, 245, 245, alpha ] rgba8;
                draw_rounded_box(ui, 10, chat_color, grow(box, 8), 6);
            }
        }
    }

    if platform.do_quit
    {
    }

    return true;
}

func edit255_begin(text_edit editable_text ref, text string255 ref)
{
    text_edit.buffer.count = text.base.count;
    text_edit.buffer.base = text.base.base;            
}

func edit255_end(text_edit editable_text, text string255 ref)
{
    text.count = text_edit.used_count cast(u8);
}

enum render_texture_slot render_texture_slot_base
{
}