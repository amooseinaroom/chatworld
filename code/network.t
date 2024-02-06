
def server_port = 18124 cast(u16); //51337 cast(u16);

def max_player_count = 4;

struct game_server
{
    socket platform_network_socket;

    clients      game_client_connection[max_player_count];
    client_count u32;

    next_id u32;
}

struct game_client_connection
{
    address   platform_network_address;
    position  vec2;
    id        u32;
    do_update b8;

    chat_message           string255;
    broadcast_chat_message b8;
}

func init(server game_server ref, network platform_network ref)
{    
    server.socket = platform_network_bind(network, server_port);
    require(platform_network_is_valid(server.socket));
    print("Server Up and Running!\n");
}

func tick(server game_server ref, network platform_network ref)
{
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
            if found_index is u32_invalid_index
            {
                if server.client_count >= server.clients.count
                {
                    print("Server: rejected player, game is full! %\n", result.address);
                    break;
                }

                print("Server: added Client %\n", result.address);
                found_index = server.client_count;
                client = server.clients[found_index] ref;
                client deref = {} game_client_connection;
                client.address = result.address;
                server.next_id += 1;
                assert(server.next_id);

                client.id = server.next_id;
                server.client_count += 1;
            }

            var message network_message_union;
            message.tag = network_message_tag.login;
            message.login.id = client.id;
            send(network, message, server.socket, client.address);
        }
        case network_message_tag.movement
        {
            client.position += result.message.movement.movement * result.message.movement.delta_seconds;
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
            if not other.do_update
                continue;

            var message network_message_union;
            message.tag = network_message_tag.position;
            message.position.id = other.id;
            message.position.position = other.position;
            send(network, message, server.socket, client.address);
        }

        if client.broadcast_chat_message
        {
            var message network_message_union;
            message.tag = network_message_tag.chat;
            message.chat.id = client.id;
            message.chat.text = client.chat_message;
            send(network, message, server.socket, client.address);
        }
    }

    loop var a u32; server.client_count
    {
        var client = server.clients[a] ref;
        client.do_update = false;
        client.broadcast_chat_message = false;
    }
}

struct string255
{
    count       u8;
    expand base u8[255];
}

func to_string255(text string) (result string255)
{    
    var result string255;
    assert(text.count <= result.base.count);
    copy_array({ text.count, result.base.base } u8[], text);
    result.count = text.count cast(u8);
    
    return result;
}

func from_string255(text string255) (result string)
{
    return { text.count, text.base.base } string;
}

enum network_message_tag
{
    login;
    movement;
    position;
    chat;
}

struct network_message_base
{
    tag network_message_tag;
}

struct network_message_login
{
    expand base network_message_base;

    id u32;
}

struct network_message_movement
{
    expand base network_message_base;

    movement      vec2;
    delta_seconds f32;
}

struct network_message_position
{
    expand base network_message_base;

    id       u32;
    position vec2;    
}

struct network_message_chat
{
    expand base network_message_base;
    
    text string255;
    id   u32;
}

type network_message_union union
{
    expand base network_message_base;
    
    login    network_message_login;
    movement network_message_movement;
    position network_message_position;
    chat     network_message_chat;
};

func send(network platform_network ref, message network_message_union, send_socket platform_network_socket, address = {} platform_network_address)
{
    var data = value_to_u8_array(message);
    var ok = platform_network_send(network, send_socket, address, data, platform_network_timeout_milliseconds_zero);
    assert(ok);
}

func receive(network platform_network ref, receive_socket platform_network_socket) (ok b8, message network_message_union, address platform_network_address)
{
    var message network_message_union;
    var buffer = value_to_u8_array(message);
    var buffer_used_byte_count usize;
    var result = platform_network_receive(network, receive_socket, buffer, buffer_used_byte_count ref, platform_network_timeout_milliseconds_zero);
    assert(result.ok);

    if buffer_used_byte_count is_not type_byte_count(network_message_union)
        return false, message, {} platform_network_address;

    if message.tag >= network_message_tag.count
        return false, message, {} platform_network_address;

    return buffer_used_byte_count > 0, message, result.address;
}