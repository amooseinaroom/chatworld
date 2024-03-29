
import network;
import render_2d;

override def use_render_system = true;
def debug_player_server_position = false;

def game_title = "chatworld client";

// override def network_print_max_level = network_print_level.count;
// override def network_print_max_level = network_print_level.info;

struct program_state
{
    expand default default_program_state;

    render_2d render_2d_api;
    dynamic_font render_2d_font;

    network platform_network;

    custom_sprite_paths string[];

    error_message_buffer u8[4096];
    error_messages string_builder;

    key_bindings game_key_bindings;
    key_bindings_write_timestamp u64;
    key_bindings_are_init        b8;

    input game_input;

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

struct game_key_bindings
{
    up    u8;
    down  u8;
    left  u8;
    right u8;

    interact u8;
    attack   u8;
    magic    u8;

    chat         u8;
    toggle_shout u8;

    accept u8;
    cancel u8;
}

struct game_input
{
    up    platform_button;
    down  platform_button;
    left  platform_button;
    right platform_button;

    interact platform_button;
    attack   platform_button;
    magic    platform_button;

    chat         platform_button;
    toggle_shout platform_button;

    accept platform_button;
    cancel platform_button;
}

func update(platform platform_api ref, input game_input ref, key_bindings game_key_bindings)
{
    var buttons = input cast(platform_button ref);
    var keys    = key_bindings ref cast(u8 ref);
    var button_count = (type_byte_count(game_input) / type_byte_count(platform_button)) cast(u32);
    var key_count    = (type_byte_count(game_key_bindings) / type_byte_count(u8)) cast(u32);
    assert(button_count is key_count);

    loop var i u32; button_count
        platform_button_poll(buttons + i, platform_key_is_active(platform, (keys + i) deref));
}

def game_key_bindings_path = "key_bindings.txt";

func load_key_bindings(platform platform_api ref, tmemory memory_arena ref) (key_bindings game_key_bindings, error_message string)
{
    var result game_key_bindings;
    result.up       = "W"[0];
    result.down     = "S"[0];
    result.left     = "A"[0];
    result.right    = "D"[0];
    result.interact = "J"[0];
    result.attack   = "K"[0];
    result.magic    = "L"[0];
    result.chat     = platform_key.enter;
    result.toggle_shout = "S"[0];
    result.accept   = "J"[0];
    result.cancel   = "K"[0];

    var result_base = result ref cast(u8 ref);
    var type = get_type_info(game_key_bindings);
    var used_field_mask u64;

    var text string = try_platform_read_entire_file(platform, tmemory, game_key_bindings_path).data;

    var iterator = text;
    skip_space(iterator ref);

    while iterator.count
    {
        // skip comment
        if try_skip(iterator ref, "#")
        {
            try_skip_until_set(iterator ref, "\n");
            skip_space(iterator ref);
            continue;
        }

        var name = skip_name(iterator ref);
        if not name.count
        {
            var error_message = allocate_text(tmemory, "Error: %,% expected field name.", game_key_bindings_path, get_line_number(iterator, text));
            return result, error_message;
        }
        skip_space(iterator ref);

        var field u8 ref;
        {
            var info = get_field_byte_offset(type, name);
            if not info.ok
            {
                var error_message string;

                write(tmemory, error_message ref, "Error: %,% there is no field '%'.\n", game_key_bindings_path, get_line_number(iterator, text), name);
                write(tmemory, error_message ref, "The Following fields are available:\n");

                var compound_type = type.compound_type deref;
                loop var field_index usize; compound_type.fields.count
                {
                    write(tmemory, error_message ref, "  - Field: %\n", compound_type.fields[field_index].name);
                }

                return result, error_message;
            }

            if used_field_mask bit_and bit64(info.field_index)
            {
                var error_message = allocate_text(tmemory, "Error: %,% field % is set multiple times.", game_key_bindings_path, get_line_number(iterator, text), name);
                return result, error_message;
            }

            used_field_mask bit_or= bit64(info.field_index);
            field = (result_base + info.byte_offset) cast(u8 ref);
        }

        if not try_skip(iterator ref, ":")
        {
            var error_message = allocate_text(tmemory, "Error: %,% expected ':' after name %.", game_key_bindings_path, get_line_number(iterator, text), name);
            return result, error_message;
        }
        skip_space(iterator ref);

        var token = try_skip_until_set(iterator ref, " \t\n\r");
        if not token.count
        {
            var error_message = allocate_text(tmemory, "Error: %,% expected field value after ':'.", game_key_bindings_path, get_line_number(iterator, text));
            return result, error_message;
        }
        skip_space(iterator ref);

        var found_value = false;
        var value u8;

        // check if it is a special key
        {
            var enumeration_type = get_type_info(platform_key).enumeration_type deref;
            loop var item_index usize; enumeration_type.items.count
            {
                if enumeration_type.items[item_index].name is token
                {
                    value = enumeration_type.items[item_index].value cast(u8);
                    found_value = true;
                    break;
                }
            }
        }

        if not found_value
        {
            if token.count > 1
            {
                var error_message string;

                write(tmemory, error_message ref, "Error: %,% unknown key name '%' for field %.\n", game_key_bindings_path, get_line_number(iterator, text), token, name);
                write(tmemory, error_message ref, "Following key names are available:\n");

                write(tmemory, error_message ref, "  - A Single symbol to indicate a keyboard key (e.g. W)\n");

                var enumeration_type = get_type_info(platform_key).enumeration_type deref;
                loop var item_index usize; enumeration_type.items.count
                {
                    write(tmemory, error_message ref, "  - Keyboard key: %\n", enumeration_type.items[item_index].name);
                }

                return result, error_message;
            }

            value = token[0];
        }

        field deref = value;
    }

    return result, "OK: keybindings.txt successfully loaded.";
}

func save_key_bindings(platform platform_api ref, key_bindings game_key_bindings, tmemory memory_arena ref)
{
    var temp_frame = temporary_begin(tmemory);

    var output string;

    write(tmemory, output ref, "# set key bindings like so:\n");

    write(tmemory, output ref, "# name: value\n\n");

    write(tmemory, output ref, "# toggle_shout is always combinded with ctrl and only avaible while chatting\n");
    write(tmemory, output ref, "# while chatting, you send and confirm the message with enter, while shift+enter goes to the next line\n");

    write(tmemory, output ref, "\n");

    var compound_type = get_type_info(game_key_bindings).compound_type deref;
    var enumeration_type = get_type_info(platform_key).enumeration_type deref;

    var base = key_bindings ref cast(u8 ref);

    loop var field_index usize; compound_type.fields.count
    {
        write(tmemory, output ref, "%: ", compound_type.fields[field_index].name);

        var value = base deref;
        base += 1;

        var found = false;
        loop var item_index usize; enumeration_type.items.count
        {
            if enumeration_type.items[item_index].value is value
            {
                write(tmemory, output ref, "%\n", enumeration_type.items[item_index].name);
                found = true;
                break;
            }
        }

        if not found
        {
            var token = { 1, value ref } string;
            write(tmemory, output ref, "%\n", token);
        }
    }

    platform_write_entire_file(platform, game_key_bindings_path, output);

    temporary_end(tmemory, temp_frame);
}

func game_init program_init_type
{
    var tmemory = state.temporary_memory ref;

    // util to get linear rgbs from online color srgb values
    multiline_comment
    {
        print("\n");
        print("def menu_color_edit = % rgba8;\n", to_rgba8(srgb_to_linear(to_vec4(menu_color_edit))).values);
        print("def menu_color_idle = % rgba8;\n", to_rgba8(srgb_to_linear(to_vec4(menu_color_idle))).values);
        print("def menu_color_background = % rgba8;\n", to_rgba8(srgb_to_linear(to_vec4(menu_color_background))).values);
        print("def menu_color_hot = % rgba8;\n", to_rgba8(srgb_to_linear(to_vec4(menu_color_hot))).values);
    }

    // loop var i; lang_global_variables.count
    // {
    //     var variable = lang_global_variables[i];
    //     print("global %\n", variable.name);
    // }

    init(state.render_2d ref, state.gl ref, tmemory);

    state.letterbox_width_over_heigth = 16.0 / 9.0;

    platform_network_init(state.network ref);

    {
        var iterator = platform_file_search_init(platform, "customization/");

        var sprite_relative_paths asset_path[];

        while platform_file_search_next(platform, iterator ref)
        {
            if iterator.found_file.is_directory
                continue;

            var split = split_path(iterator.found_file.relative_path);

            if split.extension is_not "png"
                continue;

            if not try_skip(split.name ref, "character_front_")
                continue;

            reallocate_array(tmemory, sprite_relative_paths ref, sprite_relative_paths.count + 1);
            sprite_relative_paths[sprite_relative_paths.count - 1].count = split.name.count cast(u32);
             iterator.found_file.relative_path.count cast(u32);
            copy_bytes(sprite_relative_paths[sprite_relative_paths.count - 1].base.base, split.name.base, split.name.count);
        }

        reallocate_array(state.memory ref, state.custom_sprite_paths ref, sprite_relative_paths.count * 2);
        var all_paths_text string;
        loop var i; sprite_relative_paths.count
        {
            var path = { sprite_relative_paths[i].count, sprite_relative_paths[i].base.base } string;
            state.custom_sprite_paths[i * 2   ] = write(state.memory ref, all_paths_text ref, "customization/character_front_%.png", path);
            state.custom_sprite_paths[i * 2 + 1] = write(state.memory ref, all_paths_text ref, "customization/character_back_%.png", path);
        }
    }

    state.error_messages = string_builder_from_buffer(state.error_message_buffer);

    var client = state.client ref;
    client.server_address.port = default_server_port;
    client.server_address.tag = platform_network_address_tag.ip_v4;
    client.server_address.ip_v4[0] = 127;
    client.server_address.ip_v4[3] = 1;

    update_game_version(platform, tmemory);

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

    client.server_address = load_server_address(platform, state.network ref, tmemory, client.server_address);

    if client.server_address.tag is platform_network_address_tag.ip_v4
        network_print("Client: loaded server ipv4: %.%.%.%, port: %\n",
            client.server_address.ip_v4[0],
            client.server_address.ip_v4[1],
            client.server_address.ip_v4[2],
            client.server_address.ip_v4[3],
            client.server_address.port);

    else
        network_print("Client: loaded server ipv6: %:%:%:%:%:%:%:%, port: %\n",
            format_hex(client.server_address.ip_v6.u16_values[0], "a"[0], 4),
            format_hex(client.server_address.ip_v6.u16_values[1], "a"[0], 4),
            format_hex(client.server_address.ip_v6.u16_values[2], "a"[0], 4),
            format_hex(client.server_address.ip_v6.u16_values[3], "a"[0], 4),
            format_hex(client.server_address.ip_v6.u16_values[4], "a"[0], 4),
            format_hex(client.server_address.ip_v6.u16_values[5], "a"[0], 4),
            format_hex(client.server_address.ip_v6.u16_values[6], "a"[0], 4),
            format_hex(client.server_address.ip_v6.u16_values[7], "a"[0], 4),
            client.server_address.port);

    {
        var result = try_platform_read_entire_file(platform, tmemory, client_save_state_path);
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
    var render = state.render_2d ref;

    var menu = state.menu ref;
    menu.ui = ui;
    menu.characters = { platform.character_count, platform.character_buffer.base } platform_character[];

    var game = client.game ref;

    var tiles_per_width = 20;
    var tiles_per_height = tiles_per_width / state.letterbox_width_over_heigth;
    var tile_size = ui.viewport_size.width / tiles_per_width;

    {
        var global is_init = false;

        if not is_init
        {
            var sprite_paths asset_path[];
            asset_paths_append(sprite_paths ref, platform, "assets/tiles/", "tile", tmemory);
            asset_paths_append(sprite_paths ref, platform, "assets/entities/", "entity", tmemory);
            asset_paths_append(sprite_paths ref, platform, "assets/items/", "item", tmemory);
            asset_generate_sprite_ids(sprite_paths, platform, tmemory);
            is_init = true;
        }
    }

    // try reloading key_bindings
    {
        var info = platform_get_file_info(platform, game_key_bindings_path);
        // if no file exist or timestamp changed
        if not state.key_bindings_are_init or (info.ok and (info.write_timestamp is_not state.key_bindings_write_timestamp))
        {
            state.key_bindings_write_timestamp = info.write_timestamp;
            state.key_bindings_are_init = true;

            var result = load_key_bindings(platform, state.temporary_memory ref);
            state.key_bindings = result.key_bindings;
            if result.error_message.count
            {
                // reset error_messages if we do not have enough space
                if result.error_message.count > (state.error_messages.capacity - state.error_messages.text.count)
                    state.error_messages.text.count = 0;

                write(state.error_messages ref, "%\n", result.error_message);
            }
        }
    }

    update(platform, state.input ref, state.key_bindings);
    var input = state.input;

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
            if state.font.atlas.handle
                glDeleteTextures(1, state.font.atlas.handle ref);

            state.font = {} ui_font;

            clear(state.font_memory ref);
            init(state.font ref,  platform, state.font_memory ref, tmemory, font_paths[font_index], font_height, 1024);
        }
    }

