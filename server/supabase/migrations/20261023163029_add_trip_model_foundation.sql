-- Stage 3A: identity, destination time and revision, preserving all v1 RPC shapes.
create table public.rundowns (id uuid primary key default gen_random_uuid());
alter table public.rundowns enable row level security;
revoke all on public.rundowns from public, anon, authenticated;
grant select on public.rundowns to anon, authenticated;

alter table public.rundown_versions
    add column rundown_id uuid not null default gen_random_uuid(),
    add column version_no integer not null default 1 check (version_no > 0);
insert into public.rundowns(id) select rundown_id from public.rundown_versions;
alter table public.rundown_versions
    alter column rundown_id drop default,
    add constraint rundown_versions_root_fk foreign key (rundown_id) references public.rundowns(id),
    add constraint rundown_versions_number_unique unique (rundown_id, version_no),
    add constraint rundown_versions_identity_unique unique (rundown_id, id, version_no);
create policy published_rundown_identity on public.rundowns for select to anon, authenticated
    using (exists (select 1 from public.rundown_versions v where v.rundown_id = rundowns.id and v.published));

-- Privileged legacy importers may omit the root when inserting a first version.
create function public.prepare_rundown_identity() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
    if TG_OP = 'INSERT' then
        if new.rundown_id is null then
            insert into public.rundowns default values returning id into new.rundown_id;
        end if;
    elsif new.rundown_id is distinct from old.rundown_id or new.version_no is distinct from old.version_no then
        raise check_violation using message = 'Version identity is immutable';
    end if;
    return new;
end;
$$;
revoke all on function public.prepare_rundown_identity() from public, anon, authenticated;
create trigger prepare_rundown_identity before insert or update on public.rundown_versions
    for each row execute function public.prepare_rundown_identity();

alter table public.trips
    add column source_rundown_id uuid,
    add column source_version_no integer,
    add column time_zone text,
    add column local_start_date date,
    add column revision bigint not null default 1 check (revision > 0),
    add column status text not null default 'planned' check (status = 'planned'),
    add column creation_api_version smallint not null default 1 check (creation_api_version in (1, 2));
update public.trips t set source_rundown_id = v.rundown_id, source_version_no = v.version_no
    from public.rundown_versions v where t.source_version_id = v.id;
alter table public.trips
    alter column source_rundown_id set not null,
    alter column source_version_no set not null,
    add constraint trips_source_identity_fk foreign key (source_rundown_id, source_version_id, source_version_no)
        references public.rundown_versions(rundown_id, id, version_no),
    add constraint trips_destination_date_pair check ((time_zone is null) = (local_start_date is null));

-- No client table writes. This trigger also protects privileged import/maintenance paths.
create function public.prepare_trip_model() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
    if TG_OP = 'INSERT' then
        select rundown_id, version_no into new.source_rundown_id, new.source_version_no
            from public.rundown_versions where id = new.source_version_id;
        new.revision := 1;
    else
        if new.source_version_id is distinct from old.source_version_id
           or new.source_rundown_id is distinct from old.source_rundown_id
           or new.source_version_no is distinct from old.source_version_no
           or new.creation_api_version is distinct from old.creation_api_version then
            raise check_violation using message = 'Trip source identity is immutable';
        end if;
        new.revision := old.revision + 1;
    end if;
    if new.time_zone is null then
        new.local_start_date := null;
    else
        if not exists (select 1 from pg_catalog.pg_timezone_names z
            where z.name = new.time_zone and (z.name = 'UTC' or position('/' in z.name) > 0)
              and z.name not like 'posix/%' and z.name not like 'right/%') then
            raise sqlstate 'PT400' using message = 'A recognized IANA time zone is required';
        end if;
        if not isfinite(new.starts_at) then
            raise check_violation using message = 'Trip start must be finite';
        end if;
        new.local_start_date := (new.starts_at at time zone new.time_zone)::date;
        if new.local_start_date < date '0001-01-01' or new.local_start_date > date '9999-12-31' then
            raise sqlstate 'PT400' using message = 'Local trip date is outside the supported range';
        end if;
    end if;
    return new;
