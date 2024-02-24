
struct game_server
{
    game game_state;

    socket platform_network_socket;

    users game_user_buffer;

    clients      game_client_connection[max_player_count];
    client_count u32;

    next_network_id u32;

    latency_timestamp_milliseconds u64;
    latency_timeout                f32;
    latency_id                     u32;

    do_shutdown b8;
}

struct game_client_connection
{
    address    platform_network_address;

    name_color rgba8;
    body_color rgba8;

    entity_id         game_entity_id;
    entity_network_id u32;
    user_index    u32;
    do_update  b8;
    is_new     b8;
    do_remove  b8;

    latency_milliseconds u32;

    heartbeat_timeout      f32;
    missed_heartbeat_count u32;

    fireball_cooldown f32;

    chat_message           string255;
    broadcast_chat_message b8;
}

struct game_user
{
    name     string63;
    password string63;
    is_admin b8;
}

struct game_user_buffer
{
           user_count  u32;
    expand base        game_user[1 bit_shift_left 14];
}

def server_user_path = "server_users.bin";

func init(server game_server ref, platform platform_api ref, network platform_network ref, server_port u16, tmemory memory_arena ref)
{
    server.socket = platform_network_bind(network, server_port);
    require(platform_network_is_valid(server.socket));
    network_print("Server: started. version: %, port: %, print level: %, debug: %\n", game_version, server_port, network_print_max_level, lang_debug);

    var result = try_platform_read_entire_file(platform, tmemory, server_user_path);
    if result.ok
    {
        var data = result.data;
        if data.count is type_byte_count(game_user_buffer)
            copy_bytes(server.users ref, data.base, data.count);
    }

    init(server.game ref);
}

func save(platform platform_api ref, server game_server ref)
{
    platform_write_entire_file(platform, server_user_path, value_to_u8_array(server.users));
}

func new_network_id(server game_server ref) (id u32)
{
    server.next_network_id += 1;

    if not server.next_network_id
        server.next_network_id += 1;

    return server.next_network_id;
}

