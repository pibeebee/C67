-- Stage 3B: immutable normalized snapshots; legacy wire shapes are unchanged.
-- CASE guards prevent malformed JSON from reaching unsafe casts.
create function public.is_graph_point(p jsonb) returns boolean
language plpgsql immutable security invoker set search_path = '' as $$
begin
 if jsonb_typeof(p) is distinct from 'object' then return false; end if;
 if not p ?& array['latitude','longitude'] or exists(select 1 from jsonb_object_keys(p) k where k not in ('latitude','longitude','label')) then return false; end if;
 if jsonb_typeof(p->'latitude') is distinct from 'number' or jsonb_typeof(p->'longitude') is distinct from 'number' then return false; end if;
 return (p->>'latitude')::numeric between -90 and 90 and (p->>'longitude')::numeric between -180 and 180
  and (not p ? 'label' or (jsonb_typeof(p->'label')='string' and length(p->>'label') between 1 and 200));
end;
$$;
revoke all on function public.is_graph_point(jsonb) from public,anon,authenticated,service_role;

alter table public.rundown_versions add column route_template jsonb;
alter table public.trips
 add column creation_origin jsonb,
 add column creation_start_basis text not null default 'unspecified'
  check (creation_start_basis in ('unspecified','departure_origin','start_at_landing'));
alter table public.trips drop constraint trips_creation_api_version_check;
alter table public.trips add constraint trips_creation_api_version_check check (creation_api_version in (1,2,3));