end;
$$;
revoke all on function public.prepare_trip_model() from public, anon, authenticated;
create trigger prepare_trip_model before insert or update on public.trips
    for each row execute function public.prepare_trip_model();

-- V1 retries cannot silently adopt an identically keyed V2 command.
create or replace function public.create_trip(p_version_id uuid, p_starts_at timestamptz, p_request_id uuid)
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
    if result.creation_api_version <> 1 or result.source_version_id <> p_version_id or result.starts_at <> p_starts_at then
        raise sqlstate 'PT409' using message = 'Request ID reused with different input';
    end if;
    return jsonb_build_object('id', result.id, 'source_version_id', result.source_version_id,
                             'title', result.title, 'starts_at', result.starts_at, 'stops', result.stops);
end;
$$;

create function public.get_trip_snapshot_v2(p_trip_id uuid) returns jsonb
language plpgsql stable security invoker set search_path = '' as $$
declare
    caller uuid := auth.uid();
    result jsonb;
begin
    if caller is null then raise sqlstate 'PT401' using message = 'Traveller session required'; end if;
    if p_trip_id is null then raise sqlstate 'PT400' using message = 'Trip ID is required'; end if;
    select jsonb_build_object('schema_version', 2, 'id', t.id,
        'source_version_id', t.source_version_id, 'title', t.title,
        'starts_at', t.starts_at, 'stops', t.stops,
        'source', jsonb_build_object('rundown_id', t.source_rundown_id,
            'version_id', t.source_version_id, 'version_no', t.source_version_no),
        'time_zone', t.time_zone, 'local_start_date', t.local_start_date,
        'revision', t.revision, 'status', t.status) into result
        from public.trips t where t.id = p_trip_id and t.owner_id = caller;
    if result is null then raise sqlstate 'PT404' using message = 'Trip not found'; end if;
    return result;
end;
$$;

create function public.create_trip_v2(p_version_id uuid, p_starts_at timestamptz, p_time_zone text, p_request_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
    caller uuid := auth.uid();
    source public.rundown_versions%rowtype;
    result public.trips%rowtype;
begin
    if caller is null then raise sqlstate 'PT401' using message = 'Traveller session required'; end if;
    if p_version_id is null or p_starts_at is null or p_time_zone is null or p_request_id is null then
        raise sqlstate 'PT400' using message = 'Version, start time, time zone and request ID are required';
    end if;
    if not isfinite(p_starts_at) then
        raise sqlstate 'PT400' using message = 'Trip start must be finite';
    end if;
    select * into result from public.trips where owner_id = caller and request_id = p_request_id;
    if not found then
        select * into source from public.rundown_versions where id = p_version_id and published;
        if not found then raise sqlstate 'PT404' using message = 'Published version not found'; end if;
        insert into public.trips(owner_id, source_version_id, title, starts_at, stops, request_id, time_zone, creation_api_version)
        values (caller, source.id, source.title, p_starts_at, source.stops, p_request_id, p_time_zone, 2)
        on conflict (owner_id, request_id) do nothing returning * into result;
        if not found then
            select * into result from public.trips where owner_id = caller and request_id = p_request_id;
        end if;
    end if;
    if result.creation_api_version <> 2 or result.source_version_id <> p_version_id
       or result.starts_at <> p_starts_at or result.time_zone is distinct from p_time_zone then
        raise sqlstate 'PT409' using message = 'Request ID reused with different input';
    end if;
    return jsonb_build_object('schema_version', 2, 'id', result.id,
        'source_version_id', result.source_version_id, 'title', result.title,
        'starts_at', result.starts_at, 'stops', result.stops,
        'source', jsonb_build_object('rundown_id', result.source_rundown_id,
            'version_id', result.source_version_id, 'version_no', result.source_version_no),
        'time_zone', result.time_zone, 'local_start_date', result.local_start_date,
        'revision', result.revision, 'status', result.status);
end;
$$;

revoke all on function public.get_trip_snapshot_v2(uuid), public.create_trip_v2(uuid,timestamptz,text,uuid)
    from public, anon, authenticated;
grant execute on function public.get_trip_snapshot_v2(uuid), public.create_trip_v2(uuid,timestamptz,text,uuid)
    to authenticated;
