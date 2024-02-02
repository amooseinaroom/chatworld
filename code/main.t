
import network;

def game_title = "chat world";

struct program_state
{
    expand default default_program_state;

    game game_state;

    network platform_network;
    server game_server;
    client game_client;
}

func game_init program_init_type
{
    state.letterbox_width_over_heigth = 16.0 / 9.0;

    platform_network_init(state.network ref);
    init(state.server ref, state.network ref);
    init(state.client ref, state.network ref);
}

func game_update program_update_type
{
    var memory  = state.memory ref;
    var tmemory = state.temporary_memory ref;
    var ui      = state.ui ref;
    var game    = state.game ref;

    var font = state.font;

    // update(platform, state);    

    var tiles_per_width = 20;
    var tiles_per_height = tiles_per_width / state.letterbox_width_over_heigth;

    var player = state.client.players[0] ref;
    
    {
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
    }

    if platform.do_quit
    {
    }

    return true;
}

enum render_texture_slot render_texture_slot_base
{
}