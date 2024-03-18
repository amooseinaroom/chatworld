import random;

def player_movement_speed_idle     = 6.0;
def player_movement_speed_dragging = 3.0;

struct game_state
{
    tile_map game_world_tile_map;

    camera_position vec2;
    camera_zoom     f32;

    random random_pcg;

    // entity manager

    entity_count u32;

    entity_tag_count u32[game_entity_tag.count];

    freelist     u32[max_entity_count];
    generation   u32[max_entity_count];
    tag          game_entity_tag[max_entity_count];
    network_id   game_entity_network_id[max_entity_count];
    do_delete    b8[max_entity_count];
    do_delete_next_tick b8[max_entity_count];
    entity       game_entity[max_entity_count];
    player_tent  game_entity_player_tent[max_entity_count];
    hitbox_hits  game_entity_hitbox_hits[max_entity_count];

    // server only maybe
    do_update_tick_count u8[max_entity_count];
}

struct game_entity_hitbox_hits
{
    expand base       game_entity_id[16];
           used_count u32;
}

struct game_entity_network_id
{
    value u32;
}

func is(left game_entity_network_id, right game_entity_network_id) (ok b8)
{
    return left.value is right.value;
}

func is_not(left game_entity_network_id, right game_entity_network_id) (ok b8)
{
    return left.value is_not right.value;
}

func is(left game_entity_id, right game_entity_id) (ok b8)
{
    return left.value is right.value;
}

func is_not(left game_entity_id, right game_entity_id) (ok b8)
{
    return left.value is_not right.value;
}

// COMPILER BUG: somehow sets the type to u8
def max_entity_count = (1 bit_shift_left 14) cast(u32);

def game_world_width = 256 cast(s32);
def game_world_size  = [ game_world_width, game_world_width ] vec2;

def team_index_plus_one_no_team = 0 cast(u32);

type game_entity_id union
{
    expand pair struct
    {
        index_plus_one u32;
        generation     u32;
    };

    value u64;
};

struct game_entity
{
    position      vec2;
    movement      vec2;
    push_velocity vec2;

    view_direction f32;

    collider sphere2;

    max_health      s32;
    health          s32;
    corpse_lifetime f32;

    drag_parent_id game_entity_id;
    drag_child_id  game_entity_id;

    expand tags union
    {
        chicken struct
        {
            move_direction         vec2;
            is_moving              b8;
            toggle_moveing_timeout f32;
        };

        healing_altar struct
        {
            heal_timeout f32;
        };

        hitbox struct
        {
            source_id      game_entity_id;
            collision_mask u64;
            damage         s32;
            lifetime       f32;
            tag game_entity_hitbox_tag;
            remove_on_hit  b8;
            fixed_movement b8;

            sword_view_direction f32;
        };

        player struct
        {
            input_movement       vec2;

            sword_hitbox_id      game_entity_id;
            fireball_id          game_entity_id;
            sword_swing_progress f32;

            healed_health_while_knocked_down s32;

            team_index_plus_one u32;
            team_color rgba8;

            // send back to client, for better prediction
            movement_speed f32;
        };

        flag_target struct
        {
            team_index_plus_one u32;
            team_color rgba8;
            has_scored_flag b8;
        };

        flag struct
        {
            team_index_plus_one u32;
            team_color          rgba8;
        };

        dog_retriever struct
        {
            pick_id                game_entity_id;
            // flag_id                game_entity_id;
            player_target_position vec2;
            flag_target_position   vec2;
            target_position        vec2;
            team_index_plus_one    u32;
            team_color             rgba8;

            state game_entity_dog_retreiver_state;
        };
    };
}

enum game_entity_dog_retreiver_state u8
{
    sleep;
    search;
        pick_flag;
        pick_player;
    deliver;
}

struct game_entity_player_tent
{
    name       string63;
    name_color rgba8;
    body_color rgba8;
}

enum game_entity_tag u8
{
    none;
    player;
    player_tent;
    hitbox;
    wall; // mainly for collision detection
    chicken;
    flag;
    flag_target;
    dog_retriever;
    healing_altar;

    tall_grass;
}

enum game_entity_hitbox_tag u8
{
    none;
    fireball;
    sword;
}

func init(game game_state ref, random random_pcg)
{
    clear_value(game);

    loop var i u32; game.freelist.count
        game.freelist[i] = i;

    loop var y s32; game_world_width
    {
        loop var x s32; game_world_width
        {
            game.tile_map[y][x] = game_world_tile.grass;

            // if (x + y) bit_and 1
            //     game.tile_map[y][x] = game_world_tile.ground;
            // else
            //     game.tile_map[y][x] = game_world_tile.grass;
        }
    }

    //loop var y s32 = 2; game_world_width - 4
    //    loop var x s32 = 2; game_world_width  - 4
    //    {
    //        game.tile_map[y][x] = game_world_tile.grass;
    //    }

    loop var y s32 = 5; 6
        loop var x = 5; 6
        {
            game.tile_map[y][x] = game_world_tile.ground;
        }

    game.random = random;
}

func add(game game_state ref, tag game_entity_tag, network_id game_entity_network_id) (id game_entity_id)
{
    loop var i u32; game.network_id.count
        assert(game.network_id[i] is_not network_id);

    assert(tag < game_entity_tag.count);

    assert(game.entity_count < game.entity.count);
    var index = game.freelist[game.entity_count];
    game.entity_count += 1;

    game.entity_tag_count[tag] += 1;

    game.generation[index] += 1;
    game.entity[index] = {} game_entity;
    game.network_id[index] = network_id;

    assert(game.tag[index] is game_entity_tag.none);
    game.tag[index] = tag;

    game.do_delete[index] = false;
    game.do_update_tick_count[index] = 1; // force one initial update

    var id game_entity_id;
    id.index_plus_one = index + 1;
    id.generation = game.generation[index];
    return id;
}

def player_max_health = 12 cast(s32);

