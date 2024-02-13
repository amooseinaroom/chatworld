
import network;

def game_title = "chat world";

struct program_state
{
    expand default default_program_state;
    
    network platform_network;

    is_host b8;

    server game_server;
    client game_client;

    menu menu_state;
    color_edit color_edit_tag;

    user_sprite game_user_sprite;
    user_sprite_texture gl_texture;
    has_user_sprite b8;
}

enum color_edit_tag
{
    none;
    name_color;
    body_color;
}

func skip_space(iterator string ref)
{
    try_skip_set(iterator, " \t\n\r");
}

func game_init program_init_type
{
    state.letterbox_width_over_heigth = 16.0 / 9.0;    

    platform_network_init(state.network ref);

    var client = state.client ref;
    client.server_address.port = default_server_port;
    client.server_address.ip[0] = 127;
    client.server_address.ip[3] = 1;

    init(client.game ref);
    init(state.server.game ref);

    // client.server_address.ip.u8_values = [ 77, 64, 253, 6 ] u8[];
    // client.server_address.port = 50881;    
    
    client.body_color.hue = random_f32_zero_to_one(state.random ref);
    client.body_color.saturation = 1.0;
    client.body_color.value      = 1.0;
    client.body_color.alpha      = 1.0;
    evaluate(client.body_color ref);

    client.name_color.hue = random_f32_zero_to_one(state.random ref);
    client.name_color.saturation = 1.0;
    client.name_color.value      = 1.0;
    client.name_color.alpha      = 1.0;
    evaluate(client.name_color ref);

    {
        var result = try_platform_read_entire_file(platform, state.temporary_memory ref, client_save_state_path);
        if result.ok and (result.data.count is type_byte_count(game_client_save_state))
        {
            var save_state = result.data.base cast(game_client_save_state ref) deref;
            client.name_color = save_state.name_color;
            client.body_color = save_state.body_color;
            client.user_name = save_state.user_name;
            client.user_name_edit.used_count = client.user_name.count;
            client.user_name_edit.edit_offset = client.user_name_edit.used_count;
            client.user_password = save_state.user_password;
            client.user_password_edit.used_count = client.user_password.count;
            client.user_password_edit.edit_offset = client.user_password_edit.used_count;
        }
    }

    if true
    {
        var tmemory = state.temporary_memory ref;
        var source = platform_read_entire_file(platform, tmemory, "server.txt");

        var dns string;
        var server_ip = client.server_address.ip;
        var port      = client.server_address.port;

        var it = source;
        skip_space(it ref);
        while it.count
        {
            if not try_skip(it ref, "server")
                assert(false);

            skip_space(it ref);

            if try_skip(it ref, "ip")
            {
                skip_space(it ref);

                loop var i u32; 4
                {
                    var value u32;
                    if not try_parse_u32(value ref, it ref) or (value > 255)
                        assert(false);
                    
                    server_ip[i] = value cast(u8);

                    if (i < 3) and not try_skip(it ref, ".")
                        assert(false);                                        
                }
                
                skip_space(it ref);
            }
            else if  try_skip(it ref, "dns")
            {
                dns = try_skip_until_set(it ref, " \t\n\r");
                assert(dns.count);
            }
            else
                assert(false);            

            if not try_parse_u32(port ref, it ref) or (port > 65535)
                assert(false);                     

            skip_space(it ref);
            break;
        }
        
        client.server_address.port = port cast(u16);

        if dns.count
        {
            var records DNS_RECORD ref;
            var name_buffer u8[512];
            var status = DnsQuery_A(as_cstring(name_buffer, dns), DNS_TYPE_A, DNS_QUERY_STANDARD, null, records cast(u8 ref) ref, null);
            var iterator = records;
            if iterator
            {
                client.server_address.ip = iterator.Data.A.IpAddress ref cast(platform_network_ip ref) deref;
            }

            DnsRecordListFree(records, 0);
        }
        else
        {
            client.server_address.ip = server_ip;
        }
    }
}

