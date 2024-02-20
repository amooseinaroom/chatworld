
import platform;
import memory;
import network;
import meta;
import string;

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

init(game);

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

struct peer_buffer
{
    expand base       peer_info[256];
           used_count u32;
}

struct peer_info
{
    expand address         platform_network_address;
           timestamp       u64;
           did_change      b8;
           test_range_offset u16;
}

struct network_message
{
    active_peer_address platform_network_address;
}

func update_peer(peers peer_buffer ref, address platform_network_address)
{
    if not address.ip.u32_value
        return;

    var found = false;
    loop var i u32; peers.used_count
    {
        var peer = peers[i] ref;
        if peer.ip.u32_value is address.ip.u32_value
        {
            if address.port
            {
                peer.did_change = (peer.port is_not address.port);
                peer.port = address.port;
            }

            found = true;
            break;
        }
    }

    if not found and (peers.used_count < peers.count)
    {
        var peer = peers[peers.used_count] ref;
        peers.used_count += 1;

        peer.address = address;
        peer.did_change = (address.port is_not 0);
    }
}