func add_player(game game_state ref, network_id game_entity_network_id) (id game_entity_id)
{
    var id = add(game, game_entity_tag.player, network_id);
    var entity = get(game, id);

    entity.max_health = player_max_health;
    entity.health = entity.max_health;

    // this is set so that it aligns well with the sprites
    var radius = 0.375;
    entity.collider = { [ 0, 0.0625 + radius ] vec2, radius } sphere2;

    return id;
}

func add_fireball(game game_state ref, network_id game_entity_network_id, position vec2, movement vec2, source_id game_entity_id)
{
    var id = add(game, game_entity_tag.hitbox, network_id);
    var entity = get(game, id);
    entity.collider = { {} vec2, 0.25 } sphere2;
    entity.position = position;
    entity.movement = movement;
    entity.hitbox.tag = game_entity_hitbox_tag.fireball;
    entity.hitbox.collision_mask = bit_not (bit64(game_entity_tag.none) bit_or bit64(game_entity_tag.hitbox));
    entity.hitbox.damage = 1;
    entity.hitbox.lifetime = 4;
    entity.hitbox.source_id = source_id;
    entity.hitbox.remove_on_hit = true;
    entity.hitbox.fixed_movement = true;

    // reset hits
    game.hitbox_hits[id.index_plus_one - 1].used_count = 0;
}

func add_chicken(game game_state ref, network_id game_entity_network_id, position vec2)
{
    var id = add(game, game_entity_tag.chicken, network_id);
    var entity = get(game, id);

    entity.max_health = 5;
    entity.health = entity.max_health;

    entity.collider = { {} vec2, 0.333 } sphere2;
    entity.position = position;
}

func add_healing_altar(game game_state ref, network_id game_entity_network_id, position vec2)
{
    var id = add(game, game_entity_tag.healing_altar, network_id);

    var entity = get(game, id);
    entity.collider = { {} vec2, 1.5 } sphere2;
    entity.position = position;

    // TEMP:
    var min_tile = v2s(maximum(v2(0), floor(position + entity.collider.center - entity.collider.radius)));
    var max_tile = v2s(minimum(v2(game_world_width), ceil(position + entity.collider.center + entity.collider.radius)));
    loop var y = min_tile.y; max_tile.y
    {
        loop var x = min_tile.x; max_tile.x
        {
            game.tile_map[y][x] = game_world_tile.ground;
        }
    }
}

func add_flag(game game_state ref, network_id game_entity_network_id, position vec2, team_index u32, team_color rgba8) (id game_entity_id)
{
    assert(team_index < 2);
    var id = add(game, game_entity_tag.flag, network_id);

    var entity = get(game, id);
    entity.collider = { {} vec2, 0.25 } sphere2;
    entity.position = position;
    entity.flag.team_index_plus_one = team_index + 1;
    entity.flag.team_color = team_color;

    return id;
}

func add_flag_target(game game_state ref, network_id game_entity_network_id, position vec2, team_index u32, team_color rgba8) (id game_entity_id)
{
    assert(team_index < 2);
    var id = add(game, game_entity_tag.flag_target, network_id);

    var entity = get(game, id);
    entity.collider = { {} vec2, 1.5 } sphere2;
    entity.position = position;
    entity.flag_target.team_index_plus_one = team_index + 1;
    entity.flag_target.team_color = team_color;
    entity.flag_target.team_color.a = 128;

    // TEMP:
    var min_tile = v2s(maximum(v2(0), floor(position + entity.collider.center - entity.collider.radius)));
    var max_tile = v2s(minimum(v2(game_world_width), ceil(position + entity.collider.center + entity.collider.radius)));
    loop var y = min_tile.y; max_tile.y
    {
        loop var x = min_tile.x; max_tile.x
        {
            game.tile_map[y][x] = game_world_tile.ground;
        }
    }

    return id;
}

func add_dog_retriever(game game_state ref, network_id game_entity_network_id, position vec2, team_index u32, team_color rgba8, player_target_position vec2, flag_target_position vec2) (id game_entity_id)
{
    assert(team_index < 2);
    var id = add(game, game_entity_tag.dog_retriever, network_id);

    var entity = get(game, id);
    entity.collider = { {} vec2, 0.33 } sphere2;
    entity.position = position;
    entity.max_health = 1;
    entity.health = entity.max_health;
    entity.dog_retriever.team_index_plus_one = team_index + 1;
    entity.dog_retriever.team_color = team_color;
    entity.dog_retriever.player_target_position = player_target_position;
    entity.dog_retriever.flag_target_position   = flag_target_position;

    return id;
}

var global debug_game_is_inside_update = false;

func remove(game game_state ref, id game_entity_id)
{
    assert(not debug_game_is_inside_update, "use remove_next_tick instead");
    assert(id.index_plus_one and (id.index_plus_one <= game.entity.count));

    var index = id.index_plus_one - 1;
    assert(not game.do_delete[index]);
    game.do_delete[index] = true;
}


func remove_next_tick(game game_state ref, id game_entity_id)
{
    assert(debug_game_is_inside_update, "use remove instead");
    assert(id.index_plus_one and (id.index_plus_one <= game.entity.count));

    var index = id.index_plus_one - 1;
    game.do_delete_next_tick[index] = true;
}

func remove_for_real(game game_state ref, id game_entity_id)
{
    assert(id.index_plus_one and (id.index_plus_one <= game.entity.count));

    var index = id.index_plus_one - 1;

    var tag = game.tag[index];
    assert(game.tag[index] is_not game_entity_tag.none);
    game.tag[index] = game_entity_tag.none;

    assert(game.entity_tag_count[tag]);
    game.entity_tag_count[tag] -= 1;

    assert(game.entity_count);
    game.entity_count -= 1;
    game.freelist[game.entity_count] = index;
}

func get(game game_state ref, id game_entity_id) (entity game_entity ref)
{
    if not id.index_plus_one
        return null;

    var index = id.index_plus_one - 1;
    assert(index < game.entity.count);

    if game.do_delete[index] or (game.generation[index] is_not id.generation)
        return null;

    assert(game.tag[index] is_not game_entity_tag.none);

    return game.entity[index] ref;
}

