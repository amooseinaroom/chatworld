import win32;

struct game_client
{
    game game_state;

    socket platform_network_socket;
    
    server_address platform_network_address;

    state client_state;
    reconnect_timeout f32;

    frame_input network_message_user_input;

    players      game_player[max_player_count];
    player_count u32;

    user_name_edit editable_text;
    user_name      string255;    
    
    user_password_edit editable_text;
    user_password      string255;    

    chat_message_edit editable_text;
    chat_message      string255;
    send_chat_message b8;
    
    entity_id game_entity_id;
    network_id u32;

    heartbeat_timeout f32;
}

struct game_player
{    
    entity_id         game_entity_id;
    entity_network_id u32;

    name string255;

    chat_message         string255;
    chat_message_timeout f32;
}

enum client_state
{
    disconnected;
    connected;
    online;
}

func init(client game_client ref, network platform_network ref, server_address platform_network_address)
{   
    if not platform_network_is_valid(client.socket)
    {
        client.socket = platform_network_bind(network);
        require(platform_network_is_valid(client.socket));
    }

    print("Client Up and Running!\n");
    client.state = client_state.connected;
    client.server_address = server_address;
}

func tick(client game_client ref, network platform_network ref, delta_seconds f32)
{
    var game = client.game ref;

    var reset_heartbeat = false;

    loop var i u32; client.player_count
    {
        if client.players[i].chat_message_timeout > 0
            client.players[i].chat_message_timeout -= delta_seconds * 0.1;
    }

    while true
    {
        var result = receive(network, client.socket);
        if not result.ok
            break;

        switch result.message.tag
        case network_message_tag.login_accept
        {
            if client.state is client_state.connected
            {
                client.network_id = result.message.login_accept.id;
                client.state = client_state.online;

                var entity_id = add_player(game, client.network_id);                
                client.player_count = 0;
                var player = find_player(client, entity_id);
                assert(player);
                player.name = client.user_name;
                player.entity_network_id = client.network_id;
            }
        }
        case network_message_tag.login_reject
        {
            client.state = client_state.disconnected;
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
                    player.name = message.name;
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

        print("Client: GOTTEM! % %\n", result.message.tag, result.address);
    }

    switch client.state
    case client_state.disconnected
    {

    }
    case client_state.connected
    {        
        client.reconnect_timeout -= delta_seconds;

        if client.reconnect_timeout <= 0
        {
            client.reconnect_timeout += 1.0;

            var message network_message_union;
            message.tag = network_message_tag.login;
            message.login.name     = client.user_name;
            message.login.password = client.user_password;
            
            send(network, message, client.socket, client.server_address);
            print("Client: reconnecting\n");
        }                
    }
    case client_state.online
    {
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
            print("Client: can't add more remote player\n");
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