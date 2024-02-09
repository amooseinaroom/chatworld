
struct game_server
{
    game game_state;

    socket platform_network_socket;

    expand user_buffer game_user_buffer;

    clients      game_client_connection[max_player_count];
    client_count u32;

    next_network_id u32;
}

struct game_client_connection
{
    address    platform_network_address;
    
    entity_id  game_entity_id;
    network_id u32;
    user_id    u32;
    do_update  b8;

    fireball_cooldown f32;

    chat_message           string255;
    broadcast_chat_message b8;
}

struct game_user
{
    name     string255;
    password string255;
}

struct game_user_buffer
{
    user_count u32;
    users      game_user[1 bit_shift_left 14];
}

def server_user_path = "server_users.bin";

func init(server game_server ref, platform platform_api ref, network platform_network ref, server_port u16, tmemory memory_arena ref)
{    
    server.socket = platform_network_bind(network, server_port);
    require(platform_network_is_valid(server.socket));
    print("Server Up and Running!\n");

    var result = try_platform_read_entire_file(platform, tmemory, server_user_path);
    if result.ok
    {
        var data = result.data;
        assert(data.count is type_byte_count(game_user_buffer));
        copy_bytes(server.user_buffer ref, data.base, data.count);
    }
}

func save(platform platform_api ref, server game_server ref)
{
    platform_write_entire_file(platform, server_user_path, value_to_u8_array(server.user_buffer));
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

        var found_index = u32_invalid_index;
        loop var i u32; server.client_count
        {
            if server.clients[i].address is result.address
            {
                found_index = i;
                break;
            }
        }

        var client game_client_connection ref;
        if (found_index is u32_invalid_index) and (result.message.tag is_not network_message_tag.login)
            continue;

        client = server.clients[found_index] ref;

        switch result.message.tag
        case network_message_tag.login
        {
            var message = result.message.login;

            var user_index = u32_invalid_index;
            var do_reject = false;
            loop var i u32; server.user_count
            {
                if server.users[i].name is message.name
                {
                    if server.users[i].password is_not message.password
                    {                        
                        do_reject = true;
                        break;
                    }

                    user_index = i;
                    break;
                }
            }            

            if not do_reject and (found_index is u32_invalid_index)
            {
                if server.client_count >= server.clients.count
                {
                    print("Server: rejected player, game is full! %\n", result.address);
                    do_reject = true;                    
                }
                else
                {
                    var is_loggind_in = false;
                    loop var i u32; server.client_count
                    {
                        if server.clients[i].user_id is user_index
                        {
                            is_loggind_in = true;
                            break;
                        }
                    }

                    if is_loggind_in
                    {
                        print("Server: rejected player, user is already logged in! %\n", result.address);
                        do_reject = true;                        
                    }
                    else
                    {
                        print("Server: added Client %\n", result.address);
                        found_index = server.client_count;
                        client = server.clients[found_index] ref;
                        client deref = {} game_client_connection;
                        client.address = result.address;

                        client.network_id = new_network_id(server);
                        client.entity_id = add_player(game, client.network_id);
                        server.client_count += 1;
                    }
                }
            }
                        
            if not do_reject and (user_index is u32_invalid_index)
            {
                if server.user_count >= server.users.count
                {
                    print("Server: rejected user, server users are full! %\n", result.address);
                    do_reject = true;                    
                }
                else
                {
                    user_index = server.user_count;
                    var user = server.users[user_index] ref;
                    server.user_count += 1;
                    user.name     = message.name;
                    user.password = message.password;
                    save(platform, server);
                }
            }
            
            if do_reject
            {
                var message network_message_union;
                message.tag = network_message_tag.login_reject;                        
                send(network, message, server.socket, result.address);                                     
            }
            else
            {
                client.user_id = user_index;
                
                var message network_message_union;
                message.tag = network_message_tag.login_accept;
                message.login_accept.id = client.network_id;
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
        case network_message_tag.chat
        {
            client.chat_message = result.message.chat.text;
            client.broadcast_chat_message = true;
        }
        
        print("Server: GOTTEM! % %\n", result.message.tag, result.address);
    }

    loop var a u32; server.client_count
    {
        var client = server.clients[a] ref;

        loop var b u32; server.client_count
        {
            var other = server.clients[b] ref;

            var entity = get(game, other.entity_id);
            assert(entity);

            if client.broadcast_chat_message
            {
                var message network_message_union;
                message.tag = network_message_tag.chat;
                message.chat.id = client.network_id;
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

        if client.fireball_cooldown > 0
            client.fireball_cooldown -= delta_seconds;
    }
}
