
struct asset_path
{
    expand base  u8[platform_max_path_count];
           count u32;

    id_prefix string;
}

func to_string(path asset_path) (text string)
{
    return { path.count, path.base.base } string;
}

func asset_paths_append(paths asset_path[] ref, platform platform_api ref, path string, id_prefix string, tmemory memory_arena ref)
{
    var iterator = platform_file_search_init(platform, path);

    while platform_file_search_next(platform, iterator ref)
    {
        if iterator.found_file.is_directory
            continue;

        var split = split_path(iterator.found_file.relative_path);

        if split.extension is_not "png"
            continue;

        reallocate_array(tmemory, paths, paths.count + 1);
        var buffer = paths[paths.count - 1] ref;
        var builder = string_builder_from_buffer(buffer.base);
        write(builder ref, "%", iterator.found_file.relative_path);
        buffer.count = builder.text.count cast(u32);
        buffer.id_prefix = id_prefix;
    }
}

func asset_generate_sprite_ids(paths asset_path[], platform platform_api ref, tmemory memory_arena ref)
{
    var output string;

    write(tmemory, output ref, "\nenum asset_sprite_id\n");
    write(tmemory, output ref, "{\n");
    write(tmemory, output ref, "    none;\n");

    loop var i u32; paths.count
    {
        var path = to_string(paths[i]);
        var split = split_path(path);
        latin_to_lower_case(split.name);

        var id_name = write(tmemory, output ref, "    %_%;\n", paths[i].id_prefix, split.name);
        // COMPILER BUG:
        var debug_ok = id_name is_not "none";
        assert(debug_ok);
    }

    write(tmemory, output ref, "}\n");

    write(tmemory, output ref, "\ndef asset_sprite_paths =\n");
    write(tmemory, output ref, "[\n");

    loop var i u32; paths.count
    {
        var path = to_string(paths[i]);
        write(tmemory, output ref, "    \"%\",\n", path);
    }

    write(tmemory, output ref, "] string[];\n");

    platform_write_entire_file(platform, "code/generated_assets.t", output);
}
