
import platform;
import memory;
import network;
import meta;
import string;

override def enable_network_print = true;
override def network_print_max_level = network_print_level.info;

// for some shared files that use this value
// server_main does not include hot_reloading files
def enable_hot_reloading = false;

struct server_program
{
    network platform_network;
    server  game_server;
}

var platform platform_api;
platform_init(platform ref);

var memory memory_arena;
init(memory ref);

platform_enable_console();

var program server_program ref;
allocate(memory ref, program ref);

var network = program.network ref;
platform_network_init(network);

var server = program.server ref;
var game = server.game ref;

update_game_version(platform ref, memory ref);

var server_address platform_network_address;
server_address.port = default_server_port;
server_address.ip[0] = 127;
server_address.ip[3] = 1;
server_address = load_server_address(platform ref, network, memory ref, server_address);

init(server, platform ref, network, server_address.port, memory ref);

{
    var it = try_platform_read_entire_file(platform ref, memory ref, "server_new_admins.txt").data;
    skip_space(it ref);

    while (it.count)
    {
        var ok = try_skip(it ref, "admin "); // COMPILER_BUG: does not escape quotes in get_call_argument_text
        require(ok);
        skip_space(it ref);

        var name = to_string63(skip_name(it ref));
        require(name.count);
        skip_space(it ref);

        var password = to_string63(try_skip_until_set(it ref, " \n\t\r", true));
        require(password.count);
        skip_space(it ref);

        var found = false;
        loop var i u32; server.users.user_count
        {
            if server.users[i].name is name
            {
                require(server.users[i].password is password);
                found = true;
                server.users[i].is_admin = true;
                break;
            }
        }

        if not found
        {
            var user = add_user(server, name, password).user;
            require(user);
            user.is_admin = true;
        }
    }

    save(platform ref, server);
}

// skip init time
platform_update_time(platform ref);

while platform_handle_messages(platform ref)
{
    tick(platform ref, server, network, platform.delta_seconds);

    if server.do_shutdown
        break;

    var sleep_seconds = maximum(0, server_seconds_per_tick - platform.delta_seconds);
    var sleep_milliseconds = (sleep_seconds * 1000) cast(u32);
    if sleep_milliseconds > 0
        platform_sleep_milliseconds(platform ref, sleep_milliseconds);
}

// disconnect all clients
loop var i u32; server.client_count
{
    var message network_message_union;
    message.tag = network_message_tag.login_reject;
    message.login_reject.reason = network_message_reject_reason.server_disconnect;
    send(network, message, server.socket, server.clients[i].address);
}

platform_network_shutdown(network);
network_print("Server: shutdown.\n");