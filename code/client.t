import network;
import win32;
import math;
import gl;

struct game_client
{
    expand persistant_state game_client_persistant_state;

    game game_client_state;

    pending_messages client_pending_network_message_buffer;

    send_buffer network_send_buffer;

    state client_state;
    reject_reason network_message_reject_reason;

    latency_milliseconds u32;

    tick_send_timeout f32;

    frame_input network_message_user_input;

    players      game_player[max_player_count];
    player_count u32;

    is_admin b8;
    do_shutdown_server b8;

    chat_message_edit editable_text;
    chat_message      network_message_chat_text;
    send_chat_message b8;
    is_chatting       b8;

    entity_id         game_entity_id;
    entity_network_id game_entity_network_id;

    capture_the_flag struct
    {
        score u32[2];

        running_id u32;
        play_time  f32;
        is_running b8;
    };

    heartbeat_timeout f32;

    sprite_atlas gl_texture;

    pending_sprite game_user_sprite;
}

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

    local_player_position   vec2;
    network_player_position vec2;
    local_player_position_is_init b8;
};

struct game_client_state
{
    expand base game_state;

    // add some client only entity data
}

func get(game game_client_state ref, id game_entity_id) (entity game_entity ref)
{
    return get(game.base ref, id);
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

    chat_message network_message_chat_text;
    chat_message_timeout f32;

    entity_id         game_entity_id;
    entity_network_id game_entity_network_id;

    sprite_index_plus_one u32;
}

enum client_state
{
    disconnected;
    connecting;
    online;
}

// TODO: unify this with server pending messages somehow
struct client_pending_network_message
{
    expand base    network_message_union;
    resend_timeout f32;
}

struct client_pending_network_message_buffer
{
    expand base                         client_pending_network_message[2048];
           used_count                   u32;
           next_acknowledge_message_id  u16;
           resend_count_without_replies u32;
}

func queue(client game_client ref, message network_message_union)
{
    var buffer = client.pending_messages ref;
    network_assert(buffer.used_count < buffer.count);

    var pending_message = buffer[buffer.used_count] ref;
    buffer.used_count += 1;
    pending_message deref = {} client_pending_network_message;

    buffer.next_acknowledge_message_id += 1;
    if buffer.next_acknowledge_message_id is network_acknowledge_message_id_invalid
        buffer.next_acknowledge_message_id += 1;

    pending_message.base = message;
    pending_message.base.acknowledge_message_id = buffer.next_acknowledge_message_id;
}

func remove_acknowledged_message(client game_client ref, acknowledge_message_id u16, debug_tag network_message_tag)
{
    var buffer = client.pending_messages ref;
    loop var message_index u32; buffer.used_count
    {
        var message = buffer[message_index] ref;
        if message.base.acknowledge_message_id is acknowledge_message_id
        {
            network_print_info("Client: removed pending message % [%]", debug_tag, acknowledge_message_id);
            buffer.used_count -= 1;
            buffer[message_index] = buffer[buffer.used_count];
            break;
        }
    }
}

func init(client game_client ref, network platform_network ref, server_address platform_network_address)
{
    var persistant_state = client.persistant_state;
    clear_value(client);
    client.persistant_state = persistant_state;

    if not platform_network_is_valid(client.socket)
    {
        client.socket = platform_network_peer_open(network, server_address.tag);
        require(platform_network_is_valid(client.socket));

        if server_address.tag is platform_network_address_tag.ip_v4
            network_print("Client: connecting to ipv4: %.%.%.%, port: %\n",
                server_address.ip_v4[0],
                server_address.ip_v4[1],
                server_address.ip_v4[2],
                server_address.ip_v4[3],
                server_address.port);

        else
            network_print("Client: connecting to ipv6: %:%:%:%:%:%:%:%, port: %\n",
                format_hex(server_address.ip_v6.u16_values[0], "a"[0], 4),
                format_hex(server_address.ip_v6.u16_values[1], "a"[0], 4),
                format_hex(server_address.ip_v6.u16_values[2], "a"[0], 4),
                format_hex(server_address.ip_v6.u16_values[3], "a"[0], 4),
                format_hex(server_address.ip_v6.u16_values[4], "a"[0], 4),
                format_hex(server_address.ip_v6.u16_values[5], "a"[0], 4),
                format_hex(server_address.ip_v6.u16_values[6], "a"[0], 4),
                format_hex(server_address.ip_v6.u16_values[7], "a"[0], 4),
                server_address.port);
    }

    init(client.game.base ref, {} random_pcg);

    network_print("Client: started. version: %, port: %\n, print level: %, debug: %, enable_hot_reloading: %", game_version, client.socket.port, network_print_max_level, lang_debug, enable_hot_reloading);
    client.state = client_state.connecting;
    client.server_address = server_address;

    var message network_message_union;
    message.tag = network_message_tag.login;
    message.login.client_version = game_version;
    message.login.name     = client.user_name;
    message.login.password = client.user_password;
    message.login.name_color = to_rgba8(client.name_color.color);
    message.login.body_color = to_rgba8(client.body_color.color);
    queue(client, message);
}