func tick(platform platform_api ref, server game_server ref, network platform_network ref, delta_seconds f32)
{
    var game = server.game ref;

    var timestamp_milliseconds = platform_local_timestamp_milliseconds(platform);

    while true
    {
        var result = receive(network, server.socket);
        if not result.ok
            break;

        var found_client_index = u32_invalid_index;
        loop var i u32; server.client_count
        {
            if server.clients[i].address is result.address
            {
                found_client_index = i;
                break;
            }
        }

        var client game_client_connection ref;
        if (found_client_index is u32_invalid_index) and (result.message.tag is_not network_message_tag.login)
            continue;

        if found_client_index is_not u32_invalid_index
            client = server.clients[found_client_index] ref;

        if client and client.do_remove
            continue;

        switch result.message.tag
        case network_message_tag.login
        {
            var message = result.message.login;

            var reject_reason = network_message_reject_reason.none;

            var found_user_index = u32_invalid_index;

            label check_reject
            {
                if message.client_version is_not game_version
                {
                    reject_reason = network_message_reject_reason.version_missmatch;
                    break check_reject;
                }

                loop var i u32; server.users.user_count
                {
                    if server.users[i].name is message.name
                    {
                        if server.users[i].password is_not message.password
                        {
                            reject_reason = network_message_reject_reason.credential_missmatch;
                            break check_reject;
                        }

                        if client and (client.user_index is i)
                            break check_reject;

                        loop var client_index u32; server.client_count
                        {
                            if server.clients[client_index].user_index is i
                            {
                                network_print_info("Server: rejected player, user is already logged in! % %\n", to_string(message.name), result.address);
                                reject_reason = network_message_reject_reason.duplicated_user_login;
                                break check_reject;
                            }
                        }

                        found_user_index = i;
                        break;
                    }
                }

                if (found_user_index is u32_invalid_index) and (server.users.user_count >= server.users.count)
                {
                    network_print_info("Server: rejected user, server users are full! %\n", result.address);
                    reject_reason = network_message_reject_reason.server_full_total_user;
                    break check_reject;
                }

                if (found_client_index is u32_invalid_index) and (server.client_count >= server.clients.count)
                {
                    network_print_info("Server: rejected player, game is full! %\n", result.address);
                    reject_reason = network_message_reject_reason.server_full_active_player;
                    break check_reject;
                }
            }

            if reject_reason is_not 0
            {
                var message network_message_union;
                message.tag = network_message_tag.login_reject;
                message.login_reject.reason = reject_reason;
                send(network, message, server.socket, result.address);
            }
            else
            {
                if found_user_index is u32_invalid_index
                {
                    var add_user_result = add_user(server, message.name, message.password);
                    assert(add_user_result.user);
                    found_user_index = add_user_result.user_index;
                }

                if found_client_index is u32_invalid_index
                {
                    found_client_index = server.client_count;
                    server.client_count += 1;

                    client = server.clients[found_client_index] ref;
                    client deref = {} game_client_connection;

                    client.address = result.address;
                    client.is_new  = true;

                    client.name_color = message.name_color;
                    client.body_color = message.body_color;

                    client.entity_network_id = new_network_id(server);
                    client.entity_id = add_player(game, client.entity_network_id);
                    client.user_index = found_user_index;

                    network_print_info("Server: added Client %\n", result.address);
                }

                assert(client.user_index is found_user_index);

                var message network_message_union;
                message.tag = network_message_tag.login_accept;
                message.login_accept.id = client.entity_network_id;
                message.login_accept.is_admin = server.users[found_user_index].is_admin;
                send(network, message, server.socket, client.address);
            }
        }
        case network_message_tag.user_input
        {
            var entity = get(game, client.entity_id);
            assert(entity);
            entity.movement += result.message.user_input.movement;

            if result.message.user_input.do_attack
            {
                if client.fireball_cooldown <= 0
                {
                    client.fireball_cooldown = 1;
                    var movement = normalize_or_zero(result.message.user_input.movement);
                    if squared_length(movement) is 0
                        movement = [ 0, 1 ] vec2;

                    add_fireball(game, new_network_id(server), entity.position + [ 0, entity.collider.radius ] vec2, movement * 2);
                }
            }

            client.do_update = true;
        }
        case network_message_tag.heartbeat
        {
        }
        case network_message_tag.latency
        {
            if result.message.latency.latency_id is server.latency_id
            {
                var round_trip_milliseconds = timestamp_milliseconds - server.latency_timestamp_milliseconds;

                // avarage over last 10 latencies
                if not client.latency_milliseconds
                    client.latency_milliseconds = (round_trip_milliseconds / 2) cast(u32);
                else
                    client.latency_milliseconds = (client.latency_milliseconds * 0.9 + (round_trip_milliseconds cast(f32) * 0.05)) cast(u32);
            }
        }
        case network_message_tag.chat
        {
            client.chat_message = result.message.chat.text;
            client.broadcast_chat_message = true;
        }
        case network_message_tag.admin_server_shutdown
        {
            var ok = false;
            if client
            {
                var user = server.users[client.user_index];
                if user.is_admin
                {
                    server.do_shutdown = true;
                    ok = true;
                    return;
                }

                if not ok
                {
                    var message network_message_union;
                    message.tag = network_message_tag.login_reject;
                    message.login_reject.reason = network_message_reject_reason.server_kick;
                    client.do_remove = true;
                    send(network, message, server.socket, client.address);
                }
            }
        }

        if client
        {
            client.heartbeat_timeout = 1;
            client.missed_heartbeat_count = 0;
        }

        network_print_info("Server: client message % %\n", result.message.tag, result.address);
    }

    // disconnect users that missed too many heartbeats
    loop var i u32; server.client_count
    {
        var client = server.clients[i] ref;
        client.heartbeat_timeout -= delta_seconds * heartbeats_per_seconds;
        if client.heartbeat_timeout <= 0
        {
            client.heartbeat_timeout += 1;
            client.missed_heartbeat_count += 1;

            if client.missed_heartbeat_count > max_missed_heartbeats
                client.do_remove = true;
        }
    }

    // send other users remove_player and remove client afterwards
    loop var a u32; server.client_count
    {
        var client = server.clients[a] ref;

        if client.do_remove
        {
            loop var b u32; server.client_count
            {
                var other = server.clients[b] ref;

                var message network_message_union;
                message.tag = network_message_tag.remove_player;
                message.remove_player.entity_network_id = client.entity_network_id;
                send(network, message, server.socket, other.address);
            }

            network_print_info("Server: Client % missed to many heartbeats and is considered MIA\n", client.address);
            remove(game, client.entity_id);
            server.client_count -= 1;
            server.clients[a] = server.clients[server.client_count];
            a -= 1; // repeat index
        }
    }

    // broadcast remove entity
    // before update, so entity is not deleted yet
    loop var i u32; game.entity.count
    {
        if (not game.active[i])
            continue;

        if game.do_delete[i]
        {
            loop var a u32; server.client_count
            {
                var client = server.clients[a] ref;

                var message network_message_union;
                message.tag = network_message_tag.delete_entity;
                message.delete_entity.id = game.network_id[i];
                send(network, message, server.socket, client.address);
            }
        }
    }

    update(server.game ref, delta_seconds);

    // prevent spikes when delta_seconds is very low
    var prediction_movement_scale f32;
    if delta_seconds >= 0.01
        prediction_movement_scale = (1 / delta_seconds);

    loop var a u32; server.client_count
    {
        var client = server.clients[a] ref;

        var client_name = server.users[client.user_index].name;

        var player_entity_index = client.entity_id.index_plus_one - 1;

        var player = get(game, client.entity_id);
        var player_network_id = game.network_id[player_entity_index];

        var do_update_player = game.do_update[player_entity_index];

        var movement = player.movement * prediction_movement_scale;
        var position = player.position;

        // HACK:
        player.movement = {} vec2;

        loop var b u32; server.client_count
        {
            var other = server.clients[b] ref;

            var entity = get(game, other.entity_id);
            assert(entity);

            if client.is_new
            {
                var message network_message_union;

                var other_name = server.users[other.user_index].name;

                // tell other about client
                message.tag = network_message_tag.add_player;
                message.add_player.entity_network_id = client.entity_network_id;
                message.add_player.name = client_name;
                message.add_player.name_color = client.name_color;
                message.add_player.body_color = client.body_color;
                send(network, message, server.socket, other.address);

                // tell client about other
                message.tag = network_message_tag.add_player;
                message.add_player.entity_network_id = other.entity_network_id;
                message.add_player.name = other_name;
                message.add_player.name_color = other.name_color;
                message.add_player.body_color = other.body_color;
                send(network, message, server.socket, client.address);
            }

            if client.broadcast_chat_message
            {
                var message network_message_union;
                message.tag = network_message_tag.chat;
                message.chat.id = client.entity_network_id;
                message.chat.text = client.chat_message;
                send(network, message, server.socket, other.address);
            }

            // send predicted player position
            if do_update_player
            {
                var entity = player deref;
                // predict future position on other depending on latency

                if true
                    entity.position += movement * ((client.latency_milliseconds + other.latency_milliseconds) / 1000.0);

                var message network_message_union;
                message.tag = network_message_tag.update_entity;
                message.update_entity.id     = player_network_id;
                message.update_entity.entity = entity;
                send(network, message, server.socket, client.address);
            }
        }

        loop var i u32; game.entity.count
        {
            if not game.active[i] or not game.do_update[i]
                continue;

            var entity = game.entity[i];

            if entity.tag is game_entity_tag.player
                continue;

            var message network_message_union;
            message.tag = network_message_tag.update_entity;
            message.update_entity.id     = game.network_id[i];
            message.update_entity.entity = entity;
            send(network, message, server.socket, client.address);
        }
    }

    def latency_checks_per_second = server_ticks_per_second * 0.25;
    server.latency_timeout -= delta_seconds * latency_checks_per_second;
    if server.latency_timeout <= 0
    {
        server.latency_timeout += 1.0;

        server.latency_id += 1;

        if server.latency_id is invalid_latency_id
            server.latency_id += 1;

        server.latency_timestamp_milliseconds = platform_local_timestamp_milliseconds(platform);

        var message network_message_union;
        message.tag = network_message_tag.latency;
        message.latency.latency_id  = server.latency_id;

        loop var a u32; server.client_count
        {
            var client = server.clients[a] ref;
            message.latency.latency_milliseconds = client.latency_milliseconds;
            send(network, message, server.socket, client.address);
        }
    }

    loop var a u32; server.client_count
    {
        var client = server.clients[a] ref;
        client.do_update = false;
        client.broadcast_chat_message = false;
        client.is_new = false;

        if client.fireball_cooldown > 0
            client.fireball_cooldown -= delta_seconds;
    }
}

func add_user(server game_server ref, name string63, password string63) (user game_user ref, user_index u32)
{
    if server.users.user_count >= server.users.count
        return null, 0;

    var user_index = server.users.user_count;
    server.users.user_count += 1;

    var user = server.users[user_index] ref;
    user deref = {} game_user;

    user.name     = name;
    user.password = password;

    network_print_info("Server: added user % %\n", to_string(name), user_index);

    return user, user_index;
}
