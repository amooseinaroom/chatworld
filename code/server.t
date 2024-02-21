
struct game_server
{
    game game_state;

    socket platform_network_socket;

    users game_user_buffer;

    clients      game_client_connection[max_player_count];
    client_count u32;

    next_network_id u32;

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

    heartbeat_timeout      f32;
    missed_heartbeat_count u32;

    fireball_cooldown f32;

    chat_message           string255;
    broadcast_chat_message b8;
}

struct game_user
{
    name     string255;
    password string255;
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
    network_print("Server Up and Running!\n");

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
                                network_print("Server: rejected player, user is already logged in! % %\n", from_string255(message.name), result.address);
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
                    network_print("Server: rejected user, server users are full! %\n", result.address);
                    reject_reason = network_message_reject_reason.server_full_total_user;
                    break check_reject;
                }

                if (found_client_index is u32_invalid_index) and (server.client_count >= server.clients.count)
                {
                    network_print("Server: rejected player, game is full! %\n", result.address);
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

                    network_print("Server: added Client %\n", result.address);
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
            entity.movement += result.message.user_input.movement * result.message.user_input.delta_seconds;

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

        network_print("Server: GOTTEM! % %\n", result.message.tag, result.address);
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

            network_print("Server: Client % missed to many heartbeats and is considered MIA\n", client.address);
            remove(game, client.entity_id);
            server.client_count -= 1;
            server.clients[a] = server.clients[server.client_count];
            a -= 1; // repeat index
        }
    }

    loop var a u32; server.client_count
    {
        var client = server.clients[a] ref;

        var client_name = server.users[client.user_index].name;

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
        }

        loop var i u32; game.entity.count
        {
            if (not game.active[i])
                continue;

            if game.do_delete[i]
            {
                var message network_message_union;
                message.tag = network_message_tag.delete_entity;
                message.delete_entity.id = game.network_id[i];
                send(network, message, server.socket, client.address);
            }
            else if game.do_update[i]
            {
                var entity = game.entity[i];
                var message network_message_union;
                message.tag = network_message_tag.update_entity;
                message.update_entity.id     = game.network_id[i];
                message.update_entity.entity = entity;
                send(network, message, server.socket, client.address);
            }
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

func add_user(server game_server ref, name string255, password string255) (user game_user ref, user_index u32)
{
    if server.users.user_count >= server.users.count
        return null, 0;

    var user_index = server.users.user_count;
    server.users.user_count += 1;

    var user = server.users[user_index] ref;
    user deref = {} game_user;

    user.name     = name;
    user.password = password;

    network_print("Server: added user % %\n", from_string255(name), user_index);

    return user, user_index;
}