def next_entity_start = u32_invalid_index;

func next_entity(game game_state ref, index_ref u32 ref, tag_mask u64 = bit_not bit64(game_entity_tag.none)) (ok b8)
{
    var index = index_ref deref;
    index += 1;
    assert(index < game.entity.count);

    while (index < game.entity.count)
    {
        if not game.do_delete[index] and (tag_mask bit_and bit64(game.tag[index]))
            break;

        index += 1;
    }

    index_ref deref = index;
    return (index < game.entity.count);
}

def max_corpse_lifetime = 10.0;

// M - distance
// D - duration
// f(0)  = a * 0.5 * t² + v * t = 0
// f(D)  = a * 0.5 * D² + v * D = M
// f2(D) = a * D + v = 0
//       = a * -0.5 * D² = M
//       => a = M * -2 / D²
//       => v = M * 2 / D
def push_distance = 2.0;
def push_duration = 0.5;
def push_decceleration = (push_distance * -2) / (push_duration * push_duration);
def push_velocity      = (push_distance * 2)  / push_duration;

func update(game game_state ref, delta_seconds f32)
{
    if lang_debug
        debug_game_is_inside_update = true;

    // apply dragging to movement
    loop var i u32; game.entity.count
    {
        if game.tag[i] is game_entity_tag.none
            continue;

        var entity = game.entity[i] ref;
        var drag_parent = get(game, entity.drag_parent_id);
        if not drag_parent
            continue;

        if not drag_parent.health
        {
            drag_parent.drag_child_id = {} game_entity_id;
            entity.drag_parent_id = {} game_entity_id;
            continue;
        }

        var position = entity.position + entity.collider.center;
        var parent_position = drag_parent.position + drag_parent.collider.center;
        var radius = entity.collider.radius + drag_parent.collider.radius;

        var distance = position - parent_position;

        if squared_length(distance) > (radius * radius)
        {
            var target_position = normalize(distance) * radius + parent_position;
            position = apply_spring_without_overshoot(position, target_position, 1000, delta_seconds);
            entity.movement += position - entity.collider.center - entity.position;
        }
    }

    loop var i u32; game.entity.count
    {
        if game.tag[i] is game_entity_tag.none
            continue;

        if game.do_delete[i]
        {
            remove_for_real(game, { i + 1, game.generation[i] } game_entity_id);
            continue;
        }

        game.do_delete[i] = game.do_delete_next_tick[i];
        game.do_delete_next_tick[i] = false;

        var entity = game.entity[i] ref;

        if entity.max_health and (entity.health <= 0)
        {
            entity.health = 0;

            if game.tag[i] is game_entity_tag.player
            {

            }
            else
            {
                if entity.corpse_lifetime is 0
                {
                    entity.corpse_lifetime = max_corpse_lifetime;
                    game.do_update_tick_count[i] = maximum(1, game.do_update_tick_count[i] cast(u32)) cast(u8);
                }
                else
                {
                    entity.corpse_lifetime -= delta_seconds;
                    if entity.corpse_lifetime <= 0
                    {
                        entity.corpse_lifetime = -1; // HACK: so we do not land on 0 and trigger the other branch
                        game.do_delete[i] = true;
                    }
                }
            }
        }

        var position = entity.position;
        var do_update = false;

        def max_push_velocity = 20.0;
        if squared_length(entity.push_velocity) > (max_push_velocity * max_push_velocity)
            entity.push_velocity = normalize(entity.push_velocity) * max_push_velocity;

        var decceleration = normalize_or_zero(entity.push_velocity) * (push_decceleration * delta_seconds);

        entity.position += (decceleration * 0.5 + entity.push_velocity) * delta_seconds;
        if squared_length(decceleration) > squared_length(entity.push_velocity)
            entity.push_velocity = {} vec2;
        else
            entity.push_velocity += decceleration;

        var is_dead = entity.max_health and (entity.health <= 0);

        switch game.tag[i]
        case game_entity_tag.hitbox
        {
            if entity.hitbox.lifetime > 0
            {
                entity.hitbox.lifetime -= delta_seconds;

                if entity.hitbox.lifetime <= 0
                {
                    entity.hitbox.lifetime = 0;
                    remove_next_tick(game, { i + 1, game.generation[i] } game_entity_id);
                    continue;
                }
            }

            if entity.hitbox.fixed_movement
            {
                entity.position += entity.movement * delta_seconds;
            }
            else
            {
                entity.position += entity.movement;
                entity.movement = {} vec2;
            }
        }
        case game_entity_tag.player
        {
            var player = entity.player ref;

            var sword = get(game, player.sword_hitbox_id);

            {
                var movement_speed = player_movement_speed_idle;
                if sword or is_dead
                    movement_speed = 0;
                else if get(game, entity.drag_child_id)
                    movement_speed = player_movement_speed_dragging;

                var max_distance = movement_speed * delta_seconds;

                var input_movement = player.input_movement * movement_speed;
                var distance = length(input_movement);
                var allowed_distance = minimum(max_distance, distance);

                if distance > 0.0
                    input_movement *= allowed_distance / distance;

                entity.position += entity.movement + input_movement;
                entity.movement = {} vec2;
                player.input_movement = input_movement; // we need it to send predicted position to the clients {} vec2;

                do_update or= entity.player.movement_speed is_not movement_speed;
                entity.player.movement_speed = movement_speed; // send back to client
            }

            if sword
            {
                if is_dead
                {
                    player.sword_swing_progress = 1;
                    remove_next_tick(game, player.sword_hitbox_id);
                }
                else
                {
                    // var angle = sword.view_direction; // pi32 * (player.sword_swing_progress - 0.5) + sword.view_direction;
                    var angle = pi32 * (player.sword_swing_progress - 0.5) + sword.hitbox.sword_view_direction;
                    var target_position = direction_from_angle(angle) * (entity.collider.radius + sword.collider.radius) + entity.position + entity.collider.center;
                    sword.movement = target_position - sword.position;
                    sword.view_direction = angle;
                    game.do_update_tick_count[player.sword_hitbox_id.index_plus_one - 1] = 2;

                    if player.sword_swing_progress < 1
                    {
                        def sword_swings_per_second = 4.0;
                        player.sword_swing_progress += delta_seconds * sword_swings_per_second;

                        if player.sword_swing_progress >= 1
                        {
                            player.sword_swing_progress = 1;
                            remove_next_tick(game, player.sword_hitbox_id);
                        }
                    }
                }
            }
        }
        case game_entity_tag.chicken
        {
            var chicken = entity.chicken ref;

            if not is_dead
            {
                chicken.toggle_moveing_timeout -= delta_seconds;
                if chicken.toggle_moveing_timeout <= 0
                {
                    chicken.is_moving = not chicken.is_moving;

                    if chicken.is_moving
                    {
                        var direction_angle = random_f32_zero_to_one(game.random ref) * pi32 * 2;
                        var direction = [ cos(direction_angle), sin(direction_angle) ] vec2;

                        chicken.toggle_moveing_timeout += random_f32_zero_to_one(game.random ref) * 10 + 0.5;
                        chicken.move_direction = direction;

                        var result = angle_from_direction(direction);
                        if result.ok
                            entity.view_direction = result.angle;
                    }
                    else
                    {
                        chicken.toggle_moveing_timeout += random_f32_zero_to_one(game.random ref) * 4 + 1;
                        chicken.move_direction = {} vec2;
                    }
                }
            }
            else
            {
                chicken.move_direction = {} vec2;
            }

            // if chicken.is_moving
            {
                def chicken_movement_speed = 2.0;
                entity.position += chicken.move_direction * (chicken_movement_speed * delta_seconds) + entity.movement;
                entity.movement = {} vec2;
            }
        }
        case game_entity_tag.healing_altar
        {
            def healing_altar_heals_per_second = 2;
            var healing_altar = entity.healing_altar ref;
            healing_altar.heal_timeout -= delta_seconds * healing_altar_heals_per_second;
            if healing_altar.heal_timeout <= 0
            {
                healing_altar.heal_timeout += 1;

                var position = entity.position + entity.collider.center;
                var radius   = entity.collider.radius;

                var heal_mask = bit64(game_entity_tag.player);

                loop var other_index u32; game.entity.count
                {
                    if not (bit64(game.tag[other_index]) bit_and heal_mask) or game.do_delete[other_index]
                        continue;

                    var other = game.entity[other_index] ref;

                    var other_position = other.position + other.collider.center;
                    var max_distance = radius + other.collider.radius;
                    if squared_length(other_position - position) > (max_distance * max_distance)
                        continue;

                    var previous_health = other.health;
                    if previous_health
                    {
                        other.health = minimum(other.health + 1, other.max_health);
                    }
                    else
                    {
                        // delay revive until we have accumulated a bit of health
                        // will be reset when the player is knocked down on server
                        other.player.healed_health_while_knocked_down += 1;
                        if other.player.healed_health_while_knocked_down >= (other.max_health / 2)
                            other.health = minimum(other.player.healed_health_while_knocked_down, other.max_health);
                    }

                    if other.health is_not previous_health
                        game.do_update_tick_count[other_index] = maximum(game.do_update_tick_count[other_index] cast(u32), 1 cast(u32)) cast(u8);
                }
            }
        }
        case game_entity_tag.flag_target
        {
            var target = entity.flag_target ref;
            var position = entity.position + entity.collider.center;
            var radius   = entity.collider.radius;

            var target_mask = bit64(game_entity_tag.flag);
            var team_index = target.team_index_plus_one - 1;

            loop var other_index u32; game.entity.count
            {
                if not (bit64(game.tag[other_index]) bit_and target_mask) or game.do_delete[other_index]
                    continue;

                var other = game.entity[other_index] ref;
                if (other.flag.team_index_plus_one - 1) is team_index
                    continue;

                // only score if not dragged
                if get(game, other.drag_parent_id)
                    continue;

                var other_position = other.position + other.collider.center;
                var max_distance = radius + other.collider.radius;
                if squared_length(other_position - position) > (max_distance * max_distance)
                    continue;

                remove_next_tick(game, { other_index + 1, game.generation[other_index] } game_entity_id);
                target.has_scored_flag = true;
            }
        }
        case game_entity_tag.dog_retriever
        {
            var dog_retriever = entity.dog_retriever ref;
            var position = entity.position + entity.collider.center;
            var radius   = entity.collider.radius;

            // can be damaged, so it drops when it is delivering something
            // but always heals back up
            assert(entity.max_health is 1);
            entity.health = entity.max_health;
            entity.corpse_lifetime = 0;

            var retriever_id = { i + 1, game.generation[i] } game_entity_id;

            switch dog_retriever.state
            case game_entity_dog_retreiver_state.sleep
            {
                // noting to do
            }
            case game_entity_dog_retreiver_state.search
            {
                var target_mask = bit64(game_entity_tag.flag) bit_or bit64(game_entity_tag.player);
                var team_index = dog_retriever.team_index_plus_one - 1;

                var closest_distance_squared = 10000.0;
                var closest_entiy_index = u32_invalid_index;
                var closest_entiy_is_player = false;

                loop var other_index u32; game.entity.count
                {
                    if not (bit64(game.tag[other_index]) bit_and target_mask) or game.do_delete[other_index]
                        continue;

                    var other = game.entity[other_index] ref;

                    if other.health
                        continue;

                    if get(game, other.drag_parent_id)
                        continue;

                    var other_position = other.position + other.collider.center;
                    var other_radius   = other.collider.radius;
                    var pick_radius = (radius + other_radius) * 1.5;

                    var other_team_index u32;
                    switch game.tag[other_index]
                    case game_entity_tag.flag
                    {
                        other_team_index = other.flag.team_index_plus_one - 1;

                        if squared_length(other_position - dog_retriever.flag_target_position) < (pick_radius * pick_radius)
                            continue;
                    }
                    case game_entity_tag.player
                    {
                        other_team_index = other.player.team_index_plus_one - 1;

                        if squared_length(other_position - dog_retriever.player_target_position) < (pick_radius * pick_radius)
                            continue;
                    }
                    else
                    {
                        assert(0);
                    }

                    if other_team_index is_not team_index
                        continue;

                    var distance_squared = squared_length(other_position - position);
                    if closest_distance_squared < distance_squared
                        continue;

                    closest_distance_squared = distance_squared;
                    closest_entiy_index = other_index;

                    // prioritize players
                    if game.tag[other_index] is game_entity_tag.player
                    {
                        closest_entiy_is_player = true;
                        target_mask = bit64(game_entity_tag.player);
                    }
                }

                if closest_entiy_index is_not u32_invalid_index
                {
                    if closest_entiy_is_player
                    {
                        dog_retriever.state = game_entity_dog_retreiver_state.pick_player;
                        dog_retriever.target_position = dog_retriever.player_target_position;
                    }
                    else
                    {
                        dog_retriever.state = game_entity_dog_retreiver_state.pick_flag;
                        dog_retriever.target_position = dog_retriever.flag_target_position;
                    }

                    dog_retriever.pick_id = { closest_entiy_index + 1, game.generation[closest_entiy_index] } game_entity_id;
                }
            }
            case game_entity_dog_retreiver_state.pick_flag, game_entity_dog_retreiver_state.pick_player
            {
                var pick_target = get(game, dog_retriever.pick_id);
                if not pick_target or pick_target.health or get(game, pick_target.drag_parent_id)
                {
                    dog_retriever.pick_id = {} game_entity_id;
                    dog_retriever.state = game_entity_dog_retreiver_state.search;
                    break;
                }

                def movement_speed = 8.0;
                var max_distance = movement_speed * delta_seconds;
                var movement = pick_target.position + pick_target.collider.center - position;
                if squared_length(movement) > (max_distance * max_distance)
                {
                    movement = normalize(movement) * max_distance;
                }
                else
                {
                   assert(not get(game, pick_target.drag_parent_id));
                    pick_target.drag_parent_id = retriever_id;
                    entity.drag_child_id       = dog_retriever.pick_id;
                    dog_retriever.pick_id          = {} game_entity_id;
                    dog_retriever.state = game_entity_dog_retreiver_state.deliver;
                }

                entity.position += entity.movement + movement;
            }
            case game_entity_dog_retreiver_state.deliver
            {
                var drag_child = get(game, entity.drag_child_id);
                if not drag_child
                {
                    dog_retriever.state = game_entity_dog_retreiver_state.search;
                    break;
                }

                assert(drag_child.drag_parent_id is retriever_id);

                var drop_radius = radius + drag_child.collider.radius;

                def movement_speed = 8.0;
                var max_distance = movement_speed * delta_seconds;
                var movement = dog_retriever.target_position - position;
                var movement_lenght_squared = squared_length(movement);
                if movement_lenght_squared > (max_distance * max_distance)
                {
                    movement = normalize(movement) * max_distance;
                }
                else if movement_lenght_squared < (drop_radius * drop_radius)
                {
                    drag_child.drag_parent_id = {} game_entity_id;
                    entity.drag_child_id       = {} game_entity_id;
                    dog_retriever.state = game_entity_dog_retreiver_state.search;
                }

                entity.position += entity.movement + movement;
            }
            else
            {
                assert(0);
            }
        }
        else
        {
            entity.position += entity.movement;
            entity.movement = {} vec2;
        }

        // simple world bounds
        if (game.tag[i] is_not game_entity_tag.hitbox) or (entity.hitbox.collision_mask bit_and bit64(game_entity_tag.wall))
            check_world_collision(game, entity, delta_seconds);

        // update next two ticks if entity moved
        // this way we send the predicted position and one final rest idle position
        if squared_length(position - entity.position) > 0
            game.do_update_tick_count[i] = 2;
        else if do_update
            game.do_update_tick_count[i] = maximum(game.do_update_tick_count[i] cast(u32), 1) cast(u8);
        else if game.do_update_tick_count[i]
            game.do_update_tick_count[i] -= 1;
    }

    if lang_debug
        debug_game_is_inside_update = false;

    loop var hitbox_index u32; game.entity.count
    {
        if game.do_delete[hitbox_index] or (game.tag[hitbox_index] is_not game_entity_tag.hitbox)
            continue;

        var hitbox = game.entity[hitbox_index] ref;
        var hitbox_sphere = hitbox.collider;
        var hitbox_collision_mask = hitbox.hitbox.collision_mask;
        var hitbox_damage = hitbox.hitbox.damage;
        hitbox_sphere.center += hitbox.position;

        var did_collide = false;

        var source = get(game, hitbox.hitbox.source_id);
        var source_position = source.position + source.collider.center;

        var hitbox_hits = game.hitbox_hits[hitbox_index] ref;

        label other_loop loop var other_index u32; game.entity.count
        {
            if game.do_delete[other_index] or not (bit64(game.tag[other_index]) bit_and hitbox_collision_mask)
                continue;

            var other = game.entity[other_index] ref;

            if (other is source) or (other.health is 0)
                continue;

            var other_id = { other_index, game.generation[other_index] } game_entity_id;
            loop var hit_index u32; hitbox_hits.used_count
            {
                if hitbox_hits[hit_index].value is other_id.value
                    continue other_loop;
            }

            var other_sphere = other.collider;
            other_sphere.center += other.position;

            var radius = hitbox_sphere.radius + other_sphere.radius;
            if squared_length(hitbox_sphere.center - other_sphere.center) < (radius * radius)
            {
                network_assert(hitbox_hits.used_count < hitbox_hits.count);

                var push_direction vec2;
                switch hitbox.hitbox.tag
                case game_entity_hitbox_tag.fireball
                    push_direction = normalize_or_zero(hitbox.movement);
                case game_entity_hitbox_tag.sword
                {
                    push_direction = normalize_or_zero(other_sphere.center - source_position);
                }
                else
                    assert(0);

                hitbox_hits[hitbox_hits.used_count] = other_id;
                hitbox_hits.used_count += 1;

                other.push_velocity += push_direction * push_velocity;
                other.health = maximum(0, other.health - hitbox_damage);
                did_collide = true;
            }
        }

        game.do_delete[hitbox_index] or= did_collide and hitbox.hitbox.remove_on_hit;
    }
}

