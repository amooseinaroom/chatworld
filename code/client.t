import network;
import win32;
import math;
import gl;

struct game_client_persistant_state
{
    socket platform_network_socket;

    server_address platform_network_address;

    user_name_edit editable_text;
    user_name      string63;

    name_color color_hsva;
    body_color color_hsva;

    user_password_edit editable_text;
    user_password      string63;
};

struct game_client_state
{
    expand base game_state;

    predicted_position vec2[max_entity_count];
}

func get(game game_client_state ref, id game_entity_id) (entity game_entity ref)
{
    return get(game.base ref, id);
}

struct game_client
{
    expand persistant_state game_client_persistant_state;

    game game_client_state;

    state client_state;
    reconnect_timeout f32;
    reconnect_count   u32;
    reject_reason network_message_reject_reason;

    latency_milliseconds u32;

    tick_send_timeout f32;

    frame_input network_message_user_input;

    players      game_player[max_player_count];
    player_count u32;

    is_admin b8;
    do_shutdown_server b8;

    chat_message_edit editable_text;
    chat_message      string255;
    send_chat_message b8;

    entity_id game_entity_id;
    network_id u32;

    heartbeat_timeout f32;

    sprite_atlas gl_texture;

    pending_sprite game_user_sprite;
}

type game_sprite_atlas_id union
{
    expand pair struct
    {
        generation     u32;
        index_plus_one u32;
    };

    value u64;
};

struct game_sprite_atlas
{
    texture gl_texture;
    generation         u32[256];
    unused_frame_count u32[256];
    freelist           u32[256];
    used_count         u32;
}

func frame(atlas game_sprite_atlas ref)
{
    loop var i u32; atlas.freelist.count
    {
        atlas.unused_frame_count[i] += 1;

        // free on overlow
        if not atlas.unused_frame_count[i]
        {
            loop var j u32; atlas.used_count
            {
                if atlas.freelist[j] is i
                {
                    atlas.used_count -= 1;
                    atlas.freelist[atlas.used_count] = i;
                    break;
                }
            }
        }
    }
}

func get_sprite_position(atlas game_sprite_atlas ref, index u32) (x s32, y s32)
{
    var row_count = atlas.texture.width / 256;

    var y = ((index / row_count) * 128) cast(s32);
    var x = ((index mod row_count) * 256) cast(s32);
    return x, y;
}

func add_sprite(atlas game_sprite_atlas ref, sprite game_user_sprite ref) (id game_sprite_atlas_id)
{
    if (atlas.used_count >= atlas.freelist.count)
        return {} game_sprite_atlas_id;

    var index = atlas.freelist[atlas.used_count];
    atlas.used_count += 1;

    atlas.generation[index] += 1;

    var position = get_sprite_position(atlas, index);

    glBindTexture(GL_TEXTURE_2D, atlas.texture.handle);
    glTexSubImage2D(GL_TEXTURE_2D, 0, position.x, position.y, 256, 128, GL_RGBA, GL_UNSIGNED_BYTE, sprite.base);
    glBindTexture(GL_TEXTURE_2D, 0);

    return { atlas.generation[index], index + 1 } game_sprite_atlas_id;
}

func remove_sprite(atlas game_sprite_atlas ref, id game_sprite_atlas_id)
{
    if not id.index_plus_one
        return;

    assert(id.index_plus_one < atlas.freelist.count);
    var index = id.index_plus_one - 1;

    if atlas.generation[index] is_not id.generation
        return;

    atlas.generation[index] += 1;

    assert(atlas.used_count);
    atlas.used_count -= 1;
    atlas.freelist[atlas.used_count] = index;
}

func get_sprite(atlas game_sprite_atlas ref, id game_sprite_atlas_id) (ok b8, texture_box box2)
{
    if not id.index_plus_one
        return false, {} box2;

    assert(id.index_plus_one < atlas.freelist.count);
    var index = id.index_plus_one - 1;

    if atlas.generation[index] is_not id.generation
        return false, {} box2;

    // reset unused frame count
    atlas.unused_frame_count[index] = 0;

    var position = get_sprite_position(atlas, index);
    var texture_box box2;
    texture_box.min.x = position.x;
    texture_box.min.y = position.y;
    texture_box.max.x = texture_box.min.x + 256;
    texture_box.max.y = texture_box.min.y + 128;

    return true, texture_box;
}

