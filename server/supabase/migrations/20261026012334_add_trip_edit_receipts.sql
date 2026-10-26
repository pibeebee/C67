create schema if not exists c67_private;
revoke all on schema c67_private from public,anon,authenticated,service_role;
create table c67_private.command_receipts(
 owner_id uuid not null references auth.users(id) on delete cascade, request_id uuid not null,
 command text not null, input jsonb not null, response jsonb not null, created_at timestamptz not null default now(), primary key(owner_id,request_id)
);
revoke all on c67_private.command_receipts from public,anon,authenticated,service_role;
-- Materialize creation receipts before edit commands become available.
do $$ declare t public.trips%rowtype; response jsonb; input jsonb; begin
 for t in select * from public.trips loop
  perform set_config('request.jwt.claim.sub',t.owner_id::text,true);
  input:=jsonb_build_object('version',t.source_version_id,'start',t.starts_at);
  if t.creation_api_version>=2 then input:=input||jsonb_build_object('zone',t.time_zone); end if;
  if t.creation_api_version=3 then input:=input||jsonb_build_object('basis',t.creation_start_basis,'origin',t.creation_origin); end if;
  response:=case t.creation_api_version when 1 then public.get_trip_snapshot(t.id) when 2 then public.get_trip_snapshot_v2(t.id) else public.get_trip_graph(t.id) end;
  insert into c67_private.command_receipts values(t.owner_id,t.request_id,'create_v'||t.creation_api_version,input,response,now());
 end loop;
 perform set_config('request.jwt.claim.sub','',true);
end $$;
alter function public.create_trip(uuid,timestamptz,uuid) rename to internal_create_trip;
revoke all on function public.internal_create_trip(uuid,timestamptz,uuid) from public,anon,authenticated,service_role;
create function public.create_trip(p_version_id uuid,p_starts_at timestamptz,p_request_id uuid) returns jsonb
language plpgsql volatile security definer set search_path='' as $$
declare actor uuid:=auth.uid(); input jsonb:=jsonb_build_object('version',p_version_id,'start',p_starts_at); r c67_private.command_receipts%rowtype; response jsonb;
begin
 if actor is null then raise sqlstate 'PT401' using message='Traveller session required'; end if;
 if p_request_id is null then raise sqlstate 'PT400' using message='Request ID is required'; end if;
 perform pg_advisory_xact_lock(hashtextextended(actor::text||p_request_id::text,0));
 select * into r from c67_private.command_receipts where owner_id=actor and request_id=p_request_id;
 if found then
  if r.command<>'create_v1' or r.input is distinct from input then raise sqlstate 'PT409' using message='Request ID reused with different input'; end if;
  return r.response;
 end if;
 response:=public.internal_create_trip(p_version_id,p_starts_at,p_request_id);
 insert into c67_private.command_receipts(owner_id,request_id,command,input,response) values(actor,p_request_id,'create_v1',input,response);
 return response;
end;
$$;
revoke all on function public.create_trip(uuid,timestamptz,uuid) from public,anon,authenticated;
grant execute on function public.create_trip(uuid,timestamptz,uuid) to authenticated;
alter function public.create_trip_v2(uuid,timestamptz,text,uuid) rename to internal_create_trip_v2;
revoke all on function public.internal_create_trip_v2(uuid,timestamptz,text,uuid) from public,anon,authenticated,service_role;
create function public.create_trip_v2(p_version_id uuid,p_starts_at timestamptz,p_time_zone text,p_request_id uuid) returns jsonb
language plpgsql volatile security definer set search_path='' as $$
declare actor uuid:=auth.uid(); input jsonb:=jsonb_build_object('version',p_version_id,'start',p_starts_at)||jsonb_build_object('zone',p_time_zone); r c67_private.command_receipts%rowtype; response jsonb;
begin
 if actor is null then raise sqlstate 'PT401' using message='Traveller session required'; end if;
 if p_request_id is null then raise sqlstate 'PT400' using message='Request ID is required'; end if;
 perform pg_advisory_xact_lock(hashtextextended(actor::text||p_request_id::text,0));
 select * into r from c67_private.command_receipts where owner_id=actor and request_id=p_request_id;
 if found then
  if r.command<>'create_v2' or r.input is distinct from input then raise sqlstate 'PT409' using message='Request ID reused with different input'; end if;
  return r.response;
 end if;
 response:=public.internal_create_trip_v2(p_version_id,p_starts_at,p_time_zone,p_request_id);
 insert into c67_private.command_receipts(owner_id,request_id,command,input,response) values(actor,p_request_id,'create_v2',input,response);
 return response;