func tick(client game_client ref, network platform_network ref, delta_seconds f32)
{
    if client.state is client_state.disconnected
        return;

    assert(platform_network_is_valid(client.socket));
    // init(client, network, client.server_address);

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
        var receive_buffer u8[network_max_packet_size];
        var result = receive(network, client.socket, receive_buffer);
        if not result.do_continue
            break;

        if not result.has_message
            continue;

        if result.address is_not client.server_address
            continue;

        var received_message network_message_union;
        while next_message(received_message ref, result.iterator ref)
        {

            // debug drop messages sometimes
            if false
            {
                if received_message.acknowledge_message_id is_not network_acknowledge_message_id_invalid
                {
                    var global throw_index u32;
                    throw_index = (throw_index + 1) mod 5;
                    if not throw_index
                    {
                        network_print_info("Client: dropped message % [%]", received_message.tag, received_message.acknowledge_message_id);
                        continue;
                    }
                }
            }

            // received a life sign from server
            client.pending_messages.resend_count_without_replies = 0;

            switch received_message.tag
            case network_message_tag.acknowledge
            {
                remove_acknowledged_message(client, received_message.acknowledge_message_id, received_message.tag);
            }
            case network_message_tag.login_accept
            {
                remove_acknowledged_message(client, received_message.acknowledge_message_id, received_message.tag);

                if client.state is_not client_state.connecting
                    break;

                var message = received_message.login_accept;
                client.entity_network_id = message.player_entity_network_id;
                client.state = client_state.online;

                // adding a player here is a bit redundant and needs to be the same as in
                // add_player message

                client.player_count = 0;

                var player = find_or_add_player(client, client.entity_network_id).player;
                assert(player);

                client.is_admin = message.is_admin;

                // will be filled out by add_player message
                // player.name = client.user_name;
                // player.name_color = to_rgba8(client.name_color.color);
                // player.body_color = to_rgba8(client.body_color.color);
                // player.entity_network_id = client.entity_network_id;
            }
            case network_message_tag.login_reject
            {
                remove_acknowledged_message(client, received_message.acknowledge_message_id, received_message.tag);

                client.state = client_state.disconnected;
                client.reject_reason = received_message.login_reject.reason;
                return;
            }
            case network_message_tag.add_player
            {
                if client.state is_not client_state.online
                    break;

                var message = received_message.add_player;
                var player = find_or_add_player(client, message.entity_network_id).player;

                if not player
                {
                    network_print("Client: rejected add player");
                    break;
                }

                player.name              = message.name;
                player.name_color        = message.name_color;
                player.body_color        = message.body_color;
            }
            case network_message_tag.remove_player
            {
                if client.state is_not client_state.online
                    break;

                var message = received_message.remove_player;

                var entity_id = find_network_entity(game, message.entity_network_id);
                var result = find_player(client, entity_id);
                if result.player
                {
                    remove(game, entity_id);
                    client.player_count -= 1;
                    client.players[result.index] = client.players[client.player_count];
                }
            }
            case network_message_tag.update_entity
            {
                if client.state is_not client_state.online
                    break;

                var message = received_message.update_entity;

                var entity_id = find_network_entity(game, message.network_id);
                if not entity_id.value
                    entity_id = add(game, message.tag, message.network_id);

                var entity = get(game, entity_id);
                entity deref = message.entity;
            }
            case network_message_tag.delete_entity
            {
                if client.state is_not client_state.online
                    break;

                var message = received_message.delete_entity;

                var entity_id = find_network_entity(game, message.network_id);
                if entity_id.value
                    remove_for_real(game, entity_id);
            }
            case network_message_tag.update_player_tent
            {
                if client.state is_not client_state.online
                    break;

                var message = received_message.update_player_tent;
                var entity_id = find_network_entity(game, message.entity_network_id);
                if not entity_id.value
                    break;

                game.player_tent[entity_id.index_plus_one - 1] = message.player_tent;

            }
            case network_message_tag.chat
            {
                if client.state is_not client_state.online
                    break;

                var message = received_message.chat;

                var entity_id = find_network_entity(game, message.player_entity_network_id);
                var player = find_player(client, entity_id).player;
                if player
                {
                    player.chat_message = message.text;
                    player.chat_message_timeout = 1;
                }
            }
            case network_message_tag.latency
            {
                assert(received_message.latency.latency_id is_not invalid_latency_id);

                client.latency_milliseconds = received_message.latency.latency_milliseconds;
                reply_latency_id = received_message.latency.latency_id;
            }
            case network_message_tag.capture_the_flag_started
            {
                clear_value(client.capture_the_flag ref);
                client.capture_the_flag.is_running = true;
            }
            case network_message_tag.capture_the_flag_ended
            {
                client.capture_the_flag.play_time = 1 * 60.0; // time to fade score result
                client.capture_the_flag.is_running = false;
            }
            case network_message_tag.capture_the_flag_score
            {
                var message = received_message.capture_the_flag_score;
                if message.running_id > client.capture_the_flag.running_id
                {
                    client.capture_the_flag.score[message.team_index] = message.score;
                    client.capture_the_flag.play_time = message.play_time;
                    client.capture_the_flag.running_id = message.running_id;
                }
            }
            case network_message_tag.capture_the_flag_player_team
            {
                var message = received_message.capture_the_flag_player_team;

                var entity_id = find_network_entity(game, message.entity_network_id);
                if entity_id.value
                {
                    var player = get(game, entity_id);
                    player.player.team_index = message.team_index;
                    player.player.team_color = message.team_color;
                }
            }

            if received_message.tag is_not network_message_tag.acknowledge and (received_message.acknowledge_message_id is_not network_acknowledge_message_id_invalid)
            {
                var message network_message_union;
                message.tag                    = network_message_tag.acknowledge;
                message.acknowledge_message_id = received_message.acknowledge_message_id;
                network_print_info("Client: acknowledged % [%]", received_message.tag, received_message.acknowledge_message_id);

                send(network, client, message);
            }

            network_print_verbose("Client: server message % %\n", received_message.tag, result.address);
        }
    }

    switch client.state
    case client_state.disconnected
    {

    }
    case client_state.connecting
    {
        if client.pending_messages.resend_count_without_replies > 10
        {
            client.state = client_state.disconnected;
            return;
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
            queue(client, message);
        }

        if client.frame_input.do_attack or client.frame_input.do_magic or client.frame_input.do_interact or (squared_length(client.frame_input.movement) > 0)
        {
            var message network_message_union;
            message.user_input = client.frame_input;
            message.tag = network_message_tag.user_input; // frame_input has no tag set
            send(network, client, message);

            reset_heartbeat = true;
        }

        if client.send_chat_message
        {
            var message network_message_union;
            message.tag = network_message_tag.chat;
            message.chat.text = client.chat_message;
            queue(client, message);
        }

        client.frame_input = {} network_message_user_input;
    }

    client.send_chat_message = false;

    // send pending_messages
    {
        var buffer = client.pending_messages ref;
        loop var message_index u32; buffer.used_count
        {
            var message = buffer[message_index] ref;
            message.resend_timeout -= delta_seconds * 2; // twice per second
            if message.resend_timeout > 0
                continue;

            message.resend_timeout += 1;
            buffer.resend_count_without_replies += 1;

            network_print_info("Client: send % [%]", message.base.tag, message.base.acknowledge_message_id);

            send(network, client, message.base);

            reset_heartbeat = true;
        }
    }

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
            send(network, client, message);
        }
    }

    if reply_latency_id is_not invalid_latency_id
    {
        var message network_message_union;
        message.tag = network_message_tag.latency;
        message.latency.latency_id = reply_latency_id;

        send(network, client, message);
    }

    send_flush(network, client);
}

