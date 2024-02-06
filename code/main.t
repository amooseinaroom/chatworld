
import network;

def game_title = "chat world";

struct program_state
{
    expand default default_program_state;

    game game_state;

    network platform_network;

    is_host b8;
    is_online b8;

    server game_server;
    client game_client;
}

func game_init program_init_type
{
    state.letterbox_width_over_heigth = 16.0 / 9.0;

    platform_network_init(state.network ref);
    //init(state.server ref, state.network ref);
    //init(state.client ref, state.network ref);
}

func game_update program_update_type
{
    var memory  = state.memory ref;
    var tmemory = state.temporary_memory ref;
    var ui      = state.ui ref;
    var game    = state.game ref;

    var font = state.font;

    if not state.is_online
    {   
        var box = draw_box_begin(ui);
        var cursor = cursor_below_position(font.info, ui.viewport_size.width * 0.5, ui.viewport_size.height * 0.5);

        if menu_button(ui, location_id(0), font, cursor ref, "Host Server")
        {
            init(state.server ref, state.network ref);
            init(state.client ref, state.network ref);
            state.is_host = true;
            state.is_online = true;
        }

        if menu_button(ui, location_id(0), font, cursor ref, "Connect")
        {            
            init(state.client ref, state.network ref);            
            state.is_online = true;
        }        
    }
    else
    {
        // update(platform, state);    

        var tiles_per_width = 20;
        var tiles_per_height = tiles_per_width / state.letterbox_width_over_heigth;

        var player = state.client.players[0] ref;

        state.client.frame_movement = {} vec2;
        state.client.frame_delta_seconds = 0;
        
        if game.is_chatting
        {
            if platform_key_was_pressed(platform, platform_key.enter)
            {
                state.client.send_chat_message = true;
                state.client.chat_message = to_string255("hello server!");
                game.is_chatting = false;
            }
        }
        else
        {
            if platform_key_was_pressed(platform, platform_key.enter)
            {
                game.is_chatting = true; 
            }

            var movement vec2;
            movement.x = platform_key_is_active(platform, "D"[0]) cast(s32) - platform_key_is_active(platform, "A"[0]) cast(s32);
            movement.y = platform_key_is_active(platform, "W"[0]) cast(s32) - platform_key_is_active(platform, "S"[0]) cast(s32);

            movement = normalize_or_zero(movement);

            var movement_speed = 6;
            // player.position += movement * (movement_speed * platform.delta_seconds);

            state.client.frame_movement = movement * movement_speed;
            state.client.frame_delta_seconds = platform.delta_seconds;

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
            tick(state.server ref, state.network ref);

        tick(state.client ref, state.network ref, platform.delta_seconds);

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

        loop var i u32; state.client.player_count
        {
            var player = state.client.players[i];
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
        }
    }

    if platform.do_quit
    {
    }

    return true;
}

enum render_texture_slot render_texture_slot_base
{
}