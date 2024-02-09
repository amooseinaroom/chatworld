
struct game_state
{
    camera_position vec2;
    camera_zoom     f32;

    is_chatting b8;

    // entity manager    

    generation   u32[max_entity_count];
    active       b8[max_entity_count];
    network_id   u32[max_entity_count];
    do_update    b8[max_entity_count];
    do_delete    b8[max_entity_count];
    entity       game_entity[max_entity_count];

    freelist     u32[max_entity_count];
    entity_count u32;    
}

// COMPILER BUG: somehow sets the type to u8
def max_entity_count = (1 bit_shift_left 14) cast(u32);

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
    lifetime f32;
}

enum game_entity_tag
{
    player;
    fireball;
}

func init(game game_state ref)
{
    loop var i u32; game.freelist.count    
        game.freelist[i] = i;    
}

func add(game game_state ref, tag game_entity_tag, network_id u32) (id game_entity_id)
{
    assert(tag < game_entity_tag.count);

    assert(game.entity_count < game.entity.count);
    var index = game.freelist[game.entity_count];
    game.entity_count += 1;

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
    entity.collider = { [ 0, 0.5 ] vec2, 0.5 } sphere2;
    
    return id;
}

func add_fireball(game game_state ref, network_id u32, position vec2, movement vec2)
{
    var id = add(game, game_entity_tag.fireball, network_id);
    var entity = get(game, id);
    entity.collider = { {} vec2, 0.25 } sphere2;
    entity.position = position;
    entity.movement = movement;
    entity.lifetime = 4;
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
            entity.lifetime -= delta_seconds;
            if entity.lifetime <= 0
            {                
                remove(game, { i + 1, game.generation[i] } game_entity_id);
                continue;
            }
        }
        else
        {
            entity.position += entity.movement;        
            entity.movement = {} vec2;
        }

        game.do_update[i] = squared_length(position - entity.position) > 0;        
    }
}