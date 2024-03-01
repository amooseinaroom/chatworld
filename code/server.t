
def max_user_knockdown_time = 10 * 60.0; // 10 minutes
// def max_user_knockdown_time = 30.0; // 30 sec

def enable_server_movement_prediction = true;
def server_max_prediction_seconds = server_seconds_per_tick * 0.5;

struct game_server
{
    game game_state;

    capture_the_flag capture_the_flag_state;

    random random_pcg;

    socket platform_network_socket;

    users game_user_buffer_extended;

    clients      game_client_connection[max_player_count];
    client_count u32;

    pending_messages server_pending_network_message_buffer;

    next_network_id game_entity_network_id;

    // store last couple latencies to help with high latency clients
    latency_pairs      server_latency_pair[4];
    latency_pair_index u32;
    latency_timeout    f32;

    chicken_spawn_timeout f32;

    do_shutdown b8;
}

def capture_the_flag_event_timeout  = 10.0; // 15 * 60.0;
def capture_the_flag_event_duration = 20.0; //  5 * 60.0;

struct capture_the_flag_state
{
    // by team id
    player_count   u32[2];
    score          u32[2];
    flag_position  vec2[2];
    flag_target_id game_entity_id[2]; 
    flag_id        game_entity_id[2];
    
    play_time  f32;
    running_id u32;
    is_running b8;
}

struct server_latency_pair
{
    id                     u32;
    timestamp_milliseconds u64;
}

struct game_client_connection
{
    address    platform_network_address;

    name_color rgba8;
    body_color rgba8;

    entity_id         game_entity_id;
    entity_network_id game_entity_network_id;
    user_index    u32;
    do_update  b8;
    is_new     b8;
    do_remove  b8;

    capture_the_flag_team_index u32;

    latency_milliseconds u32;

    heartbeat_timeout      f32;
    missed_heartbeat_count u32;

    chat_message           network_message_chat_text;
    broadcast_chat_message b8;
}

struct game_user
{
    name     string63;
    password string63;
    is_admin b8;
}

// active user data that does not need to be stored
struct game_user_extended
{
    knockdown_timeout f32;
    is_knockdowned    b8;

    shout_exhaustion   f32;
    is_shout_exhausted b8;

    fireball_cooldown f32;

    position vec2;
    health   s32;

    tent_id game_entity_id;
}

def max_server_user_count = 1 cast(u32) bit_shift_left 14;

struct game_user_buffer
{
           user_count  u32;
    expand base        game_user[max_server_user_count];
}

struct game_user_buffer_extended
{
    expand base           game_user_buffer;
           extended_users game_user_extended[max_server_user_count];
}

struct server_pending_network_message
{
    expand base    network_message_union;
    client_mask    u64[(max_player_count + 63) / 64];
    resend_timeout f32;
}

struct server_pending_network_message_buffer
{
    expand base                        server_pending_network_message[2048];
           used_count                  u32;
           next_acknowledge_message_id u16;
}

func queue(server game_server ref, message network_message_union)
{
    var buffer = server.pending_messages ref;
    network_assert(buffer.used_count < buffer.count);

    var pending_message = buffer[buffer.used_count] ref;
    buffer.used_count += 1;
    pending_message deref = {} server_pending_network_message;

    buffer.next_acknowledge_message_id += 1;
    if buffer.next_acknowledge_message_id is network_acknowledge_message_id_invalid
        buffer.next_acknowledge_message_id += 1;

    pending_message.base = message;
    pending_message.base.acknowledge_message_id = buffer.next_acknowledge_message_id;

    loop var client_index u32; server.client_count
    {
        var slot = client_index / 64;
        var bit  = client_index mod 64;
        pending_message.client_mask[slot] bit_or = bit64(bit);
    }
}


def server_user_path = "server_users.bin";

def capture_the_flag_team_colors =
[
    [ 255, 0, 0, 128   ] rgba8,
    [   0, 0, 255, 128 ] rgba8
] rgba8[];

