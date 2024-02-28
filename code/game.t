import random;

def player_movement_speed_idle     = 6;
def player_movement_speed_dragging = 3;

struct game_state
{
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

// COMPILER BUG: somehow sets the type to u8
def max_entity_count = (1 bit_shift_left 14) cast(u32);

def game_world_size = [ 256, 256 ] vec2;

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
        };

        player struct
        {
            sword_hitbox_id      game_entity_id;
            fireball_id          game_entity_id;
            sword_swing_progress f32;

            // send back to client, for better prediction
            movement_speed f32;
        }
    };
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
    // fireball;
    hitbox;
    chicken;
    healing_altar;
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

def max_corpse_lifetime = 10.0;

func update(game game_state ref, delta_seconds f32)
{
    if lang_debug
        debug_game_is_inside_update = true;

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

    // apply dragging to movement
    loop var i u32; game.entity.count
    {
        if game.tag[i] is game_entity_tag.none
            continue;

        var entity = game.entity[i] ref;
        var drag_parent = get(game, entity.drag_parent_id);
        if not drag_parent or not drag_parent.health
            continue;

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
                if sword
                    movement_speed = 0;
                else if get(game, entity.drag_child_id)
                    movement_speed = player_movement_speed_dragging;

                var max_distance = movement_speed * delta_seconds;

                var movement = entity.movement * movement_speed;
                var distance = length(movement);
                var allowed_distance = minimum(max_distance, distance);

                if distance > 0.0
                    movement *= allowed_distance / distance;

                // HACK:
                entity.position += movement;
                entity.movement = movement; // we need it to send predicted position to the clients {} vec2;
                entity.player.movement_speed = movement_speed; // send back to client
            }

            if sword
            {
                // var angle = sword.view_direction; // pi32 * (player.sword_swing_progress - 0.5) + sword.view_direction;
                var angle = pi32 * (player.sword_swing_progress - 0.5) + sword.view_direction;
                var target_position = direction_from_angle(angle) * (entity.collider.radius + sword.collider.radius) + entity.position + entity.collider.center;
                sword.movement = target_position - sword.position;
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
        case game_entity_tag.chicken
        {
            if is_dead
                break;

            var chicken = entity.chicken ref;
            chicken.toggle_moveing_timeout -= delta_seconds;
            if chicken.toggle_moveing_timeout <= 0
            {
                chicken.is_moving = not chicken.is_moving;

                if chicken.is_moving
                {
                    var direction_angle = random_f32_zero_to_one(game.random ref) * pi32 * 2;
                    var direction = [ cos(direction_angle), sin(direction_angle) ] vec2;

                    chicken.toggle_moveing_timeout += random_f32_zero_to_one(game.random ref) * 10 + 0.5;
                    entity.movement = direction;
                }
                else
                {
                    chicken.toggle_moveing_timeout += random_f32_zero_to_one(game.random ref) * 4 + 1;
                    entity.movement = {} vec2;
                }
            }

            if chicken.is_moving
            {
                def chicken_movement_speed = 2.0;
                entity.position += entity.movement * (chicken_movement_speed * delta_seconds);
            }
        }
        case game_entity_tag.healing_altar
        {
            def healing_altar_heals_per_second = 0.25;
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

                    var health = other.health;
                    other.health = minimum(other.health + 1, other.max_health);

                    if other.health is_not health
                        game.do_update_tick_count[other_index] = maximum(game.do_update_tick_count[other_index] cast(u32), 1 cast(u32)) cast(u8);
                }
            }
        }
        else
        {
            entity.position += entity.movement;
            entity.movement = {} vec2;
        }

        // simple world bounds
        check_world_collision(game, entity, delta_seconds);

        // update next two ticks if entity moved
        // this way we send the predicted position and one final rest idle position
        if squared_length(position - entity.position) > 0
            game.do_update_tick_count[i] = 2;
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