-- Additive owner-scoped reads. Trip snapshots retain the existing wire shape.
alter table public.trips add constraint trips_starts_at_finite check (isfinite(starts_at));
create index trips_owner_starts_id_idx on public.trips (owner_id, starts_at desc, id desc);

create function public.get_trip_snapshot(p_trip_id uuid) returns jsonb
language plpgsql stable security invoker set search_path = '' as $$
declare
    caller uuid := auth.uid();
    result jsonb;
begin
    if caller is null then raise sqlstate 'PT401' using message = 'Traveller session required'; end if;
    if p_trip_id is null then raise sqlstate 'PT400' using message = 'Trip ID is required'; end if;
    select jsonb_build_object('id', id, 'source_version_id', source_version_id,
                             'title', title, 'starts_at', starts_at, 'stops', stops)
    into result from public.trips where id = p_trip_id and owner_id = caller;
    if result is null then raise sqlstate 'PT404' using message = 'Trip not found'; end if;
    return result;
end;
$$;

create function public.list_my_trips(p_limit integer default 20, p_cursor text default null)
returns jsonb language plpgsql stable security invoker set search_path = '' as $$
declare
    caller uuid := auth.uid();
    cursor_payload jsonb;
    cursor_start timestamptz;
    cursor_id uuid;
    result jsonb;
begin
    if caller is null then raise sqlstate 'PT401' using message = 'Traveller session required'; end if;
    if p_limit is null or p_limit < 1 or p_limit > 100 then
        raise sqlstate 'PT400' using message = 'Limit must be between 1 and 100';
    end if;
    if p_cursor is not null then
        begin
            if length(p_cursor) > 512 or p_cursor !~ '^[A-Za-z0-9+/]+={0,2}$' then
                raise sqlstate '22023';
            end if;
            cursor_payload := convert_from(decode(p_cursor, 'base64'), 'UTF8')::jsonb;
            if jsonb_typeof(cursor_payload) is distinct from 'object'
               or cursor_payload->>'v' is distinct from '1'
               or cursor_payload->>'actor' is distinct from caller::text then
                raise sqlstate '22023';
            end if;
            cursor_start := (cursor_payload->>'starts_at')::timestamptz;
            cursor_id := (cursor_payload->>'id')::uuid;
            if cursor_start is null or cursor_id is null or not isfinite(cursor_start) then
                raise sqlstate '22023';
            end if;
        exception when data_exception then
            raise sqlstate 'PT400' using message = 'Invalid trip cursor';
        end;
    end if;

    with page as materialized (
        select id, source_version_id, title, starts_at, stops
        from public.trips
        where owner_id = caller
          and (p_cursor is null or (starts_at, id) < (cursor_start, cursor_id))
        order by starts_at desc, id desc limit p_limit + 1
    ), selected as materialized (
        select * from page order by starts_at desc, id desc limit p_limit
    )
    select jsonb_build_object(
        'items', coalesce((select jsonb_agg(jsonb_build_object(
            'id', id, 'source_version_id', source_version_id, 'title', title,
            'starts_at', starts_at, 'stops', stops) order by starts_at desc, id desc)
            from selected), '[]'::jsonb),
        'next_cursor', case when (select count(*) from page) > p_limit then (
            select replace(encode(convert_to(jsonb_build_object(
                'v', 1, 'actor', caller, 'starts_at', starts_at, 'id', id)::text,
                'UTF8'), 'base64'), E'\n', '')
            from selected order by starts_at asc, id asc limit 1
        ) else null end
    ) into result;
    return result;
end;
$$;

revoke all on function public.get_trip_snapshot(uuid) from public, anon, authenticated;
revoke all on function public.list_my_trips(integer, text) from public, anon, authenticated;
grant execute on function public.get_trip_snapshot(uuid), public.list_my_trips(integer, text) to authenticated;
