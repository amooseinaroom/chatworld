
import platform;
import memory;
import network;
import meta;
import string;

override def enable_network_print = true;

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

def ticks_per_second = 30;
def seconds_per_tick = 1.0 / ticks_per_second;

var server = program.server ref;
var game = server.game ref;

init(game, platform ref, memory ref);

var server_address platform_network_address;
server_address.port = default_server_port;
server_address.ip[0] = 127;
server_address.ip[3] = 1;
server_address = load_server_address(platform ref, network, memory ref, server_address);

init(server, platform ref, network, server_address.port, memory ref);

// skip init time
platform_update_time(platform ref);

while platform_handle_messages(platform ref)
{
    tick(platform ref, server, network, platform.delta_seconds);
    update(game, platform.delta_seconds);

    var sleep_seconds = maximum(0, seconds_per_tick - platform.delta_seconds);

    // sleep 5 minutes
    var sleep_milliseconds = (sleep_seconds * 1000) cast(u32);
    if sleep_milliseconds > 0
        platform_sleep_milliseconds(platform ref, sleep_milliseconds);
}

platform_network_shutdown(network);
network_print("server shutdown\n");