    var font = state.font;

    var cursor = cursor_below_position(font.info, 20, ui.viewport_size.height - 20);
    print(ui, 10, font, cursor ref, "version: %, fps: %, latency: %ms\n", game_version, 1.0 / platform.delta_seconds, client.latency_milliseconds);
    print(ui, 10, font, cursor ref, "hold F1 for info\n\n");

    if platform_key_is_active(platform, platform_key.f0 + 1)
    {
        // key bindings
        {
            var base = state.key_bindings ref cast(u8 ref);

            var compound_type = get_type_info(game_key_bindings).compound_type deref;
            var enumeration_type = get_type_info(platform_key).enumeration_type deref;

            loop var field_index usize; compound_type.fields.count
            {
                print(ui, 10, font, cursor ref, "%: ", compound_type.fields[field_index].name);

                var value = base deref;
                base += 1;

                var found = false;
                loop var item_index usize; enumeration_type.items.count
                {
                    if enumeration_type.items[item_index].value is value
                    {
                        print(ui, 10, font, cursor ref, "%\n", enumeration_type.items[item_index].name);
                        found = true;
                        break;
                    }
                }

                if not found
                {
                    var token = { 1, value ref } string;
                    print(ui, 10, font, cursor ref, "%\n", token);
                }
            }

            print(ui, 10, font, cursor ref, "\n");
        }

        print(ui, 10, font, cursor ref, "Log:\n%", state.error_messages.text);
    }