struct game_client_save_state
{
    user_name     string63;
    user_password string63;
    sprite_path   string255;
    name_color    color_hsva;
    body_color    color_hsva;
}

enum game_sprite_view_direction
{
    front_left;
    front_right;
    back_right;
    back_left;
}

def client_save_state_path = "client_save_state.bin";

struct game_player
{
    name       string63;
    name_color rgba8;
    body_color rgba8;

    chat_message         string255;
    chat_message_timeout f32;

    entity_id         game_entity_id;
    entity_network_id u32;

    sprite_index_plus_one u32;
}

enum client_state
{
    disconnected;
    connecting;
    online;
}

func init(client game_client ref, network platform_network ref, server_address platform_network_address)
{
    var persistant_state = client.persistant_state;
    clear_value(client);
    client.persistant_state = persistant_state;

    if not platform_network_is_valid(client.socket)
    {
        client.socket = platform_network_bind(network);
        require(platform_network_is_valid(client.socket));
    }

    init(client.game.base ref, {} random_pcg);

    network_print("Client: started. version: %, port: %\n, print level: %, debug: %, enable_hot_reloading: %", game_version, client.socket.port, network_print_max_level, lang_debug, enable_hot_reloading);
    client.state = client_state.connecting;
    client.server_address = server_address;
}