create function public.validate_route_template(stops jsonb, route jsonb) returns void
language plpgsql security invoker set search_path = '' as $$
declare s jsonb; d jsonb; l jsonb; pos integer; ids uuid[] := '{}'::uuid[]; seen uuid[] := '{}'::uuid[]; sid uuid; f uuid; t uuid; edge_keys text[] := '{}'::text[]; leg_ids uuid[] := '{}'::uuid[]; leg_id uuid; ek text;
begin
 if jsonb_typeof(stops) is distinct from 'array' then raise check_violation using message='Invalid stop snapshot'; end if;
 pos := 0;
 for s in select value from jsonb_array_elements(stops) loop
  if jsonb_typeof(s) is distinct from 'object' or jsonb_typeof(s->'id') is distinct from 'string'
   or jsonb_typeof(s->'title') is distinct from 'string' or length(s->>'title')=0
   or jsonb_typeof(s->'order') is distinct from 'number' or (s->>'order')::numeric <> pos then
   raise check_violation using message='Invalid stop snapshot';
  end if;
  sid := (s->>'id')::uuid;
  if sid=any(ids) then raise check_violation using message='Duplicate source stop identity'; end if;
  ids := array_append(ids,sid); pos := pos+1;
 end loop;
 if route is null then return; end if;
 if jsonb_typeof(route) is distinct from 'object' or exists(select 1 from jsonb_object_keys(route) k where k not in ('landing','stop_details','legs')) then
  raise check_violation using message='Invalid route template';
 end if;
 d := route->'landing';
 if d is not null and d <> 'null'::jsonb then
  if jsonb_typeof(d) is distinct from 'object' then raise check_violation using message='Invalid landing'; end if;
  if d->>'kind'='first_stop' then
   if cardinality(ids)=0 or d <> '{"kind":"first_stop"}'::jsonb then raise check_violation using message='Invalid first-stop landing'; end if;
  elsif d->>'kind'='separate' then
   if not public.is_graph_point(d->'location') or exists(select 1 from jsonb_object_keys(d) k where k not in ('kind','location')) then raise check_violation using message='Invalid separate landing'; end if;
  else raise check_violation using message='Invalid landing kind'; end if;
 end if;
 if route ? 'stop_details' and jsonb_typeof(route->'stop_details') is distinct from 'array' then raise check_violation using message='Invalid stop details'; end if;
 for d in select value from jsonb_array_elements(coalesce(route->'stop_details','[]')) loop
  if jsonb_typeof(d) is distinct from 'object' then raise check_violation using message='Invalid stop details'; end if;
  sid := (d->>'source_stop_id')::uuid;
  if sid is null or not sid=any(ids) or sid=any(seen) or exists(select 1 from jsonb_object_keys(d) k where k not in ('source_stop_id','location','visit_duration_seconds','time_zone')) then
   raise check_violation using message='Invalid stop detail identity'; end if;
  seen := array_append(seen,sid);
  if d ? 'location' and d->'location'<>'null'::jsonb and not public.is_graph_point(d->'location') then raise check_violation using message='Invalid stop location'; end if;
  if d ? 'visit_duration_seconds' and d->'visit_duration_seconds'<>'null'::jsonb then
   if jsonb_typeof(d->'visit_duration_seconds') is distinct from 'number' then raise check_violation using message='Invalid visit duration'; end if;
   if (d->>'visit_duration_seconds')::numeric<0 or (d->>'visit_duration_seconds')::numeric<>trunc((d->>'visit_duration_seconds')::numeric) or (d->>'visit_duration_seconds')::numeric>2147483647 then raise check_violation using message='Invalid visit duration'; end if;
  end if;
  if d ? 'time_zone' and d->'time_zone'<>'null'::jsonb then
   if not exists(select 1 from pg_catalog.pg_timezone_names z where z.name=d->>'time_zone' and (z.name='UTC' or position('/' in z.name)>0) and z.name not like 'posix/%' and z.name not like 'right/%') then raise check_violation using message='Invalid stop time zone'; end if;
  end if;
 end loop;
 if route ? 'legs' and jsonb_typeof(route->'legs') is distinct from 'array' then raise check_violation using message='Invalid route legs'; end if;
 for l in select value from jsonb_array_elements(coalesce(route->'legs','[]')) loop
  if jsonb_typeof(l) is distinct from 'object' then raise check_violation using message='Invalid route leg'; end if;
  if exists(select 1 from jsonb_object_keys(l) k where k not in ('id','kind','from_stop_id','to_stop_id','transport_mode','duration_seconds')) or l->>'id' is null then raise check_violation using message='Invalid route leg fields'; end if;
  leg_id := (l->>'id')::uuid;
  if leg_id=any(leg_ids) then raise check_violation using message='Duplicate source leg identity'; end if;
  leg_ids:=array_append(leg_ids,leg_id);
  f := (l->>'from_stop_id')::uuid; t := (l->>'to_stop_id')::uuid;
  if l->>'kind'='landing_to_first' then
   if route->'landing'->>'kind' is distinct from 'separate' or f is not null or t is distinct from ids[1] then raise check_violation using message='Invalid landing-to-first endpoints'; end if;
  elsif l->>'kind'='between_stops' then
   if f is null or t is null or array_position(ids,f) is null or array_position(ids,t) is distinct from array_position(ids,f)+1 then raise check_violation using message='Invalid adjacent-stop endpoints'; end if;
  else raise check_violation using message='Invalid route leg kind'; end if;
  ek := (l->>'kind')||':'||coalesce(f::text,'')||':'||t::text;
  if ek=any(edge_keys) then raise check_violation using message='Duplicate route edge'; end if;
  edge_keys := array_append(edge_keys,ek);
  if l ? 'transport_mode' and (l->>'transport_mode') is not null and l->>'transport_mode' not in ('walk','drive','transit','other','unknown') then raise check_violation using message='Invalid transport mode'; end if;
  if l ? 'duration_seconds' and l->'duration_seconds'<>'null'::jsonb then
   if jsonb_typeof(l->'duration_seconds') is distinct from 'number' then raise check_violation using message='Invalid leg duration'; end if;
   if (l->>'duration_seconds')::numeric<0 or (l->>'duration_seconds')::numeric<>trunc((l->>'duration_seconds')::numeric) or (l->>'duration_seconds')::numeric>2147483647 then raise check_violation using message='Invalid leg duration'; end if;
  end if;
 end loop;
exception when data_exception then raise check_violation using message='Malformed route or stop value';
end;
$$;
revoke all on function public.validate_route_template(jsonb,jsonb) from public,anon,authenticated,service_role;
create function public.check_version_route() returns trigger language plpgsql security definer set search_path='' as $$
begin perform public.validate_route_template(new.stops,new.route_template); return new; end;
$$;
revoke all on function public.check_version_route() from public,anon,authenticated,service_role;
create trigger check_version_route before insert or update of stops,route_template on public.rundown_versions for each row execute function public.check_version_route();
do $$ declare v record; begin for v in select stops,route_template from public.rundown_versions loop perform public.validate_route_template(v.stops,v.route_template); end loop; end $$;

