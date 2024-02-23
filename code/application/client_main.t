
import network;

override def use_render_system = true;

def game_title = "chatworld client";

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
    user_sprite_index_plus_one u32;

    sprite_view_direction          game_sprite_view_direction;
    sprite_view_diretcion_timeout f32;
}

enum color_edit_tag
{
    none;
    name_color;
    body_color;
}

func game_init program_init_type
{
    state.letterbox_width_over_heigth = 16.0 / 9.0;

    platform_network_init(state.network ref);

    var client = state.client ref;
    client.server_address.port = default_server_port;
    client.server_address.ip[0] = 127;
    client.server_address.ip[3] = 1;

    update_game_version(platform, state.temporary_memory ref);

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

    client.server_address = load_server_address(platform, state.network ref, state.temporary_memory ref, client.server_address);

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

    def enable_font_cycling = false;
    if enable_font_cycling
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
    print(ui, 10, font, cursor ref, "version: %, fps: %, latency: %ms\n", game_version, 1.0 / platform.delta_seconds, client.latency_milliseconds);

    if enable_font_cycling
        print(ui, 10, font, cursor ref, "font: % [%]\n", font_paths[font_index], font_index);

    if client.state is client_state.disconnected
    {
        if client.reject_reason is_not 0
            print(ui, 10, font, cursor ref, "Server rejected connection: %\n", client.reject_reason);
        else if client.reconnect_count
            print(ui, 10, font, cursor ref, "Server is not responding, it may be offline\n");

        draw_box(ui, -1000, [ 20, 20, 255, 255 ] rgba8, ui.scissor_box);

        var box = draw_box_begin(ui);
        var cursor = cursor_below_position(font.info, ui.viewport_size.width * 0.5, ui.viewport_size.height * 0.75);

        print(ui, menu_layer.text, font, cursor ref, "user: ");
        edit_string_begin(client.user_name_edit ref, client.user_name ref);
        menu_text_edit(menu, location_id(0), font, cursor ref, client.user_name_edit ref);
        edit_string_end(client.user_name_edit, client.user_name ref);

        print(ui, menu_layer.text, font, cursor ref, "password: ");
        edit_string_begin(client.user_password_edit ref, client.user_password ref);
        menu_text_edit(menu, location_id(0), font, cursor ref, client.user_password_edit ref);
        edit_string_end(client.user_password_edit, client.user_password ref);

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

        var load_sprite = false;

        if menu_button(menu, location_id(0), font, cursor ref, "previous sprite")
        {
            state.user_sprite_index_plus_one -= 1;
            load_sprite = true;
        }

        if menu_button(menu, location_id(0), font, cursor ref, "next sprite")
        {
            state.user_sprite_index_plus_one += 1;
            load_sprite = true;
        }

        label load_sprite_label
        {
            if load_sprite
            {
                var sprite_path string;
                var iterator = platform_file_search_init(platform, "customization/");
                var index u32;
                while platform_file_search_next(platform, iterator ref)
                {
                    if iterator.found_file.is_directory
                        continue;

                    var path = iterator.found_file.relative_path;

                    var split = split_path(path);
                    if split.extension is_not "png" or not starts_with(split.name, "character_")
                        continue;

                    index += 1;

                    if (index is state.user_sprite_index_plus_one) or (state.user_sprite_index_plus_one is u32_invalid_index)
                        sprite_path = path;

                    if (index is state.user_sprite_index_plus_one)
                        break;
                }

                if state.user_sprite_index_plus_one is u32_invalid_index
                    state.user_sprite_index_plus_one = index;
                else if state.user_sprite_index_plus_one > index
                    state.user_sprite_index_plus_one = 0;

                if state.user_sprite_index_plus_one is 0
                    break load_sprite_label;

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
                            state.user_sprite_texture = gl_create_texture_2d(width,height, false, colors);
                        }
                    }
                }
            }
        }

        state.sprite_view_diretcion_timeout -= platform.delta_seconds * 2;
        if state.sprite_view_diretcion_timeout <= 0
        {
            state.sprite_view_diretcion_timeout += 1.0;

            state.sprite_view_direction = (state.sprite_view_direction + 1) mod game_sprite_view_direction.count;
        }

        // display in-game character
        {
            var position = v2(cursor.position) - [ 0,  tile_size ] vec2;
            var sprite_texture_box box2;
            sprite_texture_box.min = [ 0, 0 ] vec2;
            sprite_texture_box.max = [ 128, 128 ] vec2;

            var box = draw_player(ui, position, tile_size, to_rgba8(client.body_color.color), state.user_sprite_index_plus_one is_not 0, state.user_sprite_texture, sprite_texture_box, state.sprite_view_direction);
            draw_player_name(ui, font, position, tile_size, to_string(client.user_name), to_rgba8(client.name_color.color));

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
            tick(platform, state.server ref, state.network ref, platform.delta_seconds);

        tick(client, state.network ref, platform.delta_seconds);

        if client.state is client_state.connecting
        {
            var text_color = [ 255, 255, 255, (sin(client.reconnect_timeout * 2 * pi32) * 0.5 + 0.5 * 255) cast(u8) ] rgba8;
            print(ui, 10, text_color, font, cursor ref, "Connecting to Server %.%.%.%:%", client.server_address.ip[0], client.server_address.ip[1], client.server_address.ip[2], client.server_address.ip[3], client.server_address.port);
        }

        if (client.state is client_state.online)
        {
            var game = client.game ref;

            if client.is_admin
                print(ui, 10, font, cursor ref, "Admin User");

            // update(platform, state);

            var player = client.players[0] ref;

            if game.is_chatting
            {
                client.chat_message_edit.buffer.count = client.chat_message.base.count;
                client.chat_message_edit.buffer.base  = client.chat_message.base.base;

                edit_string_begin(client.chat_message_edit ref, client.chat_message ref);

                edit_text(client.chat_message_edit ref, menu.characters ref);

                edit_string_end(client.chat_message_edit, client.chat_message ref);

                if not platform_key_is_active(platform, platform_key.control) and not platform_key_is_active(platform, platform_key.alt) and not platform_key_is_active(platform, platform_key.shift) and platform_key_was_pressed(platform, platform_key.enter)
                {
                    client.send_chat_message = true;
                    client.chat_message = client.chat_message;
                    game.is_chatting = false;
                }
            }
            else
            {
                if platform_key_is_active(platform, platform_key.alt) and platform_key_was_pressed(platform, platform_key.f0 + 3)
                    client.do_shutdown_server = true;

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
                movement *= (player_movement_speed * platform.delta_seconds);

                var entity = get(game, player.entity_id);

                client.frame_input.movement += movement;
                client.frame_input.do_attack or= do_attack;

                client.player_predicted_position += movement;

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
                    draw_box(ui, game_render_layer.ground, color, box);
                }
            }


            loop var i u32; client.player_count
            {
                var player = client.players[i];
                var entity = get(game, player.entity_id);

                var position = entity.position;
                position = floor({ position.x - 0.5, position.y } vec2 * tile_size) + tile_offset;

                var sprite_texture_box box2;
                sprite_texture_box.min = [ 0, 0 ] vec2;
                sprite_texture_box.max = [ 128, 128 ] vec2;

                var box = draw_player(ui, position, tile_size, player.body_color, state.user_sprite_index_plus_one is_not 0, state.user_sprite_texture, sprite_texture_box, state.sprite_view_direction);
                draw_player_name(ui, font, position, tile_size, to_string(player.name), player.name_color);

                if player.chat_message_timeout > 0
                {
                    var aligned_state = draw_aligned_begin(ui, get_point(box, [ 0.5, 1 ] vec2) + [ 0, tile_size * 0.5 ] vec2, [ 0.5, 0 ] vec2);

                    var t = pow(player.chat_message_timeout, 0.25);
                    var alpha = (255 * t) cast(u8);

                    var cursor = cursor_below_position(font.info, 0, 0);
                    var text_color = [ 10, 10, 10, alpha ] rgba8;
                    print(ui, 11, text_color, font, cursor ref, to_string(player.chat_message));

                    var box = draw_aligned_end(ui, aligned_state);
                    var chat_color = [ 245, 245, 245, alpha ] rgba8;
                    draw_rounded_box(ui, 10, chat_color, grow(box, 8), 6);
                }

                if (i is 0) and game.is_chatting
                {
                    var aligned_state = draw_aligned_begin(ui, get_point(box, [ 0.5, 0 ] vec2) - [ 0, tile_size * 0.2 ] vec2, [ 0.5, 1 ] vec2);

                    // var t = pow(player.chat_message_timeout, 0.25);
                    var alpha = 255 cast(u8);

                    var text = to_string(client.chat_message);

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

            // local player prediction
            if client.player_count
            {
                var sprite_texture_box box2;
                sprite_texture_box.min = [ 0, 0 ] vec2;
                sprite_texture_box.max = [ 128, 128 ] vec2;

                var player = client.players[0];
                var position = client.player_predicted_position;
                position = floor({ position.x - 0.5, position.y } vec2 * tile_size) + tile_offset;

                var body_color = player.body_color;
                body_color.r = 255 - body_color.r;
                body_color.g = 255 - body_color.g;
                body_color.b = 255 - body_color.b;
                body_color.alpha = 128;

                var name_color = player.name_color;
                name_color.alpha = 128;

                var box = draw_player(ui, position, tile_size, body_color, state.user_sprite_index_plus_one is_not 0, state.user_sprite_texture, sprite_texture_box, state.sprite_view_direction);
                draw_player_name(ui, font, position, tile_size, to_string(player.name), name_color);
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


enum render_texture_slot render_texture_slot_base
{
}

def player_draw_alignment = [ 0.5, 8.0 / 128.0 ] vec2;

func get_player_box(position vec2, tile_size f32) (box box2)
{
    var alignment = player_draw_alignment;

    var box box2;
    var box_size = v2(ceil(tile_size));
    box.min = floor(position - scale(box_size, alignment));
    box.max = box.min + box_size;
    return box;
}

enum game_render_layer
{
    ground;
    entity;
    overlay;
}

func draw_player_name(ui ui_system ref, font ui_font, position vec2, tile_size f32, name string, name_color rgba8)
{
    var box = get_player_box(position, tile_size);
    print_aligned(ui, game_render_layer.overlay, name_color, font, get_point(box, [ 0.5, 1 ] vec2) + [ 0, tile_size * 0.1 ] vec2, [ 0.5, 0 ] vec2, "%", name);
}

func draw_player(ui ui_system ref, position vec2, tile_size f32, body_color rgba8, use_sprite b8, sprite_texture gl_texture, sprite_texture_box box2, view_direction game_sprite_view_direction) (box box2)
{
    var box = get_player_box(position, tile_size);

    // if false and state.has_user_sprite
    if use_sprite
    {
        var texture_scale = v2((box.max.x - box.min.x) / 128);

        // use back
        // assuming spirte front and back are stored together
        if view_direction >= game_sprite_view_direction.back_right
        {
            sprite_texture_box.min.x += 128;
            sprite_texture_box.max.x += 128;
        }

        // flip x if looking right
        var flip_x = (((view_direction + game_sprite_view_direction.count - 1) mod game_sprite_view_direction.count) < 2) is_not 0;
        var alignment = player_draw_alignment;
        draw_texture_box(ui, game_render_layer.entity, 1.0, rgba8_white, sprite_texture, position, sprite_texture_box, alignment, texture_scale, flip_x);
    }
    else
    {
        var player_box box2;
        var size = ceil(tile_size * 96 / 128);
        player_box.min.y = box.min.y + floor(tile_size * 8 / 128);
        player_box.max.y = player_box.min.y + size;
        player_box.min.x = floor((box.max.x + box.min.x) * 0.5 - (size * 0.5));
        player_box.max.x = player_box.min.x + size;
        draw_box(ui, game_render_layer.entity, body_color, player_box);
    }

    return box;
}