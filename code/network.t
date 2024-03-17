
def default_server_port = 50881 cast(u16); // 18124 cast(u16); //51337 cast(u16);

def server_ticks_per_second = 30;
def server_seconds_per_tick = 1.0 / server_ticks_per_second;

def heartbeat_period = 5.0;
def heartbeats_per_seconds = 1.0 / heartbeat_period;
def max_missed_heartbeats = 2;

def max_player_count = 256;

def enable_network_print    = true;
def network_print_max_level = network_print_level.crucial;
// def network_print_max_level = network_print_level.count;

enum network_print_level
{
    crucial;
    info;
    verbose;
}

// essentially network_print_crucial
func network_print print_type
{
    if enable_network_print
        print_line(format, values);
}

func network_print_info print_type
{
    if enable_network_print and (network_print_level.info <= network_print_max_level)
        print_line(format, values);
}

func network_print_verbose print_type
{
    if enable_network_print and (network_print_level.verbose <= network_print_max_level)
        print_line(format, values);
}

enum network_message_tag u8
{
    invalid;
    acknowledge;
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
    update_player_tent;
    chat;

    capture_the_flag_started;
    capture_the_flag_score;
    capture_the_flag_ended;
    capture_the_flag_player_team;

    admin_server_shutdown;
}

// messages with other ids need to be acknowledged
def network_acknowledge_message_id_invalid = 0 cast(u16);

struct network_message_base
{
    tag                    network_message_tag;
    acknowledge_message_id u16;
}

type network_message_acknowledge network_message_base;

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

    player_entity_network_id game_entity_network_id;

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

    movement    vec2;
    do_interact b8;
    do_attack   b8;
    do_magic    b8;
}

struct network_message_add_player
{
    expand base network_message_base;

    name              string63;
    name_color        rgba8;
    body_color        rgba8;

    entity_network_id game_entity_network_id;
}

struct network_message_remove_player
{
    expand base network_message_base;

    entity_network_id game_entity_network_id;
}

struct network_message_update_entity
{
    expand base network_message_base;

    entity     game_entity;
    network_id game_entity_network_id;
    tag        game_entity_tag;
}

struct network_message_update_player_tent
{
    expand base network_message_base;

    entity_network_id game_entity_network_id;
    player_tent       game_entity_player_tent;
}

struct network_message_delete_entity
{
    expand base network_message_base;

    network_id game_entity_network_id;
}

struct network_message_chat_text
{
    text string255;
    is_shouting b8;
}

struct network_message_chat
{
    expand base network_message_base;

    player_entity_network_id game_entity_network_id;

    text network_message_chat_text;
}

struct network_message_capture_the_flag_score
{
    expand base network_message_base;

    running_id u32;
    play_time  f32;
    team_index u32;
    score      u32;
}

struct network_message_capture_the_flag_player_team
{
    expand base network_message_base;

    entity_network_id   game_entity_network_id;
    team_index_plus_one u32;
    team_color          rgba8;
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
    update_player_tent network_message_update_player_tent;
    delete_entity network_message_delete_entity;
    chat          network_message_chat;

    capture_the_flag_score       network_message_capture_the_flag_score;
    capture_the_flag_player_team network_message_capture_the_flag_player_team;
};

var global test_network_send_buffer network_send_buffer;
var global test_compress_zero_buffer compress_zero_buffer;

func receive(network platform_network ref, receive_socket platform_network_socket, buffer u8[]) (do_continue b8, has_message b8, address platform_network_address, iterator u8[])
{
    var buffer_used_byte_count usize;

    // COMPILER BUG: deref fixed size array and auto cast to dynamic size array
    // casting u8[512] ref to u8[] or rather accesing .base does not use '->'
    var result = platform_network_receive(network, receive_socket, buffer, buffer_used_byte_count ref, platform_network_timeout_milliseconds_zero);
    network_assert(result.result is platform_network_result.ok);

    if not buffer_used_byte_count
        return result.has_data, false, {} platform_network_address, {} u8[];

    var iterator = { buffer_used_byte_count, buffer.base } u8[];
    return result.has_data, true, result.address, iterator;
}

func next_message(message network_message_union ref, iterator u8[] ref) (ok b8)
{
    if not iterator.count
        return false;

    var decompress_result = decompress_repeat(value_to_u8_array(message deref), iterator);
    if not decompress_result.ok
        return false;

    if decompress_result.byte_count is_not type_byte_count(network_message_union)
        return false;

    if message.tag >= network_message_tag.count
        return false;

    return true;
}

def network_max_packet_size = 512 cast(u32);

struct network_send_buffer
{
    expand base       u8[network_max_packet_size];

    compress_state compress_repeat_state;

    packet_count            u32;
    byte_count              u32;
    compressed_packet_count u32;
    compressed_byte_count   u32;

    repeat_count_by_byte u8[256];
}