func tick(client game_client ref, network platform_network ref, delta_seconds f32)
{
    var game = client.game.base ref;

    var reset_heartbeat = false;

    loop var i u32; client.player_count
    {
        if client.players[i].chat_message_timeout > 0
            client.players[i].chat_message_timeout -= delta_seconds * 0.1;
    }

    var reply_latency_id = invalid_latency_id;

    while true
    {
        var result = receive(network, client.socket);
        if not result.ok
            break;

        if result.address is_not client.server_address
            continue;

        switch result.message.tag
        case network_message_tag.login_accept
        {
            if client.state is client_state.connecting
            {
                client.network_id = result.message.login_accept.id;
                client.state = client_state.online;

                // adding a player here is a bit redundant and needs to be the same as in
                // add_player message
                var entity_id = add_player(game, client.network_id);
                client.player_count = 0;
                client.is_admin = result.message.login_accept.is_admin;
                var player = find_player(client, entity_id);
                assert(player);
                player.name = client.user_name;
                player.name_color = to_rgba8(client.name_color.color);
                player.body_color = to_rgba8(client.body_color.color);
                player.entity_network_id = client.network_id;
            }
        }
        case network_message_tag.login_reject
        {
            client.state = client_state.disconnected;
            client.reject_reason = result.message.login_reject.reason;
        }
        case network_message_tag.add_player
        {
            if client.state is_not client_state.online
                break;

            var message = result.message.add_player;
            var entity_id = find_network_entity(game, message.entity_network_id);
            if not entity_id.value
            {
                entity_id = add_player(game, message.entity_network_id);
                var player = find_player(client, entity_id);
                if player
                {
                    player.name       = message.name;
                    player.name_color = message.name_color;
                    player.body_color = message.body_color;
                    player.entity_network_id = message.entity_network_id;
                }
                else
                    remove(game, entity_id); // we could not add a player, so we remove the entity
            }
        }
        case network_message_tag.remove_player
        {
            if client.state is_not client_state.online
                break;

            var message = result.message.remove_player;

            var found_index = u32_invalid_index;
            loop var i u32; client.player_count
            {
                if client.players[i].entity_network_id is message.entity_network_id
                {
                    client.player_count -= 1;
                    var entity_id = client.players[i].entity_id;
                    remove(game, entity_id);
                    client.players[i] = client.players[client.player_count];
                    break;
                }
            }
        }
        case network_message_tag.update_entity
        {
            if client.state is_not client_state.online
                break;

            var message = result.message.update_entity;

            var entity_id = find_network_entity(game, message.id);
            if not entity_id.value
                entity_id = add(game, message.entity.tag, message.id);

            var entity = get(game, entity_id);
            entity deref = message.entity;
        }
        case network_message_tag.delete_entity
        {
            if client.state is_not client_state.online
                break;

            var message = result.message.delete_entity;

            var entity_id = find_network_entity(game, message.id);
            if entity_id.value
                remove_for_real(game, entity_id);
        }
        case network_message_tag.chat
        {
            if client.state is_not client_state.online
                break;

            var message = result.message.chat;

            var entity_id = find_network_entity(game, message.id);
            assert(entity_id.value);

            var player = find_player(client, entity_id);
            player.chat_message = message.text;
            player.chat_message_timeout = 1;
        }
        case network_message_tag.latency
        {
            assert(result.message.latency.latency_id is_not invalid_latency_id);

            client.latency_milliseconds = result.message.latency.latency_milliseconds;
            reply_latency_id = result.message.latency.latency_id;
        }

        network_print_info("Client: server message % %\n", result.message.tag, result.address);
    }

    switch client.state
    case client_state.disconnected
    {

    }
    case client_state.connecting
    {
        client.reconnect_timeout -= delta_seconds;

        if client.reconnect_timeout <= 0
        {
            client.reconnect_timeout += 1.0;

            client.reconnect_count += 1;
            if client.reconnect_count > 10
            {
                client.state = client_state.disconnected;
                break;
            }

            var message network_message_union;
            message.tag = network_message_tag.login;
            message.login.client_version = game_version;
            message.login.name     = client.user_name;
            message.login.password = client.user_password;
            message.login.name_color = to_rgba8(client.name_color.color);
            message.login.body_color = to_rgba8(client.body_color.color);

            send(network, message, client.socket, client.server_address);
            network_print_info("Client: reconnecting\n");
        }
    }
    case client_state.online
    {
        // trottle send rete
        client.tick_send_timeout -= delta_seconds * server_seconds_per_tick;
        if client.tick_send_timeout > 0
            break;

        client.tick_send_timeout -= 1.0;

        if client.do_shutdown_server
        {
            client.do_shutdown_server = false;

            var message network_message_union;
            message.tag = network_message_tag.admin_server_shutdown;
            send(network, message, client.socket, client.server_address);
        }

        if client.frame_input.do_attack or (squared_length(client.frame_input.movement) > 0)
        {
            var message network_message_union;
            message.user_input = client.frame_input;
            message.tag = network_message_tag.user_input; // frame_input has no tag set
            send(network, message, client.socket, client.server_address);
            reset_heartbeat = true;
        }

        if client.send_chat_message
        {
            var message network_message_union;
            message.tag = network_message_tag.chat;
            message.chat.text = client.chat_message;
            send(network, message, client.socket, client.server_address);
            reset_heartbeat = true;
        }

        client.frame_input = {} network_message_user_input;
    }

    client.send_chat_message = false;

    if reset_heartbeat
    {
        client.heartbeat_timeout = 1;
    }
    else
    {
        client.heartbeat_timeout -= delta_seconds * heartbeats_per_seconds;
        if client.heartbeat_timeout <= 0
        {
            client.heartbeat_timeout += 1;

            var message network_message_union;
            message.tag = network_message_tag.heartbeat;
            send(network, message, client.socket, client.server_address);
        }
    }

    if reply_latency_id is_not invalid_latency_id
    {
        var message network_message_union;
        message.tag = network_message_tag.latency;
        message.latency.latency_id = reply_latency_id;
        send(network, message, client.socket, client.server_address);
    }
}

func find_player(client game_client ref, entity_id game_entity_id) (player game_player ref)
{
    var found_index = u32_invalid_index;
    loop var i u32; client.player_count
    {
        if client.players[i].entity_id.value is entity_id.value
        {
            found_index = i;
            break;
        }
    }

    if found_index is u32_invalid_index
    {
        if client.player_count >= client.players.count
        {
            network_print_info("Client: can't add more remote player\n");
            return null;
        }

        found_index = client.player_count;
        var player = client.players[found_index] ref;
        player deref = {} game_player;
        player.entity_id = entity_id;
        client.player_count += 1;
    }

    return client.players[found_index] ref;
}

func find_network_entity(game game_state ref, network_id u32) (id game_entity_id)
{
    var entity_id game_entity_id;
    loop var i u32; game.entity.count
    {
        if (not game.active[i]) or (game.network_id[i] is_not network_id)
            continue;

        entity_id.index_plus_one = i + 1;
        entity_id.generation     = game.generation[i];
        break;
    }

    return entity_id;
}