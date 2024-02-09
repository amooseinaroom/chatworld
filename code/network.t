
def default_server_port = 50881 cast(u16); // 18124 cast(u16); //51337 cast(u16);

def max_player_count = 4;

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

func is(left string255, right string255) (ok b8)
{
    return from_string255(left) is from_string255(right);
}

func is_not(left string255, right string255) (ok b8)
{
    return from_string255(left) is_not from_string255(right);
}

enum network_message_tag
{
    login;
    login_accept;
    login_reject;
    user_input;    
    update_entity;
    delete_entity;
    chat;
}

struct network_message_base
{
    tag network_message_tag;
}

struct network_message_login
{
    expand base network_message_base;

    name     string255;
    password string255;
}

struct network_message_login_accept
{
    expand base network_message_base;

    id u32;
}

struct network_message_login_reject
{
    expand base network_message_base;
}

struct network_message_user_input
{
    expand base network_message_base;

    movement      vec2;
    delta_seconds f32;
    do_attack     b8;
}

struct network_message_update_entity
{
    expand base network_message_base;

    id     u32;
    entity game_entity;
}

struct network_message_delete_entity
{
    expand base network_message_base;

    id     u32; 
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

    login         network_message_login;
    login_accept  network_message_login_accept;
    login_reject  network_message_login_reject;
    user_input    network_message_user_input;    
    update_entity network_message_update_entity;
    delete_entity network_message_delete_entity;
    chat          network_message_chat;
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