    if enable_font_cycling
        print(ui, 10, font, cursor ref, "font: % [%]\n", font_paths[font_index], font_index);

    if client.state is client_state.disconnected
    {
        if client.reject_reason is_not 0
            print(ui, 10, font, cursor ref, "Server rejected connection: %\n", client.reject_reason);
        else if client.pending_messages.resend_count_without_replies
            print(ui, 10, font, cursor ref, "Server is not responding, it may be offline\n");

        draw_box(ui, -1000, menu_color_background, ui.scissor_box);

        var box = draw_box_begin(ui);
        var cursor = cursor_below_position(font.info, ui.viewport_size.width * 0.5, ui.viewport_size.height * 0.75);

        print(ui, menu_layer.text, menu_color_idle, font, cursor ref, "user:    ");
        edit_string_begin(client.user_name_edit ref, client.user_name ref);
        menu_text_edit(menu, location_id(0), font, cursor ref, client.user_name_edit ref);
        edit_string_end(client.user_name_edit, client.user_name ref);

        print(ui, menu_layer.text, menu_color_idle, font, cursor ref, "password:    ");
        edit_string_begin(client.user_password_edit ref, client.user_password ref);
        menu_text_edit(menu, location_id(0), font, cursor ref, client.user_password_edit ref);
        edit_string_end(client.user_password_edit, client.user_password ref);

        advance_line(font.info, cursor ref);

        if menu_button(menu, location_id(0), font, cursor ref, "Host")
        {
            init(state.server ref, platform, state.network ref, client.server_address.tag, client.server_address.port, tmemory);
            init(client, state.network ref, client.server_address);

            var result = try_platform_read_entire_file(platform, tmemory, game_world_map_path);
            if result.ok and (result.data.count is type_byte_count(game_world_tile_map))
                copy_bytes(client.game.tile_map ref, result.data.base, result.data.count);

            state.is_host = true;
        }

        if menu_button(menu, location_id(0), font, cursor ref, "Connect")
        {
            init(client, state.network ref, client.server_address);

            var result = try_platform_read_entire_file(platform, tmemory, game_world_map_path);
            if result.ok and (result.data.count is type_byte_count(game_world_tile_map))
                copy_bytes(client.game.tile_map ref, result.data.base, result.data.count);
        }

        advance_line(font.info, cursor ref);

        if state.color_edit is_not color_edit_tag.none
        {
            var box box2;
            box.min.x = cursor.position.x + (tile_size * 3);
            box.max.y = cursor.position.y + (tile_size);
            box.max.x = ceil(box.min.x + (tile_size * 2));
            box.min.y = floor(box.max.y - (tile_size * 2));

            var colors =
            [
                client.name_color ref,
                client.body_color ref,
            ] color_hsva ref[];

            color_wheel(ui, 0, location_id(0), box, colors[state.color_edit - 1], false);
        }

        if menu_button(menu, location_id(0), font, cursor ref, "Name Color", state.color_edit is color_edit_tag.name_color)
        {
            state.color_edit = color_edit_tag.name_color;
        }

        if menu_button(menu, location_id(0), font, cursor ref, "Body Color", state.color_edit is color_edit_tag.body_color)
        {
            state.color_edit = color_edit_tag.body_color;
        }

        advance_line(font.info, cursor ref);

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
            var position = v2(cursor.position) + floor([ tile_size * 0.5, tile_size * -1.25 ] vec2);
            position *= (1 / tile_size);
            var sprite_texture_box box2;
            sprite_texture_box.min = [ 0, 0 ] vec2;
            sprite_texture_box.max = [ 128, 128 ] vec2;

            var box = draw_player(ui, position, tile_size, {} vec2, to_rgba8(client.body_color.color), state.user_sprite_index_plus_one is_not 0, state.user_sprite_texture, sprite_texture_box, state.sprite_view_direction);
            draw_player_name(ui, font, position, tile_size, {} vec2, to_string(client.user_name), to_rgba8(client.name_color.color));

            cursor.position.y = box.min.y cast(s32);
            advance_line(font.info, cursor ref);
        }
    }
    else
    {
        if state.is_host
        {
            tick(platform, state.server ref, state.network ref, platform.delta_seconds);

            if false
            {
                var client game_client_connection ref;
                while next_client(state.server ref, client ref)
                {
                    var buffer = client.send_buffer;
                    var client_index = (client - state.server.clients.base) cast(u32);

                    print(ui, 10, name_color, font, cursor ref, "client %, compress zero: packet_count: % [% bytes], compressed_packet_count: % [% bytes], compress packet rate: % [% bytes]\n", client_index, buffer.packet_count, buffer.byte_count, buffer.compressed_packet_count, buffer.compressed_byte_count,test_compress_zero_buffer.compressed_packet_count * 100.0 / buffer.packet_count, buffer.compressed_byte_count * 100.0 / buffer.byte_count);
                }
            }
        }

        tick(client, state.network ref, platform.delta_seconds);

        switch client.state
        case client_state.error_client_is_ipv4_only
        {
            var text_color = [ 255, 10, 10, 255 ] rgba8;
            print(ui, 10, text_color, font, cursor ref, "ERROR: To reach the server, you need an ip v6 address, but your connection only supports ip v4.\nCheck your internet ip for your ip v6 address.\nIf you don't have an ip v6, the server currently does not support your connection.\nOtherwise this is a bug, so please reach out to the developer.\n");
        }
        case client_state.connecting
        {
            var global animation_time f32;
            animation_time = fmod(animation_time + platform.delta_seconds, 1.0);
            var text_color = [ 255, 255, 255, (sin(animation_time * 2 * pi32) * 0.5 + 0.5 * 255) cast(u8) ] rgba8;

            if (client.server_address.tag is platform_network_address_tag.ip_v4)
                print(ui, 10, text_color, font, cursor ref, "Connecting to Server %.%.%.%:%", client.server_address.ip_v4[0], client.server_address.ip_v4[1], client.server_address.ip_v4[2], client.server_address.ip_v4[3], client.server_address.port);
        }
        case client_state.online
        {
            if client.capture_the_flag.is_running
            {
                var minutes = (client.capture_the_flag.play_time / 60) cast(u32);
                var seconds = (client.capture_the_flag.play_time - (minutes * 60)) cast(u32);
                print(ui, 10, font, cursor ref, "Capture The Flag time %:% - red % - % blue", minutes, seconds, client.capture_the_flag.score[0], client.capture_the_flag.score[1]);

                client.capture_the_flag.play_time += platform.delta_seconds;
            }
            else if client.capture_the_flag.play_time > 0
            {
                print(ui, 10, font, cursor ref, "Capture The Flag over. Result: - red % - % blue", client.capture_the_flag.score[0], client.capture_the_flag.score[1]);

                client.capture_the_flag.play_time -= platform.delta_seconds;
            }

            if client.is_admin
                print(ui, 10, font, cursor ref, "Admin User");

            // update(platform, state);

            var player = client.players[0] ref;

            if client.is_chatting
            {
                edit_string_begin(client.chat_message_edit ref, client.chat_message.text ref);

                edit_text(client.chat_message_edit ref, menu.characters ref);

                edit_string_end(client.chat_message_edit, client.chat_message.text ref);

                client.chat_message.is_shouting xor= platform_key_is_active(platform, platform_key.control) and platform_button_was_pressed(input.toggle_shout);

                if not platform_key_is_active(platform, platform_key.control) and not platform_key_is_active(platform, platform_key.alt) and not platform_key_is_active(platform, platform_key.shift) and platform_key_was_pressed(platform, platform_key.enter)
                {
                    client.send_chat_message = client.chat_message.text.count > 0;
                    client.chat_message = client.chat_message;
                    client.is_chatting = false;
                }
            }
            else
            {
                if platform_button_was_pressed(input.chat)
                {
                    client.is_chatting = true;
                    client.chat_message_edit.edit_offset = 0;
                    client.chat_message_edit.used_count  = 0;
                    client.chat_message.text.count       = 0;
                }
            }

            {
                if platform_key_is_active(platform, platform_key.alt) and platform_key_was_pressed(platform, platform_key.f0 + 3)
                    client.do_shutdown_server = true;

                var entity = get(game, player.entity_id);

                var movement vec2;
                if not client.is_chatting
                {
                    if entity.health
                    {
                        movement.x = input.right.is_active cast(s32) - input.left.is_active cast(s32);
                        movement.y = input.up.is_active cast(s32) - input.down.is_active cast(s32);

                        movement = normalize_or_zero(movement);
                        movement *= platform.delta_seconds;

                        client.frame_input.movement += movement;
                        client.frame_input.do_attack or= platform_button_was_pressed(input.attack);
                        client.frame_input.do_magic or= platform_button_was_pressed(input.magic);
                        client.frame_input.do_interact or= platform_button_was_pressed(input.interact);
                    }
                }

                {
                    if not client.local_player_position_is_init
                    {
                        client.local_player_position_is_init = true;
                        client.local_player_position = entity.position;
                    }

                    movement *= entity.player.movement_speed;

                    client.local_player_position += movement;

                    // smooth local postion to network position

                    if (squared_length(movement) is 0) or (squared_length(entity.position - client.local_player_position) > (0.25 * 0.25))
                        client.local_player_position = apply_spring_without_overshoot(client.local_player_position, entity.position, 1000, platform.delta_seconds);
                    else
                        client.local_player_position = apply_spring_without_overshoot(client.local_player_position, entity.position, 50, platform.delta_seconds);
                }

                // override player entity position
                client.network_player_position = entity.position;
                entity.position = client.local_player_position;

                check_world_collision(game.base ref, entity, platform.delta_seconds);
                client.local_player_position = entity.position;

                var position = client.local_player_position;

                var tile_frame = 4;
                var target_camera_position = game.camera_position;

                if position.x > (target_camera_position.x + (tiles_per_width * 0.5) - tile_frame)
                    target_camera_position.x = position.x - (tiles_per_width * 0.5) + tile_frame;
                else if position.x < (target_camera_position.x - (tiles_per_width * 0.5) + tile_frame)
                    target_camera_position.x = position.x + (tiles_per_width * 0.5) - tile_frame;

                if position.y > (target_camera_position.y + (tiles_per_height * 0.5) - tile_frame)
                    target_camera_position.y = position.y - (tiles_per_height * 0.5) + tile_frame;
                else if position.y < (target_camera_position.y - (tiles_per_height * 0.5) + tile_frame - 1)
                    target_camera_position.y = position.y + (tiles_per_height * 0.5) - tile_frame + 1;

                game.camera_position = apply_spring_without_overshoot(game.camera_position, target_camera_position, 1000, platform.delta_seconds);
            }

            // update(game, platform.delta_seconds);

            var tile_offset = floor(ui.viewport_size * 0.5 + (game.camera_position * -tile_size));

            // start render 2d frame after camera positoin update
            {
                var context = { ui.viewport_size, tile_offset, tile_size, {} f32[3] } render_2d_context;

                var sprite_paths string[];
                reallocate_array(tmemory, sprite_paths ref, asset_sprite_paths.count + state.custom_sprite_paths.count);

                // HACK: copy_array expects both array types to be identical
                var paths string[] = asset_sprite_paths;
                copy_array({ asset_sprite_paths.count, sprite_paths.base } string[], paths);
                copy_array({ state.custom_sprite_paths.count, sprite_paths.base + asset_sprite_paths.count } string[], state.custom_sprite_paths);

                frame(platform, state.gl ref, render, context, sprite_paths, tmemory);

                var font_paths =
                [
                    "C:/work/games/chatworld/assets/fonts/stanberry/Stanberry.ttf",
                    "C:/work/games/chatworld/assets/fonts/dinomouse/Dinomouse-Regular.otf",
                    "C:/work/games/chatworld/assets/fonts/Kosugi_Maru/KosugiMaru-Regular.ttf",
                ] string[];

                frame_font(platform, render, state.dynamic_font ref, font_paths, tmemory);
            }

            var dfont = state.dynamic_font ref;
            dfont.settings.pixel_height = 23;
            dfont.settings.font_index   = 0;
            dfont.cursor.baseline_x = 100;
            dfont.cursor.baseline_y = (ui.viewport_size.y - 100) cast(s32);
            dfont.cursor.line_start_x = dfont.cursor.baseline_x;
            dfont.cursor.layer = 1;

            var global text_rotation f32;
            text_rotation = fmod(text_rotation + platform.delta_seconds, 1.0);

            draw_text(render, dfont, "hello\n");
            dfont.settings.font_index = 1;
            draw_text(render, dfont, "hello\n");
            dfont.settings.font_index = 0;
            dfont.settings.pixel_height = 47;
            draw_text(render, dfont, "hello\n");

            dfont.settings.font_index = 2;
            dfont.settings.pixel_height = 47;
            {
                var text = "πポゴの時間だ\n";
                var letter_count u32;
                while text.count
                {
                    var phase = 1.0 + text_rotation - (0.05 * letter_count);
                    var color color_hsva;
                    color.hue = fmod(phase, 1.0);
                    color.saturation = 1.0;
                    color.value = 1.0;
                    color.alpha = 1.0;
                    evaluate(color ref);
                    var rainbow = color.color;

                    var letter_text = text;
                    letter_text.count = utf8_advance(text ref).byte_count;

                    var rotation = text_rotation * 2 * pi32;

                    var offset = (sin(2 * pi32 * phase) * 32) cast(s32);
                    //dfont.cursor.baseline_x += offset;
                    dfont.cursor.baseline_y += offset;

                    draw_text(render, v2(0.5), sin(2 * pi32 * phase) * 0.5 + 1, dfont, rainbow, letter_text);
                    //dfont.cursor.baseline_x -= offset;
                    dfont.cursor.baseline_y -= offset;
                    letter_count += 1;
                }
            }

            {
                var transform render_2d_transform;
                transform.pivot = game.camera_position;
                transform.alignment = v2(0.5);
                transform.layer = 1;
                draw_texture_box(render, transform, v2(10), dfont.atlas_texture_index, [ v2(0), v2(1) ] box2);
            }

            var camera_box box2;
            var camera_box_size = [ tiles_per_width, tiles_per_height ] vec2;
            camera_box.min = game.camera_position - (camera_box_size * 0.5);
            camera_box.max = game.camera_position + camera_box_size;

            var chat_message_frame = grow(ui.scissor_box, -floor(tile_size * 0.25));

            var tile_map = game.tile_map ref;

            var min_tile_x = floor(camera_box.min.x) cast(s32);
            var min_tile_y = floor(camera_box.min.y) cast(s32);
            var max_tile_x = ceil(camera_box.max.x) cast(s32);
            var max_tile_y = ceil(camera_box.max.y) cast(s32);

            loop var y = min_tile_y; max_tile_y
            {
                loop var x = min_tile_x; max_tile_x
                {
                    var box box2;
                    box.min = [ x, y ] vec2;
                    box.max = box.min + 1;
                    // var colors = [
                    //     [ 0.5, 0.1, 0.1, 1.0 ] vec4,
                    //     [ 0.1, 0.1, 0.5, 1.0 ] vec4,
                    // ] vec4[];

                    var colors = [
                        [ 0.5, 1.0, 1.0, 1.0 ] vec4,
                        [ 1.0, 1.0, 0.5, 1.0 ] vec4,
                    ] vec4[];

                    var color = colors[(x + y) bit_and 1];

                    var transform render_2d_transform;
                    transform.pivot = [ x, y ] vec2;
                    transform.layer = render.context.viewport_size.y cast(s16) * -2 - 2;
                    // draw_texture_box(render, transform, v2(1.0), color, {} render_2d_texture, {} box2);

                    var sprite_id = get_sprite(tile_map, x, y);
                    draw_sprite(render, sprite_id, transform); //, color);

                    if false
                    {
                    if (x + y) bit_and 1
                        draw_sprite(render, asset_sprite_id.tile_rpgtile019, transform);
                    else
                        draw_sprite(render, asset_sprite_id.tile_rpgtile024, transform);
                    }
                }
            }

            // draw entities
            {
                var index = next_entity_start;
                while next_entity(game.base ref, index ref)
                {
                    var entity = game.entity[index];
                    var animation = game.animation[index] ref;

                    var direction = direction_from_angle(entity.view_direction);
                    if direction.x > 0.2
                        animation.flip_x = true;
                    else if direction.x < -0.2
                        animation.flip_x = false;

                    if direction.y > 0.2
                        animation.show_back = true;
                    else if direction.y < -0.2
                        animation.show_back = false;

                    var transform render_2d_transform;
                    transform.pivot     = entity.position + entity.collider.center;
                    transform.alignment = v2(0.5);
                    transform.layer = get_y_layer(render, transform.pivot.y - entity.collider.radius);

                    var sprite_id = asset_sprite_id.none;
                    var color = [ 1, 1, 1, 1 ] vec4;

                    switch game.tag[index]
                    case game_entity_tag.chicken, game_entity_tag.dog_retriever
                    {
                        switch game.tag[index]
                        case game_entity_tag.chicken
                            sprite_id = asset_sprite_id.entity_chicken_back;
                        case game_entity_tag.dog_retriever
                        {
                            sprite_id = asset_sprite_id.entity_dog_back;

                            try_draw_team_mark(render, transform, entity.dog_retriever.team_index_plus_one - 1);
                        }

                        sprite_id += 1 - animation.show_back cast(u32);

                        if entity.health <= 0
                        {
                            // color = [ 0.4, 0.4, 0.4, 1.0 ] vec4;
                            transform.flip_y = true;
                        }
                    }
                    case game_entity_tag.healing_altar
                    {
                        draw_circle(render, transform.pivot, entity.collider.radius, 0.98, [ 0.1, 1.0, 0.1, 0.25 ] vec4);
                    }
                    case game_entity_tag.flag_target
                    {
                        draw_circle(render, transform.pivot, entity.collider.radius, 0.98, to_vec4(entity.flag_target.team_color));
                    }
                    case game_entity_tag.flag
                    {
                        if entity.flag.team_index_plus_one is 1
                            sprite_id = asset_sprite_id.item_flag_red;
                        else
                        {
                            assert(entity.flag.team_index_plus_one is 2);
                            sprite_id = asset_sprite_id.item_flag_blue;
                        }
                    }
                    case game_entity_tag.player_tent
                    {
                        sprite_id = asset_sprite_id.entity_player_tent_front;
                        color = to_vec4(game.player_tent[index].body_color);
                    }
                    case game_entity_tag.hitbox
                    {
                        var hitbox = entity.hitbox;
                        switch hitbox.tag
                        case game_entity_hitbox_tag.sword
                        {
                            sprite_id = asset_sprite_id.item_sword;
                            // our default view is right
                            // but sprite default orientation is up
                            transform.rotation  = entity.view_direction + (pi32 * 0.5);
                        }
                        case game_entity_hitbox_tag.fireball
                        {
                            sprite_id = asset_sprite_id.item_fireball;
                            animation.time = fmod(platform.delta_seconds * 2 + animation.time, 1.0);
                            transform.rotation  = animation.time * 2 * pi32;
                        }
                    }
                    case game_entity_tag.tall_grass
                    {
                        var sprite_id = asset_sprite_id.entity_tall_grass_4;

                        transform.pivot.y -= 0.5;
                        transform.alignment = [ 0.5, 0 ] vec2;

                        loop var i; 4
                        {
                            var sub_transform = transform;
                            sub_transform.pivot += [ (i mod 3) * 0.05, i * 0.2 ] vec2;
                            sub_transform.layer = get_y_layer(render, sub_transform.pivot.y);
                            // transform.flip_x = i bit_and 1;

                            var color = [ 1, 1, 1, 1 ] vec4;
                            color.rgb *= (i bit_and 1) * -0.2 + 1.0;

                            draw_sprite(render, sprite_id,  sub_transform, color);
                        }
                    }

                    transform.flip_x = animation.flip_x;

                    if sprite_id is_not asset_sprite_id.none
                    {
                        draw_sprite(render, sprite_id, transform, color);
                    }
                }
            }

            loop var i u32; client.player_count
            {
                var player = client.players[i];
                var entity = get(game, player.entity_id);
                var animation = game.animation[player.entity_id.index_plus_one - 1];

                var sprite_id = asset_sprite_id.count + animation.show_back cast(u32);

                var transform render_2d_transform;
                transform.pivot     = entity.position + entity.collider.center;
                transform.alignment = v2(0.5);
                transform.layer = get_y_layer(render, transform.pivot.y - entity.collider.radius);
                transform.flip_x = animation.flip_x;

                if entity.health <= 0
                    transform.rotation = pi32 * 0.5;

                draw_sprite(render, sprite_id, transform, to_vec4(player.body_color));

                try_draw_team_mark(render, transform, entity.player.team_index_plus_one - 1);

                var player_box = get_viewport_box(render, transform, v2(1));

                if player.chat_message_timeout > 0
                label draw_chat_box
                {
                    var alpha = pow(player.chat_message_timeout, 0.25);
                    var colors = get_chat_message_colors(player.chat_message, alpha);

                    def shout_distance = tiles_per_width * 3;

                    var text_position = get_point(player_box, [ 0.5, 1 ] vec2) + [ 0, tile_size * 0.5 ] vec2;
                    var text_alignment = [ 0.5, 0 ] vec2;

                    if is_contained(text_position, chat_message_frame)
                    {
                    }
                    else if player.chat_message.is_shouting and (squared_length(entity.position - client.local_player_position) <= (shout_distance * shout_distance))
                    {
                        text_position = clamp(text_position, chat_message_frame.min, chat_message_frame.max);
                        text_alignment = (text_position - chat_message_frame.min);
                        text_alignment.x /= chat_message_frame.max.x - chat_message_frame.min.x;
                        text_alignment.y /= chat_message_frame.max.y - chat_message_frame.min.y;
                    }
                    else
                    {
                        break draw_chat_box;
                    }

                    var aligned_state = draw_aligned_begin(ui, text_position, text_alignment);

                    var cursor = cursor_below_position(font.info, 0, 0);
                    print(ui, 11, colors.text_color, font, cursor ref, to_string(player.chat_message.text));

                    draw_rounded_box(ui, 10, colors.box_color, grow(ui.current_box, 8), 6);
                    var box = draw_aligned_end(ui, aligned_state);
                }

                if (i is 0) and client.is_chatting
                {
                    var aligned_state = draw_aligned_begin(ui, get_point(player_box, [ 0.5, 0 ] vec2) - [ 0, tile_size * 0.2 ] vec2, [ 0.5, 1 ] vec2);

                    // var t = pow(player.chat_message_timeout, 0.25);
                    var alpha = 1.0;

                    var text = to_string(client.chat_message.text);

                    var cursor = cursor_below_position(font.info, 0, 0);

                    var colors = get_chat_message_colors(client.chat_message, alpha);
                    var text_color = colors.text_color;
                    var box_color  = colors.box_color;

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
                    draw_rounded_box(ui, 10, box_color, grow(box, 8), 6);
                }
            }

            // draw colliders
            if false
            {
                var index = next_entity_start;
                while next_entity(game.base ref, index ref)
                {
                    var entity = game.entity[index];
                    var transform render_2d_transform;
                    transform.pivot = entity.position + entity.collider.center;

                    if false
                        transform.layer = render.context.viewport_size.y cast(s16) * -2; // draw below
                    else
                        transform.layer = 0;

                    draw_circle(render, transform.pivot, entity.collider.radius, transform.layer, [ 0.1, 0.1, 1, 0.25 ] vec4);
                }
            }

            // actual server send position
            if debug_player_server_position and client.player_count
            {
                var sprite_texture_box box2;
                sprite_texture_box.min = [ 0, 0 ] vec2;
                sprite_texture_box.max = [ 128, 128 ] vec2;

                var player = client.players[0];
                var entity = get(game, player.entity_id);
                var position = client.network_player_position;

                var body_color = player.body_color;
                body_color.r = 255 - body_color.r;
                body_color.g = 255 - body_color.g;
                body_color.b = 255 - body_color.b;
                body_color.alpha = 128;

                var name_color = player.name_color;
                name_color.alpha = 128;

                var box = draw_player(ui, position, tile_size, tile_offset, body_color, state.user_sprite_index_plus_one is_not 0, state.user_sprite_texture, sprite_texture_box, state.sprite_view_direction);
                draw_player_name(ui, font, position, tile_size, tile_offset, to_string(player.name), name_color);
            }

            if client.player_count
            {
                var player = client.players[0];
                var entity = get(game, player.entity_id);
                entity.position = client.network_player_position;
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

        save_key_bindings(platform, state.key_bindings, tmemory);
    }

    return true;
}

override func game_render game_render_type
{
    var tmemory = state.temporary_memory ref;
    var render = state.render_2d ref;
    execute(render, state.gl ref, tmemory);
}

enum render_texture_slot render_texture_slot_base
{
}

def player_draw_alignment = [ 0.5, 0 ] vec2; // 8.0 / 128.0 ] vec2;

func get_player_box(position vec2, tile_size f32, tile_offset vec2) (box box2)
{
    position = floor(position * tile_size) + tile_offset;
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
    ground_overlay;
    entity;
    overlay;
}

func draw_player_name(ui ui_system ref, font ui_font, position vec2, tile_size f32, tile_offset vec2, name string, name_color rgba8)
{
    var box = get_player_box(position, tile_size, tile_offset);
    print_aligned(ui, game_render_layer.overlay, name_color, font, get_point(box, [ 0.5, 1 ] vec2) + [ 0, tile_size * 0.1 ] vec2, [ 0.5, 0 ] vec2, "%", name);
}

func draw_player(ui ui_system ref, position vec2, tile_size f32, tile_offset vec2, body_color rgba8, use_sprite b8, sprite_texture gl_texture, sprite_texture_box box2, view_direction game_sprite_view_direction, is_knockdowned = false) (box box2)
{
    var box = get_player_box(position, tile_size, tile_offset);

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

        position = floor(position * tile_size) + tile_offset;
        draw_texture_box(ui, game_render_layer.entity, 1.0, rgba8_white, sprite_texture, position, sprite_texture_box, alignment, texture_scale, flip_x);

        assert(not is_knockdowned);
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

        if is_knockdowned
            draw_box(ui, game_render_layer.entity + 1, [ 50, 50, 50, 255 ] rgba8, grow(player_box, -floor(tile_size * 0.2)));
    }

    return box;
}

func try_draw_team_mark(render render_2d_api ref, transform render_2d_transform, team_index u32)
{
    if team_index < 2
    {
        transform.pivot.y -= 0.25;
        // all sprites y positions have 2 layers, so we place inbetween two sprite layers
        transform.layer += 1;
        def team_sprite_ids = [ asset_sprite_id.item_team_mark_red, asset_sprite_id.item_team_mark_blue ] asset_sprite_id[];

        draw_sprite(render, team_sprite_ids[team_index], transform);
    }
}