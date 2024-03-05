
import platform;
import memory;
import network;
import meta;
import string;

override def enable_network_print = true;
// override def network_print_max_level = network_print_level.info;

// for some shared files that use this value
// server_main does not include hot_reloading files
def enable_hot_reloading = false;

var global global_plaform platform_api ref;
var global global_memory  memory_arena ref;
var global global_program server_program ref;

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

// we have a window without using it, so we can see the server is actually running
// and close the window to shut it down properly
var window platform_window;
platform_window_init(platform ref, window ref, "chatworld server", 640, 480);

var program server_program ref;
allocate(memory ref, program ref);

global_plaform = platform ref;
global_memory  = memory ref;
global_program = program;

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
    platform_window_frame(platform ref, window ref);

    tick(platform ref, server, network, platform.delta_seconds);

    if server.do_shutdown or window.do_close
        break;

    var sleep_seconds = maximum(0, server_seconds_per_tick - platform.delta_seconds);
    var sleep_milliseconds = (sleep_seconds * 1000) cast(u32);
    if sleep_milliseconds > 0
        platform_sleep_milliseconds(platform ref, sleep_milliseconds);
}

shutdown(server, network);

{
    var buffer = test_network_send_buffer;
    loop var i; 256
    {
        print("byte: %, count: %\n", i, buffer.repeat_count_by_byte[i]);
    }
}

// end of main

func shutdown(server game_server ref, network platform_network ref)
{
    // disconnect all clients
    var client game_client_connection ref;
    while next_client(server, client ref)
    {
        var message network_message_union;
        message.tag = network_message_tag.login_reject;
        message.login_reject.reason = network_message_reject_reason.server_disconnect;
        send(network, server, client, message);
        send_flush(network, server, client);
    }

    platform_network_shutdown(network);
    network_print("Server: shutdown.\n");
}

override func network_assert assert_type
{
    if lang_debug
    {
        assert(condition_text, condition, location, format, arguments);
    }
    else if not condition
    {
        var text string;
        write(global_memory, text ref, "Assertion: %/%\n%(%,%):\n", location.module, location.function, location.file, location.line, location.column);
        write(global_memory, text ref, "Assertion: \"%\" failed.\n", condition_text);
        write(global_memory, text ref, format, arguments);
        platform_write_entire_file(global_plaform, "server_crash.txt", text);

        shutdown(global_program.server ref, global_program.network ref);
        platform_exit(0);
    }
}