func game_update program_update_type
{
    var memory  = state.memory ref;
    var tmemory = state.temporary_memory ref;
    var ui      = state.ui ref;    
    var client  = state.client ref;
    var menu = state.menu ref;
    menu.ui = ui;
    menu.characters = { platform.character_count, platform.character_buffer.base } platform_character[];

    var tiles_per_width = 20;
    var tiles_per_height = tiles_per_width / state.letterbox_width_over_heigth;
    var tile_size = ui.viewport_size.width / tiles_per_width;
    
    // reload and cycle font

    // for testing purposes we want to view different fonts
    def font_paths =
    [
        "assets/fonts/bodo-amat/Bodo Amat.ttf",
        "assets/fonts/dinomouse/Dinomouse-Regular.otf",
        "assets/fonts/new-era-casual/New Era Casual Regular.ttf",
        "assets/fonts/stanberry/Stanberry.ttf",
        "assets/fonts/super-kid/Super Kid.ttf"
    ] string[];
    
    var global font_index u32 = 3; // stanberry
    var font_changed = false;
    if false // disable font cycling
    {
        if platform_key_was_pressed(platform, "T"[0])
        {
            font_index = (font_index + 1) mod font_paths.count;
            font_changed = true;
        }
    }

    {
        var font_height = ceil(tile_size * 0.25) cast(s32);
        if font_changed or (state.font.info.pixel_height is_not font_height)
        {
            temporary_end(memory, state.memory_reload_used_byte_count);

            if state.font.atlas.handle
                glDeleteTextures(1, state.font.atlas.handle ref);

            state.font = {} ui_font;

            init(state.font ref,  platform, memory, tmemory, font_paths[font_index], font_height, 1024);
        }
    }    
    
    var font = state.font;

    var cursor = cursor_below_position(font.info, 20, ui.viewport_size.height - 20);
    print(ui, 10, font, cursor ref,  "fps: %\nfont: %\n", 1.0 / platform.delta_seconds, font_paths[font_index]);

    var global load_sprite = true;

    if load_sprite
    {
        load_sprite = false;

        var sprite_path string;
        var iterator = platform_file_search_init(platform, "customization/");
        while platform_file_search_next(platform, iterator ref)
        {
            if iterator.found_file.is_directory
                continue;

            var path = iterator.found_file.relative_path;
            sprite_path = path;
            break;
        }

        if sprite_path.count
        {
            var result = try_platform_read_entire_file(platform, tmemory, sprite_path);
            if result.ok
            {
                var width s32;
                var height s32;
                var irgnored s32;
                stbi_set_flip_vertically_on_load(1);
                var pixels = stbi_load_from_memory(result.data.base, result.data.count cast(s32), width ref, height ref, irgnored ref, 4);
                var colors = { (width * height) cast(usize) * type_byte_count(rgba8), pixels } u8[];
                if (width is 256) and (height is 128)
                {
                    copy_bytes(state.user_sprite.base, colors.base, state.user_sprite.count);
                    state.has_user_sprite = true;
                    state.user_sprite_texture = gl_create_texture_2d(width,height, false, colors);
                }
            }
        }
    }

    if client.state is client_state.disconnected
    {
        draw_box(ui, -1000, [ 20, 20, 255, 255 ] rgba8, ui.scissor_box);

        var box = draw_box_begin(ui);
        var cursor = cursor_below_position(font.info, ui.viewport_size.width * 0.5, ui.viewport_size.height * 0.75);

        print(ui, menu_layer.text, font, cursor ref, "user: ");
        edit255_begin(client.user_name_edit ref, client.user_name ref);
        menu_text_edit(menu, location_id(0), font, cursor ref, client.user_name_edit ref);
        edit255_end(client.user_name_edit, client.user_name ref);

        print(ui, menu_layer.text, font, cursor ref, "password: ");
        edit255_begin(client.user_password_edit ref, client.user_password ref);
        menu_text_edit(menu, location_id(0), font, cursor ref, client.user_password_edit ref);
        edit255_end(client.user_password_edit, client.user_password ref);

        if menu_button(menu, location_id(0), font, cursor ref, "Host")
        {            
            init(state.server ref, platform, state.network ref, client.server_address.port, tmemory);
            init(client, state.network ref, client.server_address);
            state.is_host = true;
        }

        if menu_button(menu, location_id(0), font, cursor ref, "Connect")
        {
            init(client, state.network ref, client.server_address);
        }

        if menu_button(menu, location_id(0), font, cursor ref, "Name Color")
        {           
            state.color_edit = color_edit_tag.name_color;
        }

        if menu_button(menu, location_id(0), font, cursor ref, "Body Color")
        {           
            state.color_edit = color_edit_tag.body_color;
        }        

        // display in-game character
        {            
            var box box2;
            box.min.x = cursor.position.x;
            box.max.y = cursor.position.y;
            box.max.x = ceil(box.min.x + (tile_size * 1));
            box.min.y = floor(box.max.y - (tile_size * 1));            
            var color = to_rgba8(client.body_color.color);

            // if false and state.has_user_sprite
            if state.has_user_sprite
            {
                var texture_box box2;
                texture_box.min = [ 0, 0 ] vec2;
                texture_box.max = [ 128, 128 ] vec2;

                // tile_size = box_size * texture_scale
                var alignment = {} vec2;
                var box_size = get_size(box);
                // texture_scale = tile_size / box_size

                var texture_scale = v2(box_size.width / 128);
                draw_texture_box(ui, state.user_sprite_texture, box.min, texture_box, alignment, texture_scale);
            }
            else
                draw_box(ui, 2, color, box);

            print_aligned(ui, 3, to_rgba8(client.name_color.color), font, get_point(box, [ 0.5, 1 ] vec2) + [ 0, tile_size * 0.1 ] vec2, [ 0.5, 0 ] vec2, "%", from_string255(client.user_name));

            cursor.position.y = box.min.y cast(s32);
            advance_line(font.info, cursor ref);
        }

        if state.color_edit is_not color_edit_tag.none
        {
            var box box2;
            box.min.x = cursor.position.x;
            box.max.y = cursor.position.y;
            box.max.x = ceil(box.min.x + (tile_size * 2));
            box.min.y = floor(box.max.y - (tile_size * 2));

            var colors = 
            [
                client.name_color ref,
                client.body_color ref,
            ] color_hsva ref[];

            color_wheel(ui, 0, location_id(0), box, colors[state.color_edit - 1], false);
        }
    }
    else
    {
        if state.is_host
        {
            tick(platform, state.server ref, state.network ref, platform.delta_seconds);
            update(state.server.game ref, platform.delta_seconds);
        }
    
        tick(client, state.network ref, platform.delta_seconds);                

        if (client.state is client_state.online)
        {
            var game = client.game ref;

            // update(platform, state);        

            var player = client.players[0] ref;

            client.frame_input = {} network_message_user_input;        

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

                var do_attack = platform_key_is_active(platform, "J"[0]);

                movement = normalize_or_zero(movement);

                var entity = get(game, player.entity_id);

                var movement_speed = 6;
                // player.position += movement * (movement_speed * platform.delta_seconds);

                client.frame_input.movement = movement * movement_speed;
                client.frame_input.delta_seconds = platform.delta_seconds;
                client.frame_input.do_attack = do_attack;

                var tile_frame = 4;
                if entity.position.x > (game.camera_position.x + (tiles_per_width * 0.5) - tile_frame)
                    game.camera_position.x = entity.position.x - (tiles_per_width * 0.5) + tile_frame;
                else if entity.position.x < (game.camera_position.x - (tiles_per_width * 0.5) + tile_frame)
                    game.camera_position.x = entity.position.x + (tiles_per_width * 0.5) - tile_frame;

                if entity.position.y > (game.camera_position.y + (tiles_per_height * 0.5) - tile_frame)
                    game.camera_position.y = entity.position.y - (tiles_per_height * 0.5) + tile_frame;
                else if entity.position.y < (game.camera_position.y - (tiles_per_height * 0.5) + tile_frame - 1)
                    game.camera_position.y = entity.position.y + (tiles_per_height * 0.5) - tile_frame + 1;
            }                    

            // update(game, platform.delta_seconds);

            

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
                var entity = get(game, player.entity_id);
                var player_position = entity.position;

                var box box2;
                box.min = floor({ player_position.x - 0.5, player_position.y } vec2 * tile_size) + tile_offset;
                box.max = ceil(box.min + tile_size);                
                draw_box(ui, 2, player.body_color, box);

                print_aligned(ui, 10, player.name_color, font, get_point(box, [ 0.5, 1 ] vec2) + [ 0, tile_size * 0.1 ] vec2, [ 0.5, 0 ] vec2, "%", from_string255(player.name));

                if player.chat_message_timeout > 0
                {
                    var aligned_state = draw_aligned_begin(ui, get_point(box, [ 0.5, 1 ] vec2) + [ 0, tile_size * 0.5 ] vec2, [ 0.5, 0 ] vec2);

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

                    var left = { client.chat_message_edit.edit_offset, text.base } string;
                    var right = { text.count - left.count, left.base + left.count } string;

                    print(ui, 11, text_color, font, cursor ref, left);
                    
                    {
                        var box box2;
                        box.min = [ cursor.x, cursor.y - font.info.bottom_margin ] vec2;
                        box.max = box.min + [ 0, font.info.max_glyph_height ] vec2;
                        draw_box(ui, 12, [ 20, 255, 20, 196 ] rgba8, grow(box, caret_width));
                    }

                    print(ui, 11, text_color, font, cursor ref, right);

                    ui.current_box = grow(ui.current_box, [ caret_width * 2, 0 ] vec2);

                    if false
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

            loop var i u32; game.entity.count
            {
                if not game.active[i]
                continue;
            
                var entity = game.entity[i] ref;

                switch entity.tag
                case game_entity_tag.fireball
                {
                    var box box2;
                    box.min = floor(({ entity.position.x, entity.position.y } vec2 - entity.collider.radius) * tile_size) + tile_offset;
                    box.max = ceil(box.min + (entity.collider.radius * 2 * tile_size));
                    var color = [ 255, 128, 25, 255 ] rgba8;
                    draw_box(ui, 2, color, box);
                }            
            }
        }
    }

    if platform.do_quit
    {
        var save_state game_client_save_state;
        save_state.name_color = client.name_color;
        save_state.body_color = client.body_color;
        save_state.user_name = client.user_name;
        save_state.user_password = client.user_password;

        platform_write_entire_file(platform, client_save_state_path, value_to_u8_array(save_state));
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