func check_world_collision(game game_state ref, entity game_entity ref, delta_seconds f32)
{
    var collider_position = entity.position + entity.collider.center;
    var radius = entity.collider.radius;
    if collider_position.x - radius < 0
        collider_position.x = radius;
    else if collider_position.x + radius > game_world_size.x
        collider_position.x = game_world_size.x - radius;

    if collider_position.y - radius < 0
        collider_position.y = radius;
    else if collider_position.y + radius > game_world_size.y
        collider_position.y = game_world_size.y - radius;

    entity.position = collider_position - entity.collider.center;
}

func direction_from_angle(angle f32) (direction vec2)
{
    var direction = [ cos(angle), -sin(angle) ] vec2;
    return direction;
}

func angle_from_direction(direction vec2) (ok b8, angle f32)
{
    if squared_length(direction) > 0
    {
        direction = normalize(direction);
        var angle = acos(dot([ 1, 0 ] vec2, direction));

        if dot([ 0, 1 ] vec2, direction) >= 0
            angle = 2 * pi32 - angle;

        return true, angle;
    }

    return false, 0;
}

enum game_world_tile u8
{
    none;
    ground;
    grass;
    water;
}

struct game_world_tile_map
{
    expand tiles game_world_tile[game_world_width][game_world_width];
}

