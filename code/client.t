import win32;

struct game_client
{
    socket platform_network_socket;
    
    server_address platform_network_address;

    state client_state;
    reconnect_timeout f32;

    frame_movement vec2;
    frame_delta_seconds f32;

    players      game_player[max_player_count];
    player_count u32;

    user_name_edit editable_text;
    user_name      string255;    
    
    user_password_edit editable_text;
    user_password      string255;    

    chat_message_edit editable_text;
    chat_message      string255;
    send_chat_message b8;
    
    id u32;
}

struct game_player
{
    position vec2;
    id       u32;

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
                client.id    = result.message.login_accept.id;
                client.state = client_state.online;

                // client player instance index is always 0
                client.player_count = 1;
                client.players[0].id = client.id;
            }
        }
        case network_message_tag.login_reject
        {
            client.state = client_state.disconnected;

        }
        case network_message_tag.position
        {
            if client.state is_not client_state.online            
                break;            
            
            var message = result.message.position;
            var player = find_player(client, message.id);            
            player.position = message.position;
        }
        case network_message_tag.chat
        {
            if client.state is_not client_state.online            
                break;            
            
            var message = result.message.chat;
            var player = find_player(client, message.id);            
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
        if squared_length(client.frame_movement) > 0
        {
            var message network_message_union;
            message.tag = network_message_tag.movement;
            message.movement.movement = client.frame_movement;
            message.movement.delta_seconds = client.frame_delta_seconds;            
            send(network, message, client.socket, client.server_address);
        }

        if client.send_chat_message
        {
            var message network_message_union;
            message.tag = network_message_tag.chat;
            message.chat.text = client.chat_message;
            send(network, message, client.socket, client.server_address);   
        }
    }

    client.send_chat_message = false;
}

func find_player(client game_client ref, id u32) (player game_player ref)
{
    var found_index = u32_invalid_index;
    loop var i u32; client.player_count
    {
        if client.players[i].id is id
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
        player.id = id;            
        client.player_count += 1;
    }

    return client.players[found_index] ref;
}