create table public.trip_sources (
 id uuid primary key default gen_random_uuid(), trip_id uuid not null references public.trips(id) on delete cascade,
 rundown_id uuid not null, version_id uuid not null, version_no integer not null, title text not null,
 foreign key(rundown_id,version_id,version_no) references public.rundown_versions(rundown_id,id,version_no), unique(trip_id,id)
);
create table public.trip_days (
 id uuid primary key default gen_random_uuid(), trip_id uuid not null references public.trips(id) on delete cascade,
 day_index integer not null check(day_index=0), starts_at timestamptz not null,
 time_zone text, local_date date, start_time_basis text not null check(start_time_basis in ('unspecified','departure_origin','start_at_landing')),
 origin jsonb check(origin is null or public.is_graph_point(origin)),
 landing_kind text not null check(landing_kind in ('unknown','first_stop','separate')),
 landing_location jsonb check(landing_location is null or public.is_graph_point(landing_location)), landing_trip_stop_id uuid,
 check((time_zone is null)=(local_date is null)),
 check((start_time_basis='departure_origin')=(origin is not null)),
 check((landing_kind='first_stop')=(landing_trip_stop_id is not null)),
 check(landing_kind<>'separate' or landing_location is not null),
 check(landing_kind<>'unknown' or landing_location is null),
 unique(trip_id,id), unique(trip_id,day_index)
);
create table public.trip_stops (
 id uuid primary key, trip_id uuid not null references public.trips(id) on delete cascade,
 day_id uuid not null, source_id uuid not null, source_stop_id uuid not null,
 position integer not null check(position>=0), title text not null,
 location jsonb check(location is null or public.is_graph_point(location)), time_zone text,
 visit_duration_seconds integer check(visit_duration_seconds>=0), progress_status text not null default 'not_started' check(progress_status='not_started'),
 foreign key(trip_id,day_id) references public.trip_days(trip_id,id) on delete cascade,
 foreign key(trip_id,source_id) references public.trip_sources(trip_id,id),
 unique(trip_id,id), unique(trip_id,day_id,id), unique(day_id,position)
);
alter table public.trip_days add constraint trip_day_landing_stop_fk foreign key(trip_id,landing_trip_stop_id)
 references public.trip_stops(trip_id,id) deferrable initially deferred;
create table public.trip_legs (
 id uuid primary key default gen_random_uuid(), trip_id uuid not null references public.trips(id) on delete cascade,
 day_id uuid not null, position integer not null check(position>=0), kind text not null check(kind in ('access','landing_to_first','between_stops')),
 from_trip_stop_id uuid, to_trip_stop_id uuid, transport_mode text not null default 'unknown' check(transport_mode in ('walk','drive','transit','other','unknown')),
 duration_seconds integer check(duration_seconds>=0), source_leg_id uuid,
 estimate_origin text not null check(estimate_origin in ('creator','unknown')),
 foreign key(trip_id,day_id) references public.trip_days(trip_id,id) on delete cascade,
 foreign key(trip_id,day_id,from_trip_stop_id) references public.trip_stops(trip_id,day_id,id),
 foreign key(trip_id,day_id,to_trip_stop_id) references public.trip_stops(trip_id,day_id,id),
 check((kind='access' and from_trip_stop_id is null and to_trip_stop_id is null)
  or (kind='landing_to_first' and from_trip_stop_id is null and to_trip_stop_id is not null)
  or (kind='between_stops' and from_trip_stop_id is not null and to_trip_stop_id is not null and from_trip_stop_id<>to_trip_stop_id)),
 unique(day_id,position)
);
alter table public.trip_sources enable row level security;
revoke all on public.trip_sources from public,anon,authenticated;
grant select on public.trip_sources to authenticated;
create policy own_graph on public.trip_sources for select to authenticated
 using(exists(select 1 from public.trips t where t.id=trip_id and t.owner_id=(select auth.uid())));
