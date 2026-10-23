-- Development baseline for the first slice. Not an automatic homelab deployment.
create table public.rundown_versions (
    id uuid primary key default gen_random_uuid(),
    title text not null check (length(title) > 0),
    area text not null,
    summary text not null,
    stops jsonb not null check (jsonb_typeof(stops) = 'array'),
    published boolean not null default false
);
create table public.trips (
    id uuid primary key default gen_random_uuid(),
    owner_id uuid not null references auth.users(id) on delete cascade,
    source_version_id uuid not null references public.rundown_versions(id),
    title text not null,
    starts_at timestamptz not null,
    stops jsonb not null check (jsonb_typeof(stops) = 'array'),
    request_id uuid not null,
    unique (owner_id, request_id)
);

alter table public.rundown_versions enable row level security;
alter table public.trips enable row level security;
revoke all on public.rundown_versions, public.trips from public, anon, authenticated;
grant select on public.rundown_versions to anon, authenticated;
grant select on public.trips to authenticated;
create policy published_catalog on public.rundown_versions for select to anon, authenticated
    using (published);
create policy own_trips on public.trips for select to authenticated
    using ((select auth.uid()) = owner_id);

-- Public access here covers only curated synthetic development content.
-- Creator editing, publishing and production catalog access are later decisions.
create function public.list_rundowns() returns jsonb
language sql stable security invoker set search_path = '' as $$
    select coalesce(jsonb_agg(jsonb_build_object(
        'id', id, 'title', title, 'area', area, 'summary', summary, 'stops', stops
    ) order by title, id), '[]'::jsonb)
    from public.rundown_versions where published;
$$;
create function public.get_rundown(p_version_id uuid) returns jsonb
language plpgsql stable security invoker set search_path = '' as $$
declare result jsonb;
begin
    select jsonb_build_object('id', id, 'title', title, 'area', area,
                             'summary', summary, 'stops', stops)
    into result from public.rundown_versions where id = p_version_id and published;
    if result is null then raise sqlstate 'PT404' using message = 'Published version not found'; end if;
    return result;
end;
$$;
create function public.create_trip(p_version_id uuid, p_starts_at timestamptz, p_request_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
    caller uuid := auth.uid();
    source public.rundown_versions%rowtype;
    result public.trips%rowtype;
begin
    if caller is null then raise sqlstate 'PT401' using message = 'Traveller session required'; end if;
    if p_version_id is null or p_starts_at is null or p_request_id is null then
        raise sqlstate 'PT400' using message = 'Version, start time and request ID are required';
    end if;
    select * into result from public.trips where owner_id = caller and request_id = p_request_id;
    if not found then
        select * into source from public.rundown_versions where id = p_version_id and published;
        if not found then raise sqlstate 'PT404' using message = 'Published version not found'; end if;
        insert into public.trips(owner_id, source_version_id, title, starts_at, stops, request_id)
        values (caller, source.id, source.title, p_starts_at, source.stops, p_request_id)
        on conflict (owner_id, request_id) do nothing returning * into result;
        if not found then
            -- A concurrent request won the unique-key race. Return its result after checking input.
            select * into result from public.trips where owner_id = caller and request_id = p_request_id;
        end if;
    end if;
    if result.source_version_id <> p_version_id or result.starts_at <> p_starts_at then
        raise sqlstate 'PT409' using message = 'Request ID reused with different input';
    end if;
    return jsonb_build_object('id', result.id, 'source_version_id', result.source_version_id,
                             'title', result.title, 'starts_at', result.starts_at, 'stops', result.stops);
end;
$$;
revoke all on function public.list_rundowns() from public, anon, authenticated;
revoke all on function public.get_rundown(uuid) from public, anon, authenticated;
revoke all on function public.create_trip(uuid, timestamptz, uuid) from public, anon, authenticated;
grant execute on function public.list_rundowns(), public.get_rundown(uuid) to anon, authenticated;
grant execute on function public.create_trip(uuid, timestamptz, uuid) to authenticated;
