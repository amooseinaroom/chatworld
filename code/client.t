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
    
    id u32;
}

struct game_player
{
    position vec2;
    id       u32;
}

enum client_state
{
    disconnected;
    connected;
    online;
}

func init(client game_client ref, network platform_network ref)
{    
    client.socket = platform_network_bind(network);
    require(platform_network_is_valid(client.socket));
    print("Client Up and Running!\n");
    client.state = client_state.connected;    
    
    client.server_address.port = server_port;
    client.server_address.ip[0] = 127;
    client.server_address.ip[3] = 1;

    var records DNS_RECORD ref;
    var status = DnsQuery_A("band-hood.gl.at.ply.gg\0".base cast(cstring), DNS_TYPE_A, DNS_QUERY_STANDARD, null, records cast(u8 ref) ref, null);
    var iterator = records;
    while iterator
    {
        client.server_address.ip = iterator.Data.A.IpAddress ref cast(platform_network_ip ref) deref;
        break;
        iterator = iterator.pNext;
    }

    DnsRecordListFree(records, 0);
}

func tick(client game_client ref, network platform_network ref, delta_seconds f32)
{
    while true
    {
        var result = receive(network, client.socket);
        if not result.ok
            break;

        switch result.message.tag
        case network_message_tag.login
        {
            if client.state is client_state.connected
            {
                client.id    = result.message.login.id;
                client.state = client_state.online;

                // client player instance index is always 0
                client.player_count = 1;
                client.players[0].id = client.id;
            }
        }
        case network_message_tag.position
        {
            if client.state is_not client_state.online            
                break;            
            
            var message = result.message.position;
            
            var found_index = u32_invalid_index;
            loop var i u32; client.player_count
            {
                if client.players[i].id is message.id
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
                    break;
                }

                found_index = client.player_count;
                var player = client.players[found_index] ref;
                player deref = {} game_player;
                player.id = message.id;            
                client.player_count += 1;
            }

            var player = client.players[found_index] ref;
            player.position = message.position;
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

            
            send(network, message, client.socket, client.server_address);
            print("Client: reconnecting\n");
        }                
    }
    case client_state.online
    {
        if squared_length(client.frame_movement) is 0
            break;

        var message network_message_union;
        message.tag = network_message_tag.movement;
        message.movement.movement = client.frame_movement;
        message.movement.delta_seconds = client.frame_delta_seconds;
        
        send(network, message, client.socket, client.server_address);        
    }
}