func send(network platform_network ref, send_socket platform_network_socket, address platform_network_address, buffer network_send_buffer ref, data u8[]) (result platform_network_result)
{
    network_assert(data.count);

    {
        var state compress_repeat_state;
        var buffer u8[network_max_packet_size];
        compress_next(state ref, buffer, data);
        var byte_count = compress_end(state ref, buffer);

        var iterator = { byte_count, buffer.base } u8[];
        var debuffer u8[network_max_packet_size];
        var result = decompress_repeat(debuffer, iterator ref);
        assert(result.ok);
        var dedata = { result.byte_count, debuffer.base } u8[];
        assert(data is dedata);

        dedata = {} u8[];
    }

    if not compress_next(buffer.compress_state ref, buffer.base, data)
    {
        var result = compress_end_and_send(network, send_socket, address, buffer);
        if result is_not platform_network_result.ok
            return result;

        var ok = compress_next(buffer.compress_state ref, buffer.base, data);
        network_assert(ok);
    }

    buffer.packet_count += 1;
    buffer.byte_count   += data.count cast(u32);

    return platform_network_result.ok;
}

func send_flush(network platform_network ref, send_socket platform_network_socket, address platform_network_address, buffer network_send_buffer ref) (result platform_network_result)
{
    var result = platform_network_result.ok;
    if buffer.compress_state.used_byte_count or buffer.compress_state.repeat_count
        result = compress_end_and_send(network, send_socket, address, buffer);

    return result;
}

func compress_end_and_send(network platform_network ref, send_socket platform_network_socket, address platform_network_address, buffer network_send_buffer ref) (result platform_network_result)
{
    assert(buffer.compress_state.used_byte_count or buffer.compress_state.repeat_count);

    var byte_count = compress_end(buffer.compress_state ref, buffer.base);
    network_assert(byte_count);
    var result = platform_network_send(network, send_socket, address, { byte_count, buffer.base.base } u8[], platform_network_timeout_milliseconds_zero);

    buffer.compressed_packet_count += 1;
    buffer.compressed_byte_count   += byte_count;

    return result;
}

func send(network platform_network ref, send_socket platform_network_socket, address platform_network_address, buffer network_send_buffer ref, message network_message_union) (result platform_network_result)
{
    return send(network, send_socket, address, buffer, value_to_u8_array(message));
}

type game_user_sprite rgba8[256 * 128];

func load_server_address(platform platform_api ref, network platform_network ref, tmemory memory_arena ref, default_address platform_network_address) (address platform_network_address)
{
    var address = default_address;

    var source = platform_read_entire_file(platform, tmemory, "server.txt");

    var dns string;
    var parsed_address platform_network_address;
    var parsed_address_ok = false;

    var it = source;
    skip_space(it ref);
    while it.count
    {
        if not try_skip(it ref, "server")
            network_assert(false);

        skip_space(it ref);

        if try_skip(it ref, "ip")
        {
            skip_space(it ref);

            var ip_text = try_skip_until_set(it ref, " \t\n\r");

            var ok = true;

            {
                var ip_it = ip_text;
                // try ip v4 first
                loop var i u32; 4
                {
                    var value u32;
                    if not try_parse_u32(value ref, ip_it ref) or (value > 255)
                    {
                        ok = false;
                        break;
                    }

                    parsed_address.ip_v4[i] = value cast(u8);

                    if (i < 3) and not try_skip(ip_it ref, ".")
                    {
                        ok = false;
                        break;
                    }
                }

                if ok
                    parsed_address.tag = platform_network_address_tag.ip_v4;
            }

            // try ip v6
            // we do not except shortened names
            if not ok
            {
                var ip_it = ip_text;

                ok = true;
                var pairs u16[8];
                loop var pair; 8
                {
                    var value u32;
                    if not try_parse_u32(value ref, ip_it ref, 16) or (value > 0xffff)
                    {
                        ok = false;
                        break;
                    }

                    if (pair < 7) and not try_skip(ip_it ref, ":")
                    {
                        ok = false;
                        break;
                    }

                    pairs[pair] = value cast(u16);
                }

                if ok
                {
                    parsed_address.tag = platform_network_address_tag.ip_v6;
                    parsed_address.ip_v6 = pairs ref cast(platform_network_ip_v6 ref) deref;
                }
            }

            parsed_address_ok = ok;

            skip_space(it ref);
        }
        else if try_skip(it ref, "dns")
        {
            skip_space(it ref);
            dns = try_skip_until_set(it ref, " \t\n\r");
            network_assert(dns.count);
        }
        else
            network_assert(false);

        var port u32;
        if not try_parse_u32(port ref, it ref) or (port > 65535)
            network_assert(false);

        parsed_address.port = port cast(u16);

        skip_space(it ref);
        break;
    }

    if dns.count
    {
        var result = platform_network_query_dns(network, dns);
        if result.ok
            address = result.address;
    }
    else if parsed_address_ok
    {
        address = parsed_address;
    }

    address.port = parsed_address.port;

    return address;
}

// overridden in server
func network_assert assert_type
{
    assert(condition_text, condition, location, format, arguments);
}