func init(server game_server ref, platform platform_api ref, network platform_network ref, server_port u16, tmemory memory_arena ref)
{
    server.socket = platform_network_bind(network, server_port);
    network_assert(platform_network_is_valid(server.socket));
    network_print("Server: started. version: %, port: %, print level: %, debug: %\n", game_version, server_port, network_print_max_level, lang_debug);

    var result = try_platform_read_entire_file(platform, tmemory, server_user_path);
    if result.ok
    {
        var data = result.data;
        if data.count is type_byte_count(game_user_buffer)
            copy_bytes(server.users.base ref, data.base, data.count);
    }

    init(server.game ref, platform_get_random_from_time(platform));

    // init all health
    loop var i u32; server.users.count
        server.users.extended_users[i].health = player_max_health;    

    server.capture_the_flag.flag_position[0] = [ 15.5, 15.5 ] vec2;
    server.capture_the_flag.flag_position[1] = [ 45.5, 15.5 ] vec2;
    
    loop var i u32; 2
    {
        server.capture_the_flag.flag_target_id[i] = add_flag_target(server.game ref, new_network_id(server), server.capture_the_flag.flag_position[i], i, capture_the_flag_team_colors[i]);

        var sign = i cast(f32) * 2 - 1;
        add_healing_altar(server.game ref, new_network_id(server), [ 5, 5 ] vec2 * sign + server.capture_the_flag.flag_position[i]);
    }
}

func save(platform platform_api ref, server game_server ref)
{
    platform_write_entire_file(platform, server_user_path, value_to_u8_array(server.users.base));
}

func new_network_id(server game_server ref) (id game_entity_network_id)
{
    server.next_network_id.value += 1;

    if not server.next_network_id.value
        server.next_network_id.value += 1;

    return server.next_network_id;
}

