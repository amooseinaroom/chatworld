
def default_server_port = 50881 cast(u16); // 18124 cast(u16); //51337 cast(u16);

def server_ticks_per_second = 30;
def server_seconds_per_tick = 1.0 / server_ticks_per_second;

def heartbeat_period = 5.0;
def heartbeats_per_seconds = 1.0 / heartbeat_period;
def max_missed_heartbeats = 2;

def max_player_count = 256;

def enable_network_print    = true;
def network_print_max_level = network_print_level.crucial;

enum network_print_level
{
    crucial;
    info;
}

// essentially network_print_crucial
func network_print print_type
{
    if enable_network_print
        print(format, values);
}

func network_print_info print_type
{
    if enable_network_print and (network_print_level.info <= network_print_max_level)
        print(format, values);
}

enum network_message_tag
{
    login;
    login_accept;
    login_reject;
    heartbeat;
    latency;
    user_input;
    add_player;
    remove_player;
    update_entity;
    delete_entity;
    chat;

    admin_server_shutdown;
}

struct network_message_base
{
    tag network_message_tag;
}

struct network_message_login
{
    expand base network_message_base;

    name      string63;
    password  string63;

    name_color rgba8;
    body_color rgba8;

    client_version u32;
}

struct network_message_login_accept
{
    expand base network_message_base;

    id u32;

    is_admin b8;
}

enum network_message_reject_reason
{
    none;
    version_missmatch;
    credential_missmatch;
    duplicated_user_login;
    server_full_active_player;
    server_full_total_user;
    server_disconnect;
    server_kick; // essentially the same as disconnect
}

struct network_message_login_reject
{
    expand base network_message_base;

    reason network_message_reject_reason;
}

type network_message_heartbeat network_message_base;

struct network_message_latency
{
    expand base network_message_base;

    latency_id           u32;
    latency_milliseconds u32; // server computed
}

def invalid_latency_id = 0 cast(u32);

struct network_message_user_input
{
    expand base network_message_base;

    movement  vec2;
    do_attack b8;
}

struct network_message_add_player
{
    expand base network_message_base;

    name              string63;
    name_color        rgba8;
    body_color        rgba8;

    entity_network_id u32;
}

struct network_message_remove_player
{
    expand base network_message_base;
    entity_network_id u32;
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
    heartbeat     network_message_heartbeat;
    latency       network_message_latency;
    user_input    network_message_user_input;
    add_player    network_message_add_player;
    remove_player network_message_remove_player;
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

    // we don't have connections that could fail, but win32 will indicate if a udp "connection" is lost running locally
    if not result.ok
        return false, message, {} platform_network_address;

    if buffer_used_byte_count is_not type_byte_count(network_message_union)
        return false, message, {} platform_network_address;

    if message.tag >= network_message_tag.count
        return false, message, {} platform_network_address;

    return buffer_used_byte_count > 0, message, result.address;
}

type game_user_sprite rgba8[256 * 128];


func load_server_address(platform platform_api ref, network platform_network ref, tmemory memory_arena ref, default_address platform_network_address) (address platform_network_address)
{
    var address = default_address;

    var source = platform_read_entire_file(platform, tmemory, "server.txt");

    var dns string;
    var server_ip = address.ip;
    var port      = address.port;

    var it = source;
    skip_space(it ref);
    while it.count
    {
        if not try_skip(it ref, "server")
            assert(false);

        skip_space(it ref);

        if try_skip(it ref, "ip")
        {
            skip_space(it ref);

            loop var i u32; 4
            {
                var value u32;
                if not try_parse_u32(value ref, it ref) or (value > 255)
                    assert(false);

                server_ip[i] = value cast(u8);

                if (i < 3) and not try_skip(it ref, ".")
                    assert(false);
            }

            skip_space(it ref);
        }
        else if try_skip(it ref, "dns")
        {
            skip_space(it ref);
            dns = try_skip_until_set(it ref, " \t\n\r");
            assert(dns.count);
        }
        else
            assert(false);

        if not try_parse_u32(port ref, it ref) or (port > 65535)
            assert(false);

        skip_space(it ref);
        break;
    }

    address.port = port cast(u16);

    if dns.count
    {
        var result = platform_network_query_dns_ip(network, dns);
        if result.ok
            address.ip = result.ip;
    }
    else
    {
        address.ip = server_ip;
    }

    return address;
}

func skip_space(iterator string ref)
{
    try_skip_set(iterator, " \t\n\r");
}

func skip_name(iterator string ref) (name string)
{
    var name_blacklist = " \t\n\r\\\"\'+-*/.,:;~{}[]()<>|&!?=^°%";
    var name = try_skip_until_set(iterator, name_blacklist, false);
    return name;
}

func network_assert assert_type
{
    assert(condition_text, condition, location, format, arguments);
}