end;
$$;
revoke all on function public.create_trip_v2(uuid,timestamptz,text,uuid) from public,anon,authenticated;
grant execute on function public.create_trip_v2(uuid,timestamptz,text,uuid) to authenticated;
alter function public.create_trip_v3(uuid,timestamptz,text,text,uuid,jsonb) rename to internal_create_trip_v3;
revoke all on function public.internal_create_trip_v3(uuid,timestamptz,text,text,uuid,jsonb) from public,anon,authenticated,service_role;
create function public.create_trip_v3(p_version_id uuid,p_starts_at timestamptz,p_time_zone text,p_start_time_basis text,p_request_id uuid,p_origin jsonb default null) returns jsonb
language plpgsql volatile security definer set search_path='' as $$
declare actor uuid:=auth.uid(); input jsonb:=jsonb_build_object('version',p_version_id,'start',p_starts_at)||jsonb_build_object('zone',p_time_zone)||jsonb_build_object('basis',p_start_time_basis,'origin',p_origin); r c67_private.command_receipts%rowtype; response jsonb;
begin
 if actor is null then raise sqlstate 'PT401' using message='Traveller session required'; end if;
 if p_request_id is null then raise sqlstate 'PT400' using message='Request ID is required'; end if;
 perform pg_advisory_xact_lock(hashtextextended(actor::text||p_request_id::text,0));
 select * into r from c67_private.command_receipts where owner_id=actor and request_id=p_request_id;
 if found then
  if r.command<>'create_v3' or r.input is distinct from input then raise sqlstate 'PT409' using message='Request ID reused with different input'; end if;
  return r.response;
 end if;
 response:=public.internal_create_trip_v3(p_version_id,p_starts_at,p_time_zone,p_start_time_basis,p_request_id,p_origin);
 insert into c67_private.command_receipts(owner_id,request_id,command,input,response) values(actor,p_request_id,'create_v3',input,response);
 return response;