alter table public.trip_days enable row level security;
revoke all on public.trip_days from public,anon,authenticated;
grant select on public.trip_days to authenticated;
create policy own_graph on public.trip_days for select to authenticated
 using(exists(select 1 from public.trips t where t.id=trip_id and t.owner_id=(select auth.uid())));
alter table public.trip_stops enable row level security;
revoke all on public.trip_stops from public,anon,authenticated;
grant select on public.trip_stops to authenticated;
create policy own_graph on public.trip_stops for select to authenticated
 using(exists(select 1 from public.trips t where t.id=trip_id and t.owner_id=(select auth.uid())));
alter table public.trip_legs enable row level security;
revoke all on public.trip_legs from public,anon,authenticated;
grant select on public.trip_legs to authenticated;
create policy own_graph on public.trip_legs for select to authenticated
 using(exists(select 1 from public.trips t where t.id=trip_id and t.owner_id=(select auth.uid())));

create index trip_legs_trip_day_position_idx on public.trip_legs(trip_id,day_id,position);

create function public.guard_trip_graph_write() returns trigger language plpgsql security definer set search_path='' as $$
declare target uuid;
begin
 target := case when TG_OP='DELETE' then old.trip_id else new.trip_id end;
 if TG_OP='DELETE' and not exists(select 1 from public.trips where id=target) then return old; end if;
 if TG_OP='INSERT' and current_setting('c67.graph_build_trip',true)=target::text then return new; end if;
 raise insufficient_privilege using message='Trip graph is immutable; use a graph command';
end;
$$;
revoke all on function public.guard_trip_graph_write() from public,anon,authenticated,service_role;
create trigger guard_trip_graph_write before insert or update or delete on public.trip_sources for each row execute function public.guard_trip_graph_write();
create trigger guard_trip_graph_write before insert or update or delete on public.trip_days for each row execute function public.guard_trip_graph_write();
create trigger guard_trip_graph_write before insert or update or delete on public.trip_stops for each row execute function public.guard_trip_graph_write();
create trigger guard_trip_graph_write before insert or update or delete on public.trip_legs for each row execute function public.guard_trip_graph_write();

create function public.check_trip_leg_semantics() returns trigger
language plpgsql security definer set search_path='' as $$
declare d public.trip_days%rowtype; f integer; t integer;
begin
 select * into d from public.trip_days where trip_id=new.trip_id and id=new.day_id;
 if not found then return new; end if; -- Composite FK reports unknown day/stop identities.
 if new.kind='access' and (d.origin is null or d.landing_kind='unknown') then
  raise check_violation using message='Access requires origin and landing';
 elsif new.kind='landing_to_first' then
  select position into t from public.trip_stops where trip_id=new.trip_id and day_id=new.day_id and id=new.to_trip_stop_id;
  if d.landing_kind<>'separate' or (t is not null and t<>0) then raise check_violation using message='Landing leg must reach first stop'; end if;
 elsif new.kind='between_stops' then
  select position into f from public.trip_stops where trip_id=new.trip_id and day_id=new.day_id and id=new.from_trip_stop_id;
  select position into t from public.trip_stops where trip_id=new.trip_id and day_id=new.day_id and id=new.to_trip_stop_id;
  if f is not null and t is not null and t<>f+1 then raise check_violation using message='Leg must connect adjacent stops'; end if;
 end if;
 return new;
end;
$$;
revoke all on function public.check_trip_leg_semantics() from public,anon,authenticated,service_role;
create trigger check_trip_leg_semantics before insert on public.trip_legs for each row execute function public.check_trip_leg_semantics();

create function public.populate_trip_graph(target uuid, use_source_route boolean) returns void
language plpgsql security definer set search_path='' as $$
declare t public.trips%rowtype; route jsonb; source_id uuid:=gen_random_uuid(); day_id uuid:=gen_random_uuid();
 s jsonb; detail jsonb; leg jsonb; ids uuid[]:='{}'::uuid[]; mapped uuid[]:='{}'::uuid[]; n integer; i integer; position integer:=0;
 landing_kind text; landing_location jsonb; previous_setting text:=current_setting('c67.graph_build_trip',true);