func get_tile(tile_map game_world_tile_map ref, x s32, y s32) (tile game_world_tile)
{
    if (x < 0) or (x >= game_world_width) or (y < 0) or (y >= game_world_width)
        return game_world_tile.water;
    else
        return tile_map[y][x];
}

struct game_tile_to_sprite
{
    mask       game_tile_mask;
    sprite_id  asset_sprite_id;
    check_mask u16;
}

type game_tile_mask union
{
    expand base game_world_tile[9];

    u64_values u64[2];
};

func get_sprite(tile_map game_world_tile_map ref, x s32, y s32) (id asset_sprite_id)
{
    //if (x < 0) or (x >= game_world_width) or (y < 0) or (y >= game_world_width)
        //return asset_sprite_id.tile_rpgtile029; // water asset_sprite_id.none;

    var mask game_tile_mask;
    loop var i; 9
    {
        var dx = x + (i mod 3) - 1;
        var dy = y + -(i / 3) + 1;
        mask[i] = get_tile(tile_map, dx, dy);
    }

    def check_mask_all   = -1 cast(u16);
    def check_mask_cross = (bit32(1) bit_or bit32(3) bit_or bit32(4) bit_or bit32(5) bit_or bit32(7)) cast(u16);

    var tile_to_sprite_map  =
    [
        // grass surrounded by ground
        {
            [
                game_world_tile.ground, game_world_tile.ground, game_world_tile.ground,
                game_world_tile.ground, game_world_tile.grass, game_world_tile.grass,
                game_world_tile.ground, game_world_tile.grass, game_world_tile.grass,
            ] game_tile_mask,
            asset_sprite_id.tile_rpgtile000,
            check_mask_all
        } game_tile_to_sprite,

        {
            [
                game_world_tile.ground, game_world_tile.ground, game_world_tile.ground,
                game_world_tile.grass, game_world_tile.grass, game_world_tile.grass,
                game_world_tile.grass, game_world_tile.grass, game_world_tile.grass,
            ] game_tile_mask,
            asset_sprite_id.tile_rpgtile001,
            check_mask_cross
        } game_tile_to_sprite,

        {
            [
                game_world_tile.ground, game_world_tile.ground, game_world_tile.ground,
                game_world_tile.grass, game_world_tile.grass, game_world_tile.ground,
                game_world_tile.grass, game_world_tile.grass, game_world_tile.ground,
            ] game_tile_mask,
            asset_sprite_id.tile_rpgtile002,
            check_mask_all
        } game_tile_to_sprite,

        {
            [
                game_world_tile.ground, game_world_tile.grass, game_world_tile.grass,
                game_world_tile.ground, game_world_tile.grass, game_world_tile.grass,
                game_world_tile.ground, game_world_tile.grass, game_world_tile.grass,
            ] game_tile_mask,
            asset_sprite_id.tile_rpgtile018,
            check_mask_cross
        } game_tile_to_sprite,

        {
            [
                game_world_tile.ground, game_world_tile.grass, game_world_tile.grass,
                game_world_tile.ground, game_world_tile.grass, game_world_tile.grass,
                game_world_tile.ground, game_world_tile.ground, game_world_tile.ground,
            ] game_tile_mask,
            asset_sprite_id.tile_rpgtile036,
            check_mask_all
        } game_tile_to_sprite,

        {
            [
                game_world_tile.grass, game_world_tile.grass, game_world_tile.grass,
                game_world_tile.grass, game_world_tile.grass, game_world_tile.grass,
                game_world_tile.ground, game_world_tile.ground, game_world_tile.ground,
            ] game_tile_mask,
            asset_sprite_id.tile_rpgtile037,
            check_mask_cross
        } game_tile_to_sprite,

        {
            [
                game_world_tile.grass, game_world_tile.grass, game_world_tile.ground,
                game_world_tile.grass, game_world_tile.grass, game_world_tile.ground,
                game_world_tile.ground, game_world_tile.ground, game_world_tile.ground,
            ] game_tile_mask,
            asset_sprite_id.tile_rpgtile038,
            check_mask_all
        } game_tile_to_sprite,

        {
            [
                game_world_tile.grass, game_world_tile.grass, game_world_tile.ground,
                game_world_tile.grass, game_world_tile.grass, game_world_tile.ground,
                game_world_tile.grass, game_world_tile.grass, game_world_tile.ground,
            ] game_tile_mask,
            asset_sprite_id.tile_rpgtile020,
            check_mask_cross
        } game_tile_to_sprite,

        {
            [
                game_world_tile.grass, game_world_tile.grass, game_world_tile.grass,
                game_world_tile.grass, game_world_tile.grass, game_world_tile.grass,
                game_world_tile.grass, game_world_tile.grass, game_world_tile.ground,
            ] game_tile_mask,
            asset_sprite_id.tile_rpgtile003,
            check_mask_all
        } game_tile_to_sprite,

        {
            [
                game_world_tile.grass, game_world_tile.grass, game_world_tile.grass,
                game_world_tile.grass, game_world_tile.grass, game_world_tile.grass,
                game_world_tile.ground, game_world_tile.grass, game_world_tile.grass,
            ] game_tile_mask,
            asset_sprite_id.tile_rpgtile004,
            check_mask_all
        } game_tile_to_sprite,

        {
            [
                game_world_tile.grass, game_world_tile.grass, game_world_tile.ground,
                game_world_tile.grass, game_world_tile.grass, game_world_tile.grass,
                game_world_tile.grass, game_world_tile.grass, game_world_tile.grass,
            ] game_tile_mask,
            asset_sprite_id.tile_rpgtile021,
            check_mask_all
        } game_tile_to_sprite,

        {
            [
                game_world_tile.ground, game_world_tile.grass, game_world_tile.grass,
                game_world_tile.grass, game_world_tile.grass, game_world_tile.grass,
                game_world_tile.grass, game_world_tile.grass, game_world_tile.grass,
            ] game_tile_mask,
            asset_sprite_id.tile_rpgtile022,
            check_mask_all
        } game_tile_to_sprite,

        // water surrounded by ground
        {
            [
                game_world_tile.grass, game_world_tile.grass, game_world_tile.grass,
                game_world_tile.grass, game_world_tile.water, game_world_tile.water,
                game_world_tile.grass, game_world_tile.water, game_world_tile.water,
            ] game_tile_mask,
            asset_sprite_id.tile_rpgtile010,
            check_mask_all
        } game_tile_to_sprite,

        {
            [
                game_world_tile.grass, game_world_tile.grass, game_world_tile.grass,
                game_world_tile.water, game_world_tile.water, game_world_tile.water,
                game_world_tile.water, game_world_tile.water, game_world_tile.water,
            ] game_tile_mask,
            asset_sprite_id.tile_rpgtile011,
            check_mask_cross
        } game_tile_to_sprite,

        {
            [
                game_world_tile.grass, game_world_tile.grass, game_world_tile.grass,
                game_world_tile.water, game_world_tile.water, game_world_tile.grass,
                game_world_tile.water, game_world_tile.water, game_world_tile.grass,
            ] game_tile_mask,
            asset_sprite_id.tile_rpgtile012,
            check_mask_all
        } game_tile_to_sprite,

        {
            [
                game_world_tile.grass, game_world_tile.water, game_world_tile.water,
                game_world_tile.grass, game_world_tile.water, game_world_tile.water,
                game_world_tile.grass, game_world_tile.water, game_world_tile.water,
            ] game_tile_mask,
            asset_sprite_id.tile_rpgtile028,
            check_mask_cross
        } game_tile_to_sprite,

        {
            [
                game_world_tile.grass, game_world_tile.water, game_world_tile.water,
                game_world_tile.grass, game_world_tile.water, game_world_tile.water,
                game_world_tile.grass, game_world_tile.grass, game_world_tile.grass,
            ] game_tile_mask,
            asset_sprite_id.tile_rpgtile044,
            check_mask_all
        } game_tile_to_sprite,

        {
            [
                game_world_tile.water, game_world_tile.water, game_world_tile.water,
                game_world_tile.water, game_world_tile.water, game_world_tile.water,
                game_world_tile.grass, game_world_tile.grass, game_world_tile.grass,
            ] game_tile_mask,
            asset_sprite_id.tile_rpgtile045,
            check_mask_cross
        } game_tile_to_sprite,

        {
            [
                game_world_tile.water, game_world_tile.water, game_world_tile.grass,
                game_world_tile.water, game_world_tile.water, game_world_tile.grass,
                game_world_tile.grass, game_world_tile.grass, game_world_tile.grass,
            ] game_tile_mask,
            asset_sprite_id.tile_rpgtile046,
            check_mask_all
        } game_tile_to_sprite,

        {
            [
                game_world_tile.water, game_world_tile.water, game_world_tile.grass,
                game_world_tile.water, game_world_tile.water, game_world_tile.grass,
                game_world_tile.water, game_world_tile.water, game_world_tile.grass,
            ] game_tile_mask,
            asset_sprite_id.tile_rpgtile030,
            check_mask_cross
        } game_tile_to_sprite,

        {
            [
                game_world_tile.water, game_world_tile.water, game_world_tile.water,
                game_world_tile.water, game_world_tile.water, game_world_tile.water,
                game_world_tile.water, game_world_tile.water, game_world_tile.grass,
            ] game_tile_mask,
            asset_sprite_id.tile_rpgtile013,
            check_mask_all
        } game_tile_to_sprite,

        {
            [
                game_world_tile.water, game_world_tile.water, game_world_tile.water,
                game_world_tile.water, game_world_tile.water, game_world_tile.water,
                game_world_tile.grass, game_world_tile.water, game_world_tile.water,
            ] game_tile_mask,
            asset_sprite_id.tile_rpgtile014,
            check_mask_all
        } game_tile_to_sprite,

        {
            [
                game_world_tile.water, game_world_tile.water, game_world_tile.grass,
                game_world_tile.water, game_world_tile.water, game_world_tile.water,
                game_world_tile.water, game_world_tile.water, game_world_tile.water,
            ] game_tile_mask,
            asset_sprite_id.tile_rpgtile031,
            check_mask_all
        } game_tile_to_sprite,

        {
            [
                game_world_tile.grass, game_world_tile.water, game_world_tile.water,
                game_world_tile.water, game_world_tile.water, game_world_tile.water,
                game_world_tile.water, game_world_tile.water, game_world_tile.water,
            ] game_tile_mask,
            asset_sprite_id.tile_rpgtile032,
            check_mask_all
        } game_tile_to_sprite,

    ] game_tile_to_sprite[];

    multiline_comment
    {
    var not_used =
    [
        // ground surrounded by grass
        {
            [
                game_world_tile.grass, game_world_tile.grass, game_world_tile.grass,
                game_world_tile.grass, game_world_tile.ground, game_world_tile.ground,
                game_world_tile.grass, game_world_tile.ground, game_world_tile.ground,
            ] game_tile_mask,
            asset_sprite_id.tile_rpgtile005
        } game_tile_to_sprite,

        {
            [
                game_world_tile.grass, game_world_tile.grass, game_world_tile.grass,
                game_world_tile.ground, game_world_tile.ground, game_world_tile.ground,
                game_world_tile.ground, game_world_tile.ground, game_world_tile.ground,
            ] game_tile_mask,
            asset_sprite_id.tile_rpgtile006
        } game_tile_to_sprite,

        {
            [
                game_world_tile.grass, game_world_tile.grass, game_world_tile.grass,
                game_world_tile.ground, game_world_tile.ground, game_world_tile.grass,
                game_world_tile.ground, game_world_tile.ground, game_world_tile.grass,
            ] game_tile_mask,
            asset_sprite_id.tile_rpgtile007
        } game_tile_to_sprite,

        {
            [
                game_world_tile.grass, game_world_tile.ground, game_world_tile.ground,
                game_world_tile.grass, game_world_tile.ground, game_world_tile.ground,
                game_world_tile.grass, game_world_tile.ground, game_world_tile.ground,
            ] game_tile_mask,
            asset_sprite_id.tile_rpgtile023
        } game_tile_to_sprite,

        {
            [
                game_world_tile.grass, game_world_tile.ground, game_world_tile.ground,
                game_world_tile.grass, game_world_tile.ground, game_world_tile.ground,
                game_world_tile.grass, game_world_tile.grass, game_world_tile.grass,
            ] game_tile_mask,
            asset_sprite_id.tile_rpgtile041
        } game_tile_to_sprite,

        {
            [
                game_world_tile.ground, game_world_tile.ground, game_world_tile.ground,
                game_world_tile.ground, game_world_tile.ground, game_world_tile.ground,
                game_world_tile.grass, game_world_tile.grass, game_world_tile.grass,
            ] game_tile_mask,
            asset_sprite_id.tile_rpgtile042
        } game_tile_to_sprite,

        {
            [
                game_world_tile.ground, game_world_tile.ground, game_world_tile.grass,
                game_world_tile.ground, game_world_tile.ground, game_world_tile.grass,
                game_world_tile.grass, game_world_tile.grass, game_world_tile.grass,
            ] game_tile_mask,
            asset_sprite_id.tile_rpgtile043
        } game_tile_to_sprite,

        {
            [
                game_world_tile.ground, game_world_tile.ground, game_world_tile.grass,
                game_world_tile.ground, game_world_tile.ground, game_world_tile.grass,
                game_world_tile.ground, game_world_tile.ground, game_world_tile.grass,
            ] game_tile_mask,
            asset_sprite_id.tile_rpgtile025
        } game_tile_to_sprite,
    ] game_tile_to_sprite[];
    }

    loop var i; tile_to_sprite_map.count
    {
        var tile_to_sprite = tile_to_sprite_map[i];

        var do_match = true;
        loop var mask_index u32; 9
        {
            if (tile_to_sprite.check_mask bit_and bit32(mask_index)) and (tile_to_sprite.mask[mask_index] is_not mask[mask_index])
            {
                do_match = false;
                break;
            }
        }

        //if (tile_to_sprite_map[i].mask.u64_values[0] is mask.u64_values[0]) and (tile_to_sprite_map[i].mask.u64_values[1] is mask.u64_values[1])

        if do_match
            return tile_to_sprite_map[i].sprite_id;
    }

    var simple_tile_to_sprite_map =
    [
        asset_sprite_id.none,
        asset_sprite_id.tile_rpgtile024,
        asset_sprite_id.tile_rpgtile019,
        asset_sprite_id.tile_rpgtile029,
    ] asset_sprite_id[];

    return simple_tile_to_sprite_map[mask[4]];
}

func update_game_version(platform platform_api ref, tmemory memory_arena ref)
{
    if lang_debug
    {
        var temp_frame = temporary_begin(tmemory);

        def version_git_commit_id_path = "git_commit_id_version.txt";
        def current_git_commit_id_path = "git_commit_id_current.txt";

        var version_git_commit_id string = try_platform_read_entire_file(platform, tmemory, version_git_commit_id_path).data;
        var current_git_commit_id string = try_platform_read_entire_file(platform, tmemory, current_git_commit_id_path).data;

        if current_git_commit_id.count and (version_git_commit_id is_not current_git_commit_id)
        {
            var buffer u8[1024];
            var builder = string_builder_from_buffer(buffer);
            write(builder ref, "// game_version is variable, since we auto detect the version change on program start\n");
            game_version += 1;
            write(builder ref, "var global game_version = % cast(u32); // git commit id %", game_version, current_git_commit_id);

            platform_write_entire_file(platform, "code/version.t", builder.text);
            platform_copy_file(platform, version_git_commit_id_path, current_git_commit_id_path);
        }

        temporary_end(tmemory, temp_frame);
    }
}