end;
$$;
revoke all on function public.create_trip_v3(uuid,timestamptz,text,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.create_trip_v3(uuid,timestamptz,text,text,uuid,jsonb) to authenticated;

-- Only definer commands set this transaction-local guard; clients have no table write grants.
create or replace function public.guard_trip_graph_write() returns trigger language plpgsql security definer set search_path='' as $$
declare target uuid;
begin
 target:=case when TG_OP='DELETE' then old.trip_id else new.trip_id end;
 if TG_OP='DELETE' and not exists(select 1 from public.trips where id=target) then return old; end if;
 if current_setting('c67.graph_edit_trip',true)=target::text then return case when TG_OP='DELETE' then old else new end; end if;
 if TG_OP='INSERT' and current_setting('c67.graph_build_trip',true)=target::text then return new; end if;
 raise insufficient_privilege using message='Trip graph is immutable; use a graph command';
end;
$$;
create or replace function public.guard_trip_graph_root() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if current_setting('c67.graph_edit_trip',true)=old.id::text then return new; end if;
 if new.stops is distinct from old.stops or new.starts_at is distinct from old.starts_at or new.time_zone is distinct from old.time_zone
 or new.creation_origin is distinct from old.creation_origin or new.creation_start_basis is distinct from old.creation_start_basis then
  raise sqlstate 'PT409' using message='Trip graph fields require a graph command'; end if;
 return new;
end;
$$;
create table c67_private.plan_previews(
 id uuid primary key default gen_random_uuid(),owner_id uuid not null references auth.users(id) on delete cascade,
 trip_id uuid not null references public.trips(id) on delete cascade, expected_revision bigint not null,
 patch jsonb not null, source_snapshot jsonb, expires_at timestamptz not null default now()+interval '15 minutes'
);
revoke all on c67_private.plan_previews from public,anon,authenticated,service_role;
create function public.preview_trip_change(p_trip_id uuid,p_expected_revision bigint,p_patch jsonb) returns jsonb
language plpgsql volatile security definer set search_path='' as $$
declare actor uuid:=auth.uid(); t public.trips%rowtype; token uuid; source jsonb; ids uuid[]; supplied uuid[]; version uuid;
begin
 if actor is null then raise sqlstate 'PT401' using message='Traveller session required'; end if;
 select * into t from public.trips where id=p_trip_id and owner_id=actor;
 if not found then raise sqlstate 'PT404' using message='Trip not found'; end if;
 if p_expected_revision is null or t.revision<>p_expected_revision then raise sqlstate 'PT409' using message='Trip revision changed'; end if;
 if t.status<>'planned' then raise sqlstate 'PT409' using message='Only planned trips may be edited'; end if;
 if jsonb_typeof(p_patch) is distinct from 'object' or p_patch='{}'::jsonb or exists(select 1 from jsonb_object_keys(p_patch) k where k not in ('title','starts_at','time_zone','stop_order','append_version_id')) then raise sqlstate 'PT400' using message='Invalid trip patch'; end if;
 if p_patch ? 'title' and (jsonb_typeof(p_patch->'title') is distinct from 'string' or length(btrim(p_patch->>'title')) not between 1 and 200) then raise sqlstate 'PT400' using message='Invalid trip title'; end if;
 if p_patch ? 'starts_at' and (jsonb_typeof(p_patch->'starts_at') is distinct from 'string' or not isfinite((p_patch->>'starts_at')::timestamptz)) then raise sqlstate 'PT400' using message='Invalid trip start';end if;
 if p_patch ? 'time_zone' and not exists(select 1 from pg_catalog.pg_timezone_names z where z.name=p_patch->>'time_zone' and (z.name='UTC' or position('/' in z.name)>0) and z.name not like 'posix/%' and z.name not like 'right/%') then raise sqlstate 'PT400' using message='Invalid trip time zone';end if;
 if p_patch ? 'stop_order' then
  if jsonb_typeof(p_patch->'stop_order') is distinct from 'array' then raise sqlstate 'PT400' using message='Invalid stop order'; end if;
  select array_agg(id order by id) into ids from public.trip_stops where trip_id=t.id;
  select array_agg(value::uuid order by value::uuid) into supplied from jsonb_array_elements_text(p_patch->'stop_order');
  if supplied is null or cardinality(supplied)<>(select count(distinct x) from unnest(supplied) x) or not supplied<@ids then raise sqlstate 'PT400' using message='Order must contain distinct existing trip occurrences'; end if;
 end if;
 if p_patch ? 'append_version_id' then
  version:=(p_patch->>'append_version_id')::uuid;
  select jsonb_build_object('rundown_id',rundown_id,'version_id',id,'version_no',version_no,'title',title,'stops',stops,'route_template',route_template) into source from public.rundown_versions where id=version and published;
  if source is null then raise sqlstate 'PT404' using message='Published version not found'; end if;
 end if;
 -- Location/visit guards are added alongside the journal migration; token pins exact choices/source bytes.
 insert into c67_private.plan_previews(owner_id,trip_id,expected_revision,patch,source_snapshot) values(actor,t.id,t.revision,p_patch,source) returning id into token;
 return jsonb_build_object('preview_id',token,'trip_id',t.id,'expected_revision',t.revision,'patch',p_patch,'append_source',source,'expires_in_seconds',900,'warnings',case when p_patch ? 'stop_order' or p_patch ? 'append_version_id' then '["route_estimates_invalidated","keep_all_occurrences"]'::jsonb else '[]'::jsonb end);
exception when data_exception then raise sqlstate 'PT400' using message='Malformed trip patch';
end;
$$;
create function public.apply_trip_change(p_preview_id uuid,p_request_id uuid) returns jsonb
language plpgsql volatile security definer set search_path='' as $$
declare actor uuid:=auth.uid(); p c67_private.plan_previews%rowtype; t public.trips%rowtype;
 r c67_private.command_receipts%rowtype; input jsonb:=jsonb_build_object('preview_id',p_preview_id); response jsonb;
 d public.trip_days%rowtype; sid uuid; s jsonb; route jsonb; new_id uuid; pos integer; idx integer; ids uuid[]; detail jsonb;
begin
 if actor is null then raise sqlstate 'PT401' using message='Traveller session required'; end if;
 if p_request_id is null or p_preview_id is null then raise sqlstate 'PT400' using message='Preview and request ID are required'; end if;
 perform pg_advisory_xact_lock(hashtextextended(actor::text||p_request_id::text,0));
 select * into r from c67_private.command_receipts where owner_id=actor and request_id=p_request_id;
 if found then
  if r.command<>'apply_plan' or r.input is distinct from input then raise sqlstate 'PT409' using message='Request ID reused with different input'; end if;
  return r.response;
 end if;
 select * into p from c67_private.plan_previews where id=p_preview_id and owner_id=actor;
 if not found then raise sqlstate 'PT404' using message='Preview not found'; end if;
 if p.expires_at<now() then raise sqlstate 'PT409' using message='Preview expired'; end if;
 select * into t from public.trips where id=p.trip_id and owner_id=actor for update;
 if not found then raise sqlstate 'PT404' using message='Trip not found'; end if;
 if t.revision<>p.expected_revision then raise sqlstate 'PT409' using message='Trip revision changed'; end if;
 if t.status<>'planned' then raise sqlstate 'PT409' using message='Only planned trips may be edited'; end if;
 if p.source_snapshot is not null then perform 1 from public.rundown_versions where id=(p.source_snapshot->>'version_id')::uuid for share; end if;
 if p.source_snapshot is not null and not exists(select 1 from public.rundown_versions v where v.id=(p.source_snapshot->>'version_id')::uuid and v.published and jsonb_build_object('rundown_id',v.rundown_id,'version_id',v.id,'version_no',v.version_no,'title',v.title,'stops',v.stops,'route_template',v.route_template)=p.source_snapshot) then raise sqlstate 'PT409' using message='Source changed; preview again'; end if;
 perform set_config('c67.graph_edit_trip',t.id::text,true);
 select * into d from public.trip_days where trip_id=t.id;
 if p.patch ? 'stop_order' then
  -- Every removed occurrence is explicitly absent from the reviewed retained-ID list.
  -- FKs and the journal guard reject protected plans before any delete.
  if exists(select 1 from public.journal_entries where trip_id=t.id) or exists(select 1 from public.journal_uploads where trip_id=t.id and state in ('uploading','queued','processing') and (state<>'uploading' or expires_at>now())) then raise sqlstate 'PT409' using message='Journaled or pending-upload plan is protected';end if;
  delete from public.trip_legs where trip_id=t.id;
  select array_agg(value::uuid) into ids from jsonb_array_elements_text(p.patch->'stop_order');
  if d.landing_kind='first_stop' then update public.trip_days set landing_trip_stop_id=ids[1],landing_location=(select location from public.trip_stops where id=ids[1]) where id=d.id;end if;
  delete from public.trip_stops where trip_id=t.id and not id=any(ids);
  -- Park positions to preserve the immediate unique index while moving rows.
  update public.trip_stops set position=position+1000000 where trip_id=t.id;
  idx:=0;
  for s in select value from jsonb_array_elements(p.patch->'stop_order') loop
   update public.trip_stops set position=idx where trip_id=t.id and id=(s#>>'{}')::uuid;idx:=idx+1;
  end loop;
  if d.landing_kind='first_stop' then
   select id into new_id from public.trip_stops where trip_id=t.id order by position limit 1;
   update public.trip_days set landing_trip_stop_id=new_id,landing_location=(select location from public.trip_stops where id=new_id) where id=d.id;
  end if;
 end if;
 if p.source_snapshot is not null then
  insert into public.trip_sources(trip_id,rundown_id,version_id,version_no,title)
  values(t.id,(p.source_snapshot->>'rundown_id')::uuid,(p.source_snapshot->>'version_id')::uuid,(p.source_snapshot->>'version_no')::integer,p.source_snapshot->>'title') returning id into sid;
  select coalesce(max(position)+1,0) into pos from public.trip_stops where trip_id=t.id;
  route:=p.source_snapshot->'route_template';
  for s in select value from jsonb_array_elements(p.source_snapshot->'stops') loop
   detail:=null;select x into detail from jsonb_array_elements(coalesce(route->'stop_details','[]')) x where x->>'source_stop_id'=s->>'id';
   insert into public.trip_stops(id,trip_id,day_id,source_id,source_stop_id,position,title,location,time_zone,visit_duration_seconds)
   values(gen_random_uuid(),t.id,d.id,sid,(s->>'id')::uuid,pos,s->>'title',nullif(detail->'location','null'::jsonb),detail->>'time_zone',(detail->>'visit_duration_seconds')::numeric::integer);pos:=pos+1;
  end loop;
 end if;
 if p.patch ? 'stop_order' or p.source_snapshot is not null then
  -- Recompute topology, invalidate every estimate; never reuse old ETA for new adjacency.
  delete from public.trip_legs where trip_id=t.id;
  pos:=0;
  if d.origin is not null then insert into public.trip_legs(trip_id,day_id,position,kind,estimate_origin) values(t.id,d.id,pos,'access','unknown');pos:=pos+1;end if;
  select array_agg(id order by position) into ids from public.trip_stops where trip_id=t.id;
  if d.landing_kind='separate' and cardinality(ids)>0 then insert into public.trip_legs(trip_id,day_id,position,kind,to_trip_stop_id,estimate_origin) values(t.id,d.id,pos,'landing_to_first',ids[1],'unknown');pos:=pos+1;end if;
  if cardinality(ids)>1 then for edge_index in 1..cardinality(ids)-1 loop
   insert into public.trip_legs(trip_id,day_id,position,kind,from_trip_stop_id,to_trip_stop_id,estimate_origin) values(t.id,d.id,pos,'between_stops',ids[edge_index],ids[edge_index+1],'unknown');pos:=pos+1;
  end loop;end if;
 end if;
 update public.trips set title=coalesce(p.patch->>'title',title),starts_at=coalesce((p.patch->>'starts_at')::timestamptz,starts_at),time_zone=coalesce(p.patch->>'time_zone',time_zone),stops=case when p.patch ? 'stop_order' or p.source_snapshot is not null then (select coalesce(jsonb_agg(jsonb_build_object('id',id,'title',title,'order',position) order by position),'[]'::jsonb) from public.trip_stops where trip_id=t.id) else stops end where id=t.id;
 update public.trip_days d set starts_at=t2.starts_at,time_zone=t2.time_zone,local_date=t2.local_start_date from public.trips t2 where t2.id=t.id and d.trip_id=t2.id;
 perform set_config('c67.graph_edit_trip','',true);
 response:=public.get_trip_graph(t.id);
 insert into c67_private.command_receipts(owner_id,request_id,command,input,response) values(actor,p_request_id,'apply_plan',input,response);
 return response;
end;
$$;
revoke all on function public.preview_trip_change(uuid,bigint,jsonb),public.apply_trip_change(uuid,uuid) from public,anon,authenticated;
grant execute on function public.preview_trip_change(uuid,bigint,jsonb),public.apply_trip_change(uuid,uuid) to authenticated;
