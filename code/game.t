import random;

def player_movement_speed = 6;

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
    active       b8[max_entity_count];
    network_id   u32[max_entity_count];
    do_delete    b8[max_entity_count];
    entity       game_entity[max_entity_count];

    // server only maybe
    do_update_tick_count u8[max_entity_count];
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
    tag      game_entity_tag;
    position vec2;
    movement vec2;
    collider sphere2;

    expand tags union
    {
        fireball struct
        {
            lifetime f32;
        };

        chicken struct
        {
            is_moving              b8;
            toggle_moveing_timeout f32;
        };
    };
}

enum game_entity_tag
{
    player;
    fireball;
    chicken;
}

func init(game game_state ref, random random_pcg)
{
    clear_value(game);

    loop var i u32; game.freelist.count
        game.freelist[i] = i;

    game.random = random;
}

func add(game game_state ref, tag game_entity_tag, network_id u32) (id game_entity_id)
{
    assert(tag < game_entity_tag.count);

    assert(game.entity_count < game.entity.count);
    var index = game.freelist[game.entity_count];
    game.entity_count += 1;

    game.entity_tag_count[tag] += 1;

    game.generation[index] += 1;
    game.entity[index] = {} game_entity;
    game.entity[index].tag = tag;
    game.network_id[index] = network_id;

    assert(not game.active[index]);
    game.active[index] = true;
    game.do_delete[index] = false;

    var id game_entity_id;
    id.index_plus_one = index + 1;
    id.generation = game.generation[index];
    return id;
}

func add_player(game game_state ref, network_id u32) (id game_entity_id)
{
    var id = add(game, game_entity_tag.player, network_id);
    var entity = get(game, id);

    // this is set so that it aligns well with the sprites
    var radius = 0.375;
    entity.collider = { [ 0, 0.0625 + radius ] vec2, radius } sphere2;

    return id;
}

func add_fireball(game game_state ref, network_id u32, position vec2, movement vec2)
{
    var id = add(game, game_entity_tag.fireball, network_id);
    var entity = get(game, id);
    entity.collider = { {} vec2, 0.25 } sphere2;
    entity.position = position;
    entity.movement = movement;
    entity.fireball.lifetime = 4;
}

func add_chicken(game game_state ref, network_id u32, position vec2)
{
    var id = add(game, game_entity_tag.chicken, network_id);
    var entity = get(game, id);
    entity.collider = { {} vec2, 0.333 } sphere2;
    entity.position = position;
}

func remove(game game_state ref, id game_entity_id)
{
    assert(id.index_plus_one and (id.index_plus_one <= game.entity.count));

    var index = id.index_plus_one - 1;
    assert(not game.do_delete[index]);
    game.do_delete[index] = true;
}

func remove_for_real(game game_state ref, id game_entity_id)
{
    assert(id.index_plus_one and (id.index_plus_one <= game.entity.count));

    var index = id.index_plus_one - 1;

    assert(game.active[index]);
    game.active[index] = false;

    var tag = game.entity[index].tag;
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

    assert(game.active[index]);

    return game.entity[index] ref;
}

func update(game game_state ref, delta_seconds f32)
{
    loop var i u32; game.entity.count
    {
        if not game.active[i]
            continue;

        if game.do_delete[i]
        {
            remove_for_real(game, { i + 1, game.generation[i] } game_entity_id);
            continue;
        }

        var entity = game.entity[i] ref;

        var position = entity.position;

        switch entity.tag
        case game_entity_tag.fireball
        {
            entity.position += entity.movement * delta_seconds;
            entity.fireball.lifetime -= delta_seconds;
            if entity.fireball.lifetime <= 0
            {
                remove(game, { i + 1, game.generation[i] } game_entity_id);
                continue;
            }
        }
        case game_entity_tag.player
        {
            var max_distance = player_movement_speed * delta_seconds;
            var distance = squared_length(entity.movement);
            var allowed_distance = minimum(max_distance, distance);
            var movement vec2;

            if distance > 0.0
                movement = entity.movement * (allowed_distance / distance);

            // HACK:
            entity.position += movement;
            entity.movement = movement; // we need it to send predicted position to the clients {} vec2;
        }
        case game_entity_tag.chicken
        {
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
        else
        {
            entity.position += entity.movement;
            entity.movement = {} vec2;
        }

        // simple world bounds
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

        // update next two ticks if entity moved
        // this way we send the predicted position and one final rest idle position
        if squared_length(position - entity.position) > 0
            game.do_update_tick_count[i] = 2;
        else if game.do_update_tick_count[i]
            game.do_update_tick_count[i] -= 1;
    }
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