func tick(platform platform_api ref, server game_server ref, network platform_network ref, delta_seconds f32)
{
    var game = server.game ref;

    var timestamp_milliseconds = platform_local_timestamp_milliseconds(platform);

    while true
    {
        var result = receive(network, server.socket);
        if not result.ok
            break;

        var found_client_index = u32_invalid_index;
        loop var i u32; server.client_count
        {
            if server.clients[i].address is result.address
            {
                found_client_index = i;
                break;
            }
        }

        var client game_client_connection ref;
        if (found_client_index is u32_invalid_index) and (result.message.tag is_not network_message_tag.login)
            continue;

        if found_client_index is_not u32_invalid_index
            client = server.clients[found_client_index] ref;

        if client and client.do_remove
            continue;

        switch result.message.tag
        case network_message_tag.acknowledge
        {
            var acknowledge_message_id = result.message.acknowledge_message_id;
            network_print("Server: got acknowledge % [%]", result.message.tag, acknowledge_message_id);

            var buffer = server.pending_messages ref;
            loop var message_index u32; buffer.used_count
            {
                var message = buffer[message_index] ref;
                if message.base.acknowledge_message_id is acknowledge_message_id
                {
                    var slot = found_client_index / 64;
                    var bit  = found_client_index mod 64;

                    message.client_mask[slot] bit_and= bit_not bit64(bit);

                    var do_remove = true;
                    loop var i u32; message.client_mask.count
                    {                        
                        if message.client_mask[i]
                        {
                            do_remove = false;  
                            break;
                        }
                    }

                    if do_remove
                    {
                        network_print("Server: removed pending message [%]", acknowledge_message_id);
                        buffer.used_count -= 1;
                        buffer[message_index] = buffer[buffer.used_count];
                    }

                    break;
                }                
            }
        }
        case network_message_tag.login
        {
            var message = result.message.login;

            if message.acknowledge_message_id is network_acknowledge_message_id_invalid
                break;

            var reject_reason = network_message_reject_reason.none;

            var found_user_index = u32_invalid_index;

            label check_reject
            {
                if message.client_version is_not game_version
                {
                    reject_reason = network_message_reject_reason.version_missmatch;
                    break check_reject;
                }

                if client and (server.users[client.user_index].name is message.name) and (server.users[client.user_index].password is message.password)
                {
                    found_user_index = client.user_index;
                    break check_reject;
                }

                loop var user_index u32; server.users.user_count
                {
                    if server.users[user_index].name is message.name
                    {
                        if server.users[user_index].password is_not message.password
                        {
                            reject_reason = network_message_reject_reason.credential_missmatch;
                            break check_reject;
                        }

                        loop var client_index u32; server.client_count
                        {
                            if server.clients[client_index].user_index is user_index
                            {
                                network_print_info("Server: rejected player, user is already logged in! % %\n", to_string(message.name), result.address);
                                reject_reason = network_message_reject_reason.duplicated_user_login;
                                break check_reject;
                            }
                        }

                        found_user_index = user_index;
                        break;
                    }
                }

                if (found_user_index is u32_invalid_index) and (server.users.user_count >= server.users.count)
                {
                    network_print_info("Server: rejected user, server users are full! %\n", result.address);
                    reject_reason = network_message_reject_reason.server_full_total_user;
                    break check_reject;
                }

                if (found_client_index is u32_invalid_index) and (server.client_count >= server.clients.count)
                {
                    network_print_info("Server: rejected player, game is full! %\n", result.address);
                    reject_reason = network_message_reject_reason.server_full_active_player;
                    break check_reject;
                }
            }

            if reject_reason is_not 0
            {
                var message network_message_union;
                message.tag = network_message_tag.login_reject;                
                message.acknowledge_message_id = result.message.acknowledge_message_id; // counts as acknowledge for loging message
                message.login_reject.reason = reject_reason;
                send(network, message, server.socket, result.address);
            }
            else
            {
                if found_user_index is u32_invalid_index
                {
                    var add_user_result = add_user(server, message.name, message.password);
                    network_assert(add_user_result.user);
                    found_user_index = add_user_result.user_index;
                }

                if found_client_index is u32_invalid_index
                {
                    found_client_index = server.client_count;
                    server.client_count += 1;

                    client = server.clients[found_client_index] ref;
                    client deref = {} game_client_connection;

                    client.address = result.address;
                    client.is_new  = true;

                    client.name_color = message.name_color;
                    client.body_color = message.body_color;

                    client.entity_network_id = new_network_id(server);
                    client.entity_id = add_player(game, client.entity_network_id);
                    client.user_index = found_user_index;

                    var entity = get(game, client.entity_id);
                    entity.health   = server.users.extended_users[client.user_index].health;
                    entity.position = server.users.extended_users[client.user_index].position;

                    // delete previous tent
                    var tent = get(game, server.users.extended_users[client.user_index].tent_id);
                    if tent
                        remove(game, server.users.extended_users[client.user_index].tent_id);

                    network_print_info("Server: added Client %\n", result.address);
                }

                network_assert(client.user_index is found_user_index);

                var message network_message_union;
                message.tag = network_message_tag.login_accept;
                message.acknowledge_message_id = result.message.acknowledge_message_id; // counts as acknowledge for loging message
                message.login_accept.player_entity_network_id = client.entity_network_id;
                message.login_accept.is_admin = server.users[found_user_index].is_admin;
                send(network, message, server.socket, client.address);
            }
        }
        case network_message_tag.user_input
        {
            var entity = get(game, client.entity_id);
            network_assert(entity);

            // ignore input from knockdowned players
            if entity.health is 0
                break;

            var player = entity.player ref;
            player.input_movement += result.message.user_input.movement;

            if squared_length(player.input_movement) > 0
            {
                var direction = normalize(player.input_movement);
                entity.view_direction = acos(dot([ 1, 0 ] vec2, direction));

                if dot([ 0, 1 ] vec2, direction) > 0
                    entity.view_direction = 2 * pi32 - entity.view_direction;
            }

            if result.message.user_input.do_attack
            label check_attack
            {

                var sword = get(game, player.sword_hitbox_id);
                if not sword
                {
                    player.sword_hitbox_id = add(game, game_entity_tag.hitbox, new_network_id(server));
                    sword = get(game, player.sword_hitbox_id);
                    sword.collider = { {} vec2, 0.4 } sphere2;
                    sword.hitbox.tag = game_entity_hitbox_tag.sword;
                    sword.hitbox.source_id = client.entity_id;
                    sword.hitbox.collision_mask = bit_not (bit64(game_entity_tag.none) bit_or bit64(game_entity_tag.hitbox));
                    sword.hitbox.damage = 3;
                    sword.view_direction = entity.view_direction;
                }
                else if player.sword_swing_progress < 0.5
                {
                    break check_attack;
                }

                player.sword_swing_progress = 0;

                // reset hits
                game.hitbox_hits[player.sword_hitbox_id.index_plus_one - 1].used_count = 0;
            }
            else if result.message.user_input.do_magic
            {
                var user = server.users.extended_users[client.user_index] ref;

                if (user.fireball_cooldown <= 0) and not get(game, entity.player.sword_hitbox_id)
                {
                    user.fireball_cooldown = 1;
                    def fireball_speed = 8.0;

                    var movement = direction_from_angle(entity.view_direction);

                    add_fireball(game, new_network_id(server), entity.position + [ 0, entity.collider.radius ] vec2, movement * fireball_speed, client.entity_id);
                }
            }
            else if result.message.user_input.do_interact
            {
                var drag_child = get(game, entity.drag_child_id);
                if drag_child
                {
                    drag_child.drag_parent_id = {} game_entity_id;
                    entity.drag_child_id = {} game_entity_id;
                }
                else
                {
                    var closest_player_distance_squared = 100.0; // some big range
                    var closest_player_index = u32_invalid_index;

                    var entity_index = client.entity_id.index_plus_one - 1;

                    var position = entity.position + entity.collider.center;
                    var radius   = entity.collider.radius * 0.5; // we want to overlap other by half our radius

                    var drag_mask = bit64(game_entity_tag.player) bit_or bit64(game_entity_tag.flag) bit_or bit64(game_entity_tag.chicken);

                    loop var i u32; game.entity.count
                    {
                        if not (bit64(game.tag[i]) bit_and drag_mask) or (i is entity_index)
                            continue;

                        var other = game.entity[i] ref;
                        if other.health is 0
                        {
                            var drag_parent = get(game, other.drag_parent_id);
                            if not drag_parent
                            {
                                var other_position = other.position + other.collider.center;
                                var max_grab_distance = radius + other.collider.radius;
                                var distance_squared = squared_length(other.position - entity.position);
                                if (distance_squared < (max_grab_distance * max_grab_distance)) and ( distance_squared < closest_player_distance_squared)
                                {
                                    closest_player_distance_squared = distance_squared;
                                    closest_player_index = i;
                                }
                            }
                        }
                    }

                    if closest_player_index is_not u32_invalid_index
                    {
                        var other = game.entity[closest_player_index] ref;
                        other.drag_parent_id = client.entity_id;
                        entity.drag_child_id = { closest_player_index + 1, game.generation[closest_player_index] } game_entity_id;
                    }
                }
            }

            // stop movement while swinging sword
            {
                var sword = get(game, entity.player.sword_hitbox_id);
                if sword
                    player.input_movement = {} vec2;
            }

            client.do_update = true;
        }
        case network_message_tag.heartbeat
        {
        }
        case network_message_tag.latency
        {
            loop var latency_pair_index u32; server.latency_pairs.count
            {
                if result.message.latency.latency_id is server.latency_pairs[latency_pair_index].id
                {
                    var round_trip_milliseconds = timestamp_milliseconds - server.latency_pairs[latency_pair_index].timestamp_milliseconds;

                    // avarage over last 10 latencies
                    if not client.latency_milliseconds
                        client.latency_milliseconds = (round_trip_milliseconds / 2) cast(u32);
                    else
                        client.latency_milliseconds = (client.latency_milliseconds * 0.9 + (round_trip_milliseconds cast(f32) * 0.05)) cast(u32);

                    break;
                }
            }
        }
        case network_message_tag.chat
        {
            var entity = get(game, client.entity_id);
            network_assert(entity);

            client.broadcast_chat_message = true;

            var user = server.users.extended_users[client.user_index] ref;

            if user.is_shout_exhausted or (user.knockdown_timeout > 0)
            {
                client.chat_message.text = to_string255("...");
                client.chat_message.is_shouting = false;
            }
            else
            {
                client.chat_message = result.message.chat.text;
            }

            if client.chat_message.is_shouting
            {
                user.shout_exhaustion += 5.0;

                if user.shout_exhaustion > 30
                    user.is_shout_exhausted = true;
            }
        }
        case network_message_tag.admin_server_shutdown
        {
            var ok = false;
            if client
            {
                var user = server.users[client.user_index];
                if user.is_admin
                {
                    server.do_shutdown = true;
                    ok = true;
                    return;
                }

                if not ok
                {
                    var message network_message_union;
                    message.tag = network_message_tag.login_reject;
                    message.login_reject.reason = network_message_reject_reason.server_kick;
                    client.do_remove = true;
                    send(network, message, server.socket, client.address);
                }
            }
        }

        if client
        {
            client.heartbeat_timeout = 1;
            client.missed_heartbeat_count = 0;
        }

        if result.message.tag is_not network_message_tag.acknowledge and (result.message.acknowledge_message_id is_not network_acknowledge_message_id_invalid)
        {
            var message network_message_union;
            message.tag                    = network_message_tag.acknowledge;
            message.acknowledge_message_id = result.message.acknowledge_message_id;
            network_print("Server: acknowledged % [%]", result.message.tag, result.message.acknowledge_message_id);
            send(network, message, server.socket, client.address);
        }

        network_print_info("Server: client message % %\n", result.message.tag, result.address);
    }

    // disconnect users that missed too many heartbeats
    loop var i u32; server.client_count
    {
        var client = server.clients[i] ref;
        client.heartbeat_timeout -= delta_seconds * heartbeats_per_seconds;
        if client.heartbeat_timeout <= 0
        {
            client.heartbeat_timeout += 1;
            client.missed_heartbeat_count += 1;

            if client.missed_heartbeat_count > max_missed_heartbeats
                client.do_remove = true;
        }
    }

    // send other users remove_player and remove client afterwards
    loop var a u32; server.client_count
    {
        var client = server.clients[a] ref;

        if client.do_remove
        {
            loop var b u32; server.client_count
            {
                var other = server.clients[b] ref;

                var message network_message_union;
                message.tag = network_message_tag.remove_player;
                message.remove_player.entity_network_id = client.entity_network_id;
                send(network, message, server.socket, other.address);
            }

            // save entity health
            var entity = get(game, client.entity_id);
            server.users.extended_users[client.user_index].health   = entity.health;
            server.users.extended_users[client.user_index].position = entity.position;

            // spawn tent
            {
                var tent_id = add(game, game_entity_tag.player_tent, new_network_id(server));
                var tent_entity = get(game, tent_id);
                tent_entity.position = entity.position;
                game.do_update_tick_count[tent_id.index_plus_one - 1] = 2;

                // HACK: use corpse system to delere tent after a certain time
                tent_entity.max_health = 1;
                tent_entity.corpse_lifetime = 2 * 60 * 60; // 2 hours

                var tent = game.player_tent[tent_id.index_plus_one - 1] ref;
                tent.name       = server.users[client.user_index].name;
                tent.name_color = client.name_color;
                tent.body_color = client.body_color;

                // store so we can delete it on login
                server.users.extended_users[client.user_index].tent_id = tent_id;
            }

            // updated client masks in pending_messages
            // TODO: test this
            {
                var buffer = server.pending_messages ref;

                var remove_slot     = a / 64;
                var remove_bit_mask = bit64(a  mod 64);
                
                var swapped_slot     = (server.client_count - 1) / 64;
                var swapped_bit_mask = bit64((server.client_count - 1) mod 64);

                loop var message_index u32; buffer.used_count
                {
                    var message = buffer[message_index] ref;

                    message.client_mask[remove_slot] bit_and= bit_not remove_bit_mask;

                    var swapped_is_set = (message.client_mask[swapped_slot] bit_and swapped_bit_mask);
                    message.client_mask[swapped_slot] bit_and= bit_not swapped_bit_mask;

                    if swapped_is_set
                        message.client_mask[remove_slot] bit_or= remove_bit_mask;
                }
            }

            network_print_info("Server: Client % missed to many heartbeats and is considered MIA\n", client.address);
            remove(game, client.entity_id);
            server.client_count -= 1;
            server.clients[a] = server.clients[server.client_count];
            a -= 1; // repeat index
        }
    }

    // broadcast remove entity
    // before update, so entity is not deleted yet
    loop var i u32; game.entity.count
    {
        if game.tag[i] is game_entity_tag.none
            continue;

        if game.do_delete[i]
        {
            var message network_message_union;
            message.tag = network_message_tag.delete_entity;
            message.delete_entity.network_id = game.network_id[i];
            queue(server, message);

            multiline_comment
            {

            loop var a u32; server.client_count
            {
                var client = server.clients[a] ref;
                send(network, message, server.socket, client.address);
            }
            }
        }
    }

    def chicken_spawns_per_second = 0.1;
    server.chicken_spawn_timeout -= delta_seconds * chicken_spawns_per_second;
    if server.chicken_spawn_timeout <= 0
    {
        server.chicken_spawn_timeout += 1;

        if game.entity_tag_count[game_entity_tag.chicken] < 128
            add_chicken(game, new_network_id(server), { 2, 2 } vec2);
    }

    update(server.game ref, delta_seconds);
    
    {
        var capture_the_flag = server.capture_the_flag ref;
        
        capture_the_flag.play_time += delta_seconds;

        if capture_the_flag.is_running
        {   
            loop var team_index u32; capture_the_flag.score.count
            {
                var target = get(server.game ref, capture_the_flag.flag_target_id[team_index]);
                if target.flag_target.has_scored_flag            
                {
                    capture_the_flag.score[team_index] += 1;            

                    capture_the_flag.running_id += 1;

                    var message network_message_union;
                    message.tag = network_message_tag.capture_the_flag_score;
                    message.capture_the_flag_score.running_id = capture_the_flag.running_id;
                    message.capture_the_flag_score.play_time = capture_the_flag.play_time;
                    message.capture_the_flag_score.team_index = team_index;
                    message.capture_the_flag_score.score      = capture_the_flag.score[team_index];                
                    queue(server, message);
                }

                target.flag_target.has_scored_flag = false;            

                var flag = get(server.game ref, capture_the_flag.flag_id[team_index]);
                if not flag            
                {
                    var color = capture_the_flag_team_colors[team_index];
                    color.a = 255;
                    capture_the_flag.flag_id[team_index] = add_flag(server.game ref, new_network_id(server), capture_the_flag.flag_position[team_index], team_index, color);            
                }
            }    
            
            if capture_the_flag.play_time >= capture_the_flag_event_duration
            {
                capture_the_flag.play_time -= capture_the_flag_event_duration;

                capture_the_flag.is_running = false;

                var message network_message_union;
                message.tag = network_message_tag.capture_the_flag_ended;                
                queue(server, message);

                loop var team_index; 2
                {
                    var flag = get(server.game ref, capture_the_flag.flag_id[team_index]);
                    if flag     
                        remove(server.game ref, capture_the_flag.flag_id[team_index]);
                }
            }            
        }
        else
        {            
            if capture_the_flag.play_time >= capture_the_flag_event_timeout
            {
                capture_the_flag.play_time -= capture_the_flag_event_timeout;
                capture_the_flag.is_running = true;

                capture_the_flag.running_id = 0;
                capture_the_flag.score[0] = 0;
                capture_the_flag.score[1] = 0;
                capture_the_flag.player_count[0] = 0;
                capture_the_flag.player_count[1] = 0;

                loop var client_index u32; server.client_count
                {       
                    var client = server.clients[client_index] ref;
                    client.capture_the_flag_team_index = u32_invalid_index;
                }

                loop var team_index u32; 2
                {
                    var target = get(server.game ref, capture_the_flag.flag_target_id[team_index]);

                    var target_position = target.position + target.collider.center;
                    var target_radius   = target.collider.radius;

                    loop var client_index u32; server.client_count
                    {
                        var client = server.clients[client_index] ref;
                        var player = get(server.game ref, client.entity_id);                        

                        var position = player.position + player.collider.center;
                        var radius   = player.collider.radius;
                        
                        var max_distance = target_radius + radius;
                        if squared_length(target_position - position) > (max_distance * max_distance)
                            continue;
                        
                        capture_the_flag.player_count[team_index] += 1;
                        
                        client.capture_the_flag_team_index = team_index;                        
                    }
                }

                // balance team counts
                var player_count = minimum(capture_the_flag.player_count[0], capture_the_flag.player_count[1]);
                capture_the_flag.player_count[0] = 0;
                capture_the_flag.player_count[1] = 0;

                loop var client_index u32; server.client_count
                {       
                    var client = server.clients[client_index];
                    var team_index = client.capture_the_flag_team_index;

                    var color rgba8;
                    if team_index < capture_the_flag_team_colors.count
                    {
                        if capture_the_flag.player_count[team_index] < player_count                    
                        {
                            capture_the_flag.player_count[team_index] += 1;
                        }
                        else
                        {
                            team_index = u32_invalid_index;
                            client.capture_the_flag_team_index = u32_invalid_index;
                        }
                    }

                    if team_index < capture_the_flag_team_colors.count
                    {                    
                        color = capture_the_flag_team_colors[team_index];
                        color.a = 255;                       
                    }

                    var message network_message_union;
                    message.tag = network_message_tag.capture_the_flag_player_team;
                    message.capture_the_flag_player_team.entity_network_id = client.entity_network_id;
                    message.capture_the_flag_player_team.team_index        = team_index;
                    message.capture_the_flag_player_team.team_color        = color;
                    queue(server, message);
                }

                if not player_count
                {
                    // wait for the next event                    
                    capture_the_flag.is_running = false;
                }
                else
                {
                    var message network_message_union;
                    message.tag = network_message_tag.capture_the_flag_started;
                    queue(server, message);                
                }
            }
        }
    }

    // prevent spikes when delta_seconds is very low
    var prediction_movement_scale f32;
    if delta_seconds >= 0.01
        prediction_movement_scale = (1 / delta_seconds);

    loop var a u32; server.client_count
    {
        var client = server.clients[a] ref;

        var client_name = server.users[client.user_index].name;

        var player_entity_index = client.entity_id.index_plus_one - 1;

        var player = get(game, client.entity_id);
        var player_network_id = game.network_id[player_entity_index];

        var do_update_player = game.do_update_tick_count[player_entity_index];

        // ignore movement if it did not cause a change in position
        // so we can send the exact position, instead of a prediction
        var movement vec2;
        if do_update_player > 1
            movement = player.player.input_movement * prediction_movement_scale;

        var position = player.position;
        player.player.input_movement = {} vec2;

        var send_entity = player deref;

        loop var b u32; server.client_count
        {
            var other = server.clients[b] ref;

            var entity = get(game, other.entity_id);
            network_assert(entity);

            if client.is_new
            {
                var message network_message_union;

                var other_name = server.users[other.user_index].name;

                // tell other about client
                message.tag = network_message_tag.add_player;
                message.add_player.entity_network_id = client.entity_network_id;
                message.add_player.name = client_name;
                message.add_player.name_color = client.name_color;
                message.add_player.body_color = client.body_color;
                send(network, message, server.socket, other.address);

                // tell client about other
                message.tag = network_message_tag.add_player;
                message.add_player.entity_network_id = other.entity_network_id;
                message.add_player.name = other_name;
                message.add_player.name_color = other.name_color;
                message.add_player.body_color = other.body_color;
                send(network, message, server.socket, client.address);
            }

            if client.broadcast_chat_message
            {
                var message network_message_union;
                message.tag = network_message_tag.chat;
                message.chat.player_entity_network_id = client.entity_network_id;
                message.chat.text = client.chat_message;
                send(network, message, server.socket, other.address);
            }

            // send predicted player position
            if client.is_new or do_update_player
            {
                var entity = send_entity;

                // predict future position on other depending on latency
                if enable_server_movement_prediction
                {
                    var predicted_movement = movement * minimum(server_max_prediction_seconds, ((client.latency_milliseconds + other.latency_milliseconds) / 1000.0));
                    entity.position += predicted_movement;
                }

                // network_print("player % update %, movement:% (%)\n", player_network_id, do_update_player, predicted_movement, player.movement);

                var message network_message_union;
                message.tag = network_message_tag.update_entity;
                message.update_entity.tag        = game_entity_tag.player;
                message.update_entity.network_id = player_network_id;
                message.update_entity.entity     = entity;
                send(network, message, server.socket, other.address);
            }
        }

        loop var i u32; game.entity.count
        {
            if (game.tag[i] is game_entity_tag.none) or (not client.is_new and not game.do_update_tick_count[i])
                continue;

            if not client.is_new and (game.tag[i] is game_entity_tag.player)
                continue;

            var entity = game.entity[i];

            var message network_message_union;
            message.tag = network_message_tag.update_entity;
            message.update_entity.network_id = game.network_id[i];
            message.update_entity.tag        = game.tag[i];
            message.update_entity.entity     = entity;
            send(network, message, server.socket, client.address);

            if game.tag[i] is game_entity_tag.player_tent
            {
                var message network_message_union;
                message.tag = network_message_tag.update_player_tent;
                message.update_player_tent.entity_network_id = game.network_id[i];
                message.update_player_tent.player_tent       = game.player_tent[i];
                send(network, message, server.socket, client.address);
            }
        }
    }

    def latency_checks_per_second = server_ticks_per_second * 0.25;
    server.latency_timeout -= delta_seconds * latency_checks_per_second;
    if server.latency_timeout <= 0
    {
        server.latency_timeout += 1.0;

        var latency_id = server.latency_pairs[server.latency_pair_index].id + 1;
        server.latency_pair_index = (server.latency_pair_index + 1) mod server.latency_pairs.count;

        if latency_id is invalid_latency_id
            latency_id += 1;

        server.latency_pairs[server.latency_pair_index].id = latency_id;
        server.latency_pairs[server.latency_pair_index].timestamp_milliseconds = platform_local_timestamp_milliseconds(platform);

        var message network_message_union;
        message.tag = network_message_tag.latency;
        message.latency.latency_id = latency_id;

        loop var a u32; server.client_count
        {
            var client = server.clients[a] ref;
            message.latency.latency_milliseconds = client.latency_milliseconds;
            send(network, message, server.socket, client.address);
        }
    }

    // send pending_messages
    {
        var buffer = server.pending_messages ref;
        loop var message_index u32; buffer.used_count
        {
            var message = buffer[message_index];
            message.resend_timeout -= delta_seconds * 2; // twice per second
            if message.resend_timeout > 0
                continue;

            message.resend_timeout += 1;

            loop var client_index u32; server.client_count
            {
                var client = server.clients[client_index];

                var slot = client_index / 64;
                var bit  = client_index mod 64;

                if message.client_mask[slot] bit_and bit64(bit)
                {
                    network_print("Server: send % [%]", message.base.tag, message.base.acknowledge_message_id);
                    send(network, message.base, server.socket, client.address);                
                }
            }
        }
    }

    loop var user_index u32; server.users.count cast(u32)
    {
        var user = server.users.extended_users[user_index] ref;

        if user.fireball_cooldown > 0
            user.fireball_cooldown -= delta_seconds;

        if user.knockdown_timeout > 0
            user.knockdown_timeout -= delta_seconds;

        if user.shout_exhaustion > 0
        {
            user.shout_exhaustion -= delta_seconds;

            if user.shout_exhaustion <= 0
            {
                user.shout_exhaustion = 0;
                user.is_shout_exhausted = false;
            }
        }
    }

    loop var a u32; server.client_count
    {
        var client = server.clients[a] ref;
        client.do_update = false;
        client.broadcast_chat_message = false;
        client.is_new = false;

        var entity = get(game, client.entity_id);
        network_assert(entity);

        var entity_index = client.entity_id.index_plus_one - 1;

        var user = server.users.extended_users[client.user_index] ref;

        if user.is_knockdowned
        {
            if (user.knockdown_timeout <= 0) or entity.health
            {
                // healed by waiting out the timer
                if user.knockdown_timeout <= 0
                    entity.health = maximum(1, entity.max_health / 5);

                user.knockdown_timeout = 0;
                user.is_knockdowned = false;

                // stop being dragged
                var drag_parent = get(game, entity.drag_parent_id);
                if drag_parent
                    drag_parent.drag_child_id = {} game_entity_id;
                entity.drag_parent_id = {} game_entity_id;

                game.do_update_tick_count[entity_index] = 2;
            }
        }
        else
        {
            if not entity.health
            {
                user.knockdown_timeout = max_user_knockdown_time;
                user.is_knockdowned = true;
                game.do_update_tick_count[entity_index] = 2;
            }
        }
    }
}

func add_user(server game_server ref, name string63, password string63) (user game_user ref, user_index u32)
{
    if server.users.user_count >= server.users.count
        return null, 0;

    var user_index = server.users.user_count;
    server.users.user_count += 1;

    var user = server.users[user_index] ref;
    user deref = {} game_user;

    user.name     = name;
    user.password = password;

    network_print_info("Server: added user % %\n", to_string(name), user_index);

    return user, user_index;
}