func find_player(client game_client ref, entity_id game_entity_id) (player game_player ref, index u32)
{
    if not entity_id.value
        return null, u32_invalid_index;

    var found_index = u32_invalid_index;
    loop var i u32; client.player_count
    {
        if client.players[i].entity_id.value is entity_id.value
            return client.players[i] ref, i;
    }

    return null, u32_invalid_index;
}

func find_or_add_player(client game_client ref, entity_network_id game_entity_network_id) (player game_player ref, index u32)
{
    var entity_id = find_network_entity(client.game.base ref, entity_network_id);
    var result = find_player(client, entity_id);
    if not result.player
    {
        if client.player_count >= client.players.count
        {
            network_print("Client: can't add more remote players");
            return null, u32_invalid_index;
        }

        result.index  = client.player_count;
        result.player = client.players[result.index] ref;
        client.player_count += 1;
        result.player deref = {} game_player;

        if not entity_id.value
            result.player.entity_id = add_player(client.game.base ref, entity_network_id);
        else
            result.player.entity_id = entity_id;

        result.player.entity_network_id = entity_network_id;
    }

    return result;
}

func find_network_entity(game game_state ref, network_id game_entity_network_id) (entity_id game_entity_id)
{
    var entity_id game_entity_id;
    loop var i u32; game.entity.count
    {
        if (game.tag[i] is game_entity_tag.none) or (game.network_id[i] is_not network_id)
            continue;

        entity_id.index_plus_one = i + 1;
        entity_id.generation     = game.generation[i];
        break;
    }

    return entity_id;
}

func send(network platform_network ref, client game_client ref, message network_message_union)
{
    assert(client.state is_not client_state.disconnected);
    send(network, client.socket, client.server_address, client.send_buffer ref, message);
}

func send_flush(network platform_network ref, client game_client ref)
{
    assert(client.state is_not client_state.disconnected);
    send_flush(network, client.socket, client.server_address, client.send_buffer ref);
}