begin
 select * into strict t from public.trips where id=target for update;
 if exists(select 1 from public.trip_days where trip_id=target) then raise check_violation using message='Trip graph already exists'; end if;
 if use_source_route then select route_template into route from public.rundown_versions where id=t.source_version_id for share; end if;
 perform public.validate_route_template(t.stops,route);
 for s in select value from jsonb_array_elements(t.stops) loop
  ids:=array_append(ids,(s->>'id')::uuid); mapped:=array_append(mapped,gen_random_uuid());
 end loop;
 n:=cardinality(ids); landing_kind:=coalesce(route->'landing'->>'kind','unknown');
 if landing_kind='separate' then landing_location:=route->'landing'->'location';
 elsif landing_kind='first_stop' then
  select nullif(d->'location','null'::jsonb) into landing_location from jsonb_array_elements(coalesce(route->'stop_details','[]')) d where d->>'source_stop_id'=ids[1]::text;
 end if;
 if t.creation_start_basis='departure_origin' and (t.creation_origin is null or landing_kind='unknown') then raise sqlstate 'PT400' using message='Departure origin requires an origin and explicit source landing'; end if;
 if t.creation_start_basis<>'departure_origin' and t.creation_origin is not null then raise sqlstate 'PT400' using message='Origin is only accepted for departure_origin'; end if;
 if t.creation_start_basis='start_at_landing' and landing_kind='unknown' then raise sqlstate 'PT400' using message='Start at landing requires an explicit source landing'; end if;
 if t.creation_origin is not null and not public.is_graph_point(t.creation_origin) then raise sqlstate 'PT400' using message='Invalid origin point'; end if;
 perform set_config('c67.graph_build_trip',target::text,true);
 insert into public.trip_sources(id,trip_id,rundown_id,version_id,version_no,title) values(source_id,target,t.source_rundown_id,t.source_version_id,t.source_version_no,t.title);
 insert into public.trip_days(id,trip_id,day_index,starts_at,time_zone,local_date,start_time_basis,origin,landing_kind,landing_location,landing_trip_stop_id)
 values(day_id,target,0,t.starts_at,t.time_zone,t.local_start_date,t.creation_start_basis,t.creation_origin,landing_kind,landing_location,case when landing_kind='first_stop' then mapped[1] else null end);
 i:=0;
 for s in select value from jsonb_array_elements(t.stops) loop
  i:=i+1; detail:=null;
  select d into detail from jsonb_array_elements(coalesce(route->'stop_details','[]')) d where d->>'source_stop_id'=ids[i]::text;
  insert into public.trip_stops(id,trip_id,day_id,source_id,source_stop_id,position,title,location,time_zone,visit_duration_seconds)
  values(mapped[i],target,day_id,source_id,ids[i],i-1,s->>'title',nullif(detail->'location','null'::jsonb),detail->>'time_zone',(detail->>'visit_duration_seconds')::numeric::integer);
 end loop;
 if t.creation_origin is not null then
  insert into public.trip_legs(trip_id,day_id,position,kind,estimate_origin) values(target,day_id,position,'access','unknown'); position:=position+1;
 end if;
 if landing_kind='separate' and n>0 then
  leg:=null; select l into leg from jsonb_array_elements(coalesce(route->'legs','[]')) l where l->>'kind'='landing_to_first';
  insert into public.trip_legs(trip_id,day_id,position,kind,to_trip_stop_id,transport_mode,duration_seconds,source_leg_id,estimate_origin)
  values(target,day_id,position,'landing_to_first',mapped[1],coalesce(leg->>'transport_mode','unknown'),(leg->>'duration_seconds')::numeric::integer,(leg->>'id')::uuid,case when leg is null then 'unknown' else 'creator' end); position:=position+1;
 end if;
 if n>1 then for edge_index in 1..n-1 loop
  leg:=null; select l into leg from jsonb_array_elements(coalesce(route->'legs','[]')) l where l->>'kind'='between_stops' and l->>'from_stop_id'=ids[edge_index]::text and l->>'to_stop_id'=ids[edge_index+1]::text;
  insert into public.trip_legs(trip_id,day_id,position,kind,from_trip_stop_id,to_trip_stop_id,transport_mode,duration_seconds,source_leg_id,estimate_origin)
  values(target,day_id,position,'between_stops',mapped[edge_index],mapped[edge_index+1],coalesce(leg->>'transport_mode','unknown'),(leg->>'duration_seconds')::numeric::integer,(leg->>'id')::uuid,case when leg is null then 'unknown' else 'creator' end); position:=position+1;
 end loop; end if;
 perform set_config('c67.graph_build_trip',coalesce(previous_setting,''),true);
