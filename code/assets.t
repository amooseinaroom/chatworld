
struct platform_path_string
{
    expand base  u8[platform_max_path_count];
           count u32;
}

func do_something(platform platform_api ref, path string, id_prefix string, tmemory memory_arena ref)
{
    var iterator = platform_file_search_init(platform, path);

    var sprite_relative_paths platform_path_string[];    

    while platform_file_search_next(platform, iterator ref)
    {
        if iterator.found_file.is_directory
            continue;
        
        var split = split_path(iterator.found_file.relative_path);

        if split.extension is_not "png"
            continue;

        reallocate_array(tmemory, sprite_relative_paths ref, sprite_relative_paths.count + 1);
        sprite_relative_paths[sprite_relative_paths.count - 1].count = iterator.found_file.relative_path.count cast(u32);
        copy_bytes(sprite_relative_paths[sprite_relative_paths.count - 1].base.base, iterator.found_file.relative_path.base, iterator.found_file.relative_path.count);
    }	

    var output string;

    write(tmemory, output ref, "\nenum asset_sprite_id\n");
    write(tmemory, output ref, "{\n");
    write(tmemory, output ref, "    none;\n");

    loop var i u32; sprite_relative_paths.count
    {
        var relative_path = { sprite_relative_paths[i].count, sprite_relative_paths[i].base.base } string;
        var split = split_path(relative_path);
        latin_to_lower_case(split.name);    

        var id_name = write(tmemory, output ref, "    %_%;\n", id_prefix, split.name);
        // COMPILER BUG:
        var debug_ok = id_name is_not "none";
        assert(debug_ok);
    }

    write(tmemory, output ref, "}\n");    

    write(tmemory, output ref, "\ndef asset_sprite_paths =\n");
    write(tmemory, output ref, "[\n");

    loop var i u32; sprite_relative_paths.count
    {
        var relative_path = { sprite_relative_paths[i].count, sprite_relative_paths[i].base.base } string;        
        write(tmemory, output ref, "    \"%\",\n", relative_path);
    }

    write(tmemory, output ref, "] string[];\n");    

    platform_write_entire_file(platform, "code/generated_assets.t", output);
}
