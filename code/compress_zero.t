
struct compress_zero_buffer
{
    expand base               u8[];
           used_count         u32;
           pending_zero_count u32;

           packet_count            u32;
           byte_count              u32;
           compressed_packet_count u32;
           compressed_byte_count   u32;
}

func send_packet(buffer compress_zero_buffer ref, data u8[])
{
    if not compress_zero(buffer, data)
    {
        buffer.compressed_packet_count += 1;
        buffer.compressed_byte_count   += buffer.used_count;

        if buffer.pending_zero_count
        {
            assert(buffer.pending_zero_count <= 256);
            buffer.compressed_byte_count += 2;
        }

        buffer.pending_zero_count = 0;
        buffer.used_count         = 0;

        var ok = compress_zero(buffer, data);
        assert(ok);
    }

    buffer.packet_count += 1;
    buffer.byte_count   += data.count cast(u32);
}

func compress_zero(buffer compress_zero_buffer ref, data u8[]) (ok b8)
{
    var buffer_used_count  = buffer.used_count;
    var pending_zero_count = buffer.pending_zero_count;
    loop var i usize; data.count
    {
        var byte = data[i];

        if byte is_not 0
        {
            if pending_zero_count
            {
                assert(pending_zero_count <= 256);

                if (buffer_used_count + 2) > buffer.count
                    return false;

                buffer[buffer_used_count] = 0;
                buffer[buffer_used_count + 1] = (pending_zero_count - 1) cast(u8);
                buffer_used_count += 2;
            }

            if (buffer_used_count + 1) > buffer.count
                return false;

            buffer[buffer_used_count] = byte;
            buffer_used_count += 1;
        }
        else
        {
            if pending_zero_count is 256
            {
                if (buffer_used_count + 2) > buffer.count
                    return false;

                buffer[buffer_used_count]     = 0;
                buffer[buffer_used_count + 1] = 255;
                buffer_used_count += 2;

                pending_zero_count -= 256;
            }

            pending_zero_count += 1;
        }
    }

    if pending_zero_count and ((buffer_used_count + 2) > buffer.count)
        return false;

    buffer.used_count         = buffer_used_count;
    buffer.pending_zero_count = pending_zero_count;

    return true;
}

struct compress_repeat_state
{
    used_byte_count u32;
    repeat_count    u16;
    repeat_byte     u8;
}

func compress_next(state compress_repeat_state ref, buffer u8[], data u8[]) (ok b8)
{
    var new_state = state deref;

    if data.count and (new_state.used_byte_count is 0)
    {
        assert(new_state.repeat_count is 0);
        new_state.repeat_byte = data[0];
    }

    loop var i u32; data.count
    {
        var byte = data[i];
        if byte is new_state.repeat_byte
        {
            // wrap around
            if new_state.repeat_count is 256
            {
                if (new_state.used_byte_count + 2) > buffer.count
                    return false;

                buffer[new_state.used_byte_count] = 255; // stores repeat_count - 1
                buffer[new_state.used_byte_count + 1] = new_state.repeat_byte;
                new_state.used_byte_count += 2;

                new_state.repeat_count = 0;
            }

            new_state.repeat_count += 1;
            assert((new_state.repeat_count > 0) and (new_state.repeat_count <= 256));
        }
        else
        {
            if (new_state.used_byte_count + 2) > buffer.count
                return false;

            assert((new_state.repeat_count > 0) and (new_state.repeat_count <= 256));
            buffer[new_state.used_byte_count]     = (new_state.repeat_count - 1) cast(u8);
            buffer[new_state.used_byte_count + 1] = new_state.repeat_byte;
            new_state.used_byte_count += 2;

            new_state.repeat_count = 1;
            new_state.repeat_byte  = byte;
        }
    }

    // if the last pair would fit we failed also
    // but we do not write it yet, since the next message may repeat the current repeat_byte
    if new_state.repeat_count and ((new_state.used_byte_count + 2) > buffer.count)
        return false;

    state deref = new_state;

    return true;
}

func compress_end(state compress_repeat_state ref, buffer u8[]) (byte_count u32)
{
    if state.repeat_count
    {
        assert(state.repeat_count <= 256);
        assert((state.used_byte_count + 2) <= buffer.count);
        buffer[state.used_byte_count]     = (state.repeat_count - 1) cast(u8);
        buffer[state.used_byte_count + 1] = state.repeat_byte;

        state.used_byte_count += 2;
    }

    var byte_count = state.used_byte_count;

    state deref = {} compress_repeat_state;

    return byte_count;
}

func decompress_repeat(buffer u8[], iterator u8[] ref) (ok b8, byte_count u32)
{
    var byte_count u32;

    // data is pairs of repeat_count and repeat_byte,
    // so it needs to be an even count
    if iterator.count bit_and 1
        return false, 0;

    while iterator.count
    {
        var repeat_count = iterator[0] cast(u32) + 1;
        var repeat_byte  = iterator[1];

        if (byte_count + repeat_count) > buffer.count
        {
            assert(byte_count <= buffer.count);
            var fitting_repeat_count = buffer.count cast(u32) - byte_count;

            loop var repeat u32; fitting_repeat_count
                buffer[byte_count + repeat] = repeat_byte;

            byte_count += fitting_repeat_count;

            assert(fitting_repeat_count < repeat_count);
            iterator[0] = (repeat_count - fitting_repeat_count - 1) cast(u8);

            return true, byte_count;
        }

        advance(iterator, 2);

        loop var repeat u32; repeat_count
            buffer[byte_count + repeat] = repeat_byte;

        byte_count += repeat_count;
    }

    return true, byte_count;
}