exception when others then
 perform set_config('c67.graph_build_trip',coalesce(previous_setting,''),true); raise;
end;
$$;
revoke all on function public.populate_trip_graph(uuid,boolean) from public,anon,authenticated,service_role;
-- Existing trips normalize their own saved JSON; current source geometry is not historical evidence.
do $$ declare t record; begin for t in select id from public.trips loop perform public.populate_trip_graph(t.id,false); end loop; end $$;
create function public.create_trip_graph_rows() returns trigger language plpgsql security definer set search_path='' as $$
begin perform public.populate_trip_graph(new.id,true); return new; end;
$$;
revoke all on function public.create_trip_graph_rows() from public,anon,authenticated,service_role;
create trigger create_trip_graph_rows after insert on public.trips for each row execute function public.create_trip_graph_rows();
create function public.guard_trip_graph_root() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.stops is distinct from old.stops or new.starts_at is distinct from old.starts_at or new.time_zone is distinct from old.time_zone
  or new.creation_origin is distinct from old.creation_origin or new.creation_start_basis is distinct from old.creation_start_basis then
  raise sqlstate 'PT409' using message='Trip graph fields require a graph command';
 end if;
 return new;
end;
$$;
revoke all on function public.guard_trip_graph_root() from public,anon,authenticated,service_role;
create trigger guard_trip_graph_root before update on public.trips for each row execute function public.guard_trip_graph_root();

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
        select * into source from public.rundown_versions where id = p_version_id and published for share;
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


create or replace function public.create_trip_v2(p_version_id uuid, p_starts_at timestamptz, p_time_zone text, p_request_id uuid)
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
        select * into source from public.rundown_versions where id = p_version_id and published for share;
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


create function public.get_trip_graph(p_trip_id uuid) returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare caller uuid:=auth.uid(); result jsonb;
begin
 if caller is null then raise sqlstate 'PT401' using message='Traveller session required'; end if;
 if p_trip_id is null then raise sqlstate 'PT400' using message='Trip ID is required'; end if;
 select jsonb_build_object('schema_version',3,'id',t.id,'title',t.title,'starts_at',t.starts_at,'revision',t.revision,'status',t.status,
 'sources',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'rundown_id',s.rundown_id,'version_id',s.version_id,'version_no',s.version_no,'title',s.title) order by s.id) from public.trip_sources s where s.trip_id=t.id),'[]'::jsonb),
 'days',coalesce((select jsonb_agg(jsonb_build_object('id',d.id,'day_index',d.day_index,'starts_at',d.starts_at,'time_zone',d.time_zone,'local_date',d.local_date,'start_time_basis',d.start_time_basis,'origin',d.origin,'landing',jsonb_build_object('kind',d.landing_kind,'trip_stop_id',d.landing_trip_stop_id,'location',d.landing_location)) order by d.day_index) from public.trip_days d where d.trip_id=t.id),'[]'::jsonb),
 'stops',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'day_id',s.day_id,'source_id',s.source_id,'source_stop_id',s.source_stop_id,'position',s.position,'title',s.title,'location',s.location,'time_zone',s.time_zone,'visit_duration_seconds',s.visit_duration_seconds,'progress_status',s.progress_status) order by s.position) from public.trip_stops s where s.trip_id=t.id),'[]'::jsonb),
 'legs',coalesce((select jsonb_agg(jsonb_build_object('id',l.id,'day_id',l.day_id,'position',l.position,'kind',l.kind,'from_trip_stop_id',l.from_trip_stop_id,'to_trip_stop_id',l.to_trip_stop_id,'transport_mode',l.transport_mode,'duration_seconds',l.duration_seconds,'source_leg_id',l.source_leg_id,'estimate_origin',l.estimate_origin) order by l.position) from public.trip_legs l where l.trip_id=t.id),'[]'::jsonb),
 'warnings',to_jsonb(array_remove(array[
  case when exists(select 1 from public.trip_days d where d.trip_id=t.id and d.landing_kind='unknown') then 'landing_unknown' end,
  case when exists(select 1 from public.trip_days d where d.trip_id=t.id and d.start_time_basis='unspecified') then 'start_basis_unspecified' end,
  case when exists(select 1 from public.trip_stops s where s.trip_id=t.id and s.location is null) then 'stop_location_unknown' end,
  case when exists(select 1 from public.trip_stops s where s.trip_id=t.id and s.visit_duration_seconds is null) then 'visit_duration_unknown' end,
  case when exists(select 1 from public.trip_legs l where l.trip_id=t.id and l.duration_seconds is null) then 'leg_duration_unknown' end],null)))
 into result from public.trips t where t.id=p_trip_id and t.owner_id=caller;
 if result is null then raise sqlstate 'PT404' using message='Trip not found'; end if;
 return result;
end;
$$;
create function public.create_trip_v3(p_version_id uuid,p_starts_at timestamptz,p_time_zone text,p_start_time_basis text,p_request_id uuid,p_origin jsonb default null)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare caller uuid:=auth.uid(); source public.rundown_versions%rowtype; result public.trips%rowtype;
begin
 if caller is null then raise sqlstate 'PT401' using message='Traveller session required'; end if;
 if p_version_id is null or p_starts_at is null or p_time_zone is null or p_start_time_basis is null or p_request_id is null then raise sqlstate 'PT400' using message='Version, start, zone, basis and request ID are required'; end if;
 if not isfinite(p_starts_at) then raise sqlstate 'PT400' using message='Trip start must be finite'; end if;
 if p_start_time_basis not in ('unspecified','departure_origin','start_at_landing') then raise sqlstate 'PT400' using message='Invalid start time basis'; end if;
 if p_origin is not null and not public.is_graph_point(p_origin) then raise sqlstate 'PT400' using message='Invalid origin point'; end if;
 select * into result from public.trips where owner_id=caller and request_id=p_request_id;
 if not found then
  select * into source from public.rundown_versions where id=p_version_id and published for share;
  if not found then raise sqlstate 'PT404' using message='Published version not found'; end if;
  insert into public.trips(owner_id,source_version_id,title,starts_at,stops,request_id,time_zone,creation_api_version,creation_origin,creation_start_basis)
  values(caller,source.id,source.title,p_starts_at,source.stops,p_request_id,p_time_zone,3,p_origin,p_start_time_basis)
  on conflict(owner_id,request_id) do nothing returning * into result;
  if not found then select * into result from public.trips where owner_id=caller and request_id=p_request_id; end if;
 end if;
 if result.creation_api_version<>3 or result.source_version_id<>p_version_id or result.starts_at<>p_starts_at
  or result.time_zone is distinct from p_time_zone or result.creation_origin is distinct from p_origin or result.creation_start_basis<>p_start_time_basis then
  raise sqlstate 'PT409' using message='Request ID reused with different input';
 end if;
 return public.get_trip_graph(result.id);
end;
$$;
revoke all on function public.get_trip_graph(uuid),public.create_trip_v3(uuid,timestamptz,text,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.get_trip_graph(uuid),public.create_trip_v3(uuid,timestamptz,text,text,uuid,jsonb) to authenticated;

create function public.get_rundown_route(p_version_id uuid) returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare result jsonb;
begin
 select jsonb_build_object('version_id',id,'rundown_id',rundown_id,'version_no',version_no,'stops',stops,'route_template',route_template)
 into result from public.rundown_versions where id=p_version_id and published;
 if result is null then raise sqlstate 'PT404' using message='Published version not found'; end if;
 return result;
end;
$$;
revoke all on function public.get_rundown_route(uuid) from public,anon,authenticated;
grant execute on function public.get_rundown_route(uuid) to anon,authenticated;
