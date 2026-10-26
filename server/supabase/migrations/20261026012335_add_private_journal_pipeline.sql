-- Private journal policy v1: reported device location at session creation only.
create table public.journal_uploads(
 id uuid primary key default gen_random_uuid(), owner_id uuid references auth.users(id) on delete set null,
 trip_id uuid references public.trips(id) on delete set null, stop_id uuid references public.trip_stops(id) on delete set null,
 request_id uuid not null, input jsonb not null, input_hash text not null, declared_type text not null check(declared_type in ('image/jpeg','image/png')),
 state text not null default 'uploading' check(state in ('uploading','queued','processing','ready','rejected')),
 raw_path text unique not null, ready_path text unique not null,
 expires_at timestamptz not null default now()+interval '15 minutes', created_at timestamptz not null default now(),
 lease_id uuid, lease_until timestamptz, attempts integer not null default 0,
 failure_code text, width integer, height integer, sha256 text, unique(owner_id,request_id)
);
create index journal_uploads_queue_idx on public.journal_uploads(state,lease_until,created_at);
create index journal_uploads_owner_idx on public.journal_uploads(owner_id,created_at);
create table public.journal_entries(
 id uuid primary key default gen_random_uuid(), owner_id uuid not null references auth.users(id) on delete cascade,
 trip_id uuid not null references public.trips(id) on delete cascade,
 stop_id uuid not null references public.trip_stops(id), upload_id uuid not null unique references public.journal_uploads(id),
 accepted_at timestamptz not null default now(), verification_origin text not null default 'device_reported_session_v1',
 object_path text not null unique, width integer not null, height integer not null, sha256 text not null
);
create index journal_entries_trip_idx on public.journal_entries(trip_id,accepted_at,id);
create index journal_entries_owner_idx on public.journal_entries(owner_id);
alter table public.journal_uploads enable row level security;
alter table public.journal_entries enable row level security;
revoke all on public.journal_uploads,public.journal_entries from public,anon,authenticated;
grant select on public.journal_entries to authenticated;
create policy own_journal on public.journal_entries for select to authenticated using(owner_id=(select auth.uid()));
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values
 ('c67-journal-raw','c67-journal-raw',false,5242880,array['image/jpeg','image/png']),
 ('c67-journal-ready','c67-journal-ready',false,5242880,array['image/jpeg'])
 on conflict(id) do nothing;
do $$ begin
 if exists(select 1 from storage.buckets where id in ('c67-journal-raw','c67-journal-ready') and (public or file_size_limit is distinct from 5242880)) then raise check_violation using message='Unexpected journal bucket configuration';end if;
end $$;
create function public.can_upload_journal(p_name text) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.journal_uploads where raw_path=p_name and owner_id=auth.uid() and state='uploading' and expires_at>now());
$$;
revoke all on function public.can_upload_journal(text) from public,anon,authenticated;
grant execute on function public.can_upload_journal(text) to authenticated;
create policy c67_raw_insert on storage.objects for insert to authenticated with check(bucket_id='c67-journal-raw' and public.can_upload_journal(name));
create policy c67_ready_read on storage.objects for select to authenticated using(bucket_id='c67-journal-ready' and exists(select 1 from public.journal_entries j where j.object_path=name and j.owner_id=(select auth.uid())));
create function public.begin_journal_upload(p_trip_id uuid,p_stop_id uuid,p_request_id uuid,p_content_type text,p_location jsonb) returns jsonb
language plpgsql volatile security definer set search_path='' as $$
declare actor uuid:=auth.uid(); t public.trips%rowtype; s public.trip_stops%rowtype; u public.journal_uploads%rowtype;
 input jsonb; sample timestamptz; accuracy numeric; distance_m double precision; lat1 double precision;lat2 double precision;dlon double precision;
begin
 if actor is null then raise sqlstate 'PT401' using message='Traveller session required'; end if;
 if p_request_id is null or p_stop_id is null or p_trip_id is null then raise sqlstate 'PT400' using message='Trip, stop and request ID are required'; end if;
 input:=jsonb_build_object('trip',p_trip_id,'stop',p_stop_id,'content_type',p_content_type,'location',p_location);
 perform pg_advisory_xact_lock(hashtextextended(actor::text||p_request_id::text,1));
 select * into u from public.journal_uploads where owner_id=actor and request_id=p_request_id;
 if found then
  if u.input_hash is distinct from md5(input::text) then raise sqlstate 'PT409' using message='Upload request reused with different input'; end if;
  return jsonb_build_object('upload_id',u.id,'bucket','c67-journal-raw','path',u.raw_path,'expires_at',u.expires_at,'state',u.state);
 end if;
 select * into t from public.trips where id=p_trip_id and owner_id=actor for update;
 if not found then raise sqlstate 'PT404' using message='Trip not found'; end if;
 select * into s from public.trip_stops where id=p_stop_id and trip_id=t.id;
 if not found then raise sqlstate 'PT404' using message='Trip stop not found'; end if;
 if s.location is null then raise sqlstate 'PT409' using message='Stop location is unresolved'; end if;
 if p_content_type is null or p_content_type not in ('image/jpeg','image/png') then raise sqlstate 'PT400' using message='Only JPEG or PNG is supported'; end if;
 if jsonb_typeof(p_location) is distinct from 'object' or not public.is_graph_point(p_location-'accuracy_m'-'sampled_at') then raise sqlstate 'PT400' using message='Invalid reported location';end if;
 if jsonb_typeof(p_location->'accuracy_m') is distinct from 'number' then raise sqlstate 'PT400' using message='Invalid location accuracy';end if;
 accuracy:=(p_location->>'accuracy_m')::numeric;sample:=(p_location->>'sampled_at')::timestamptz;
 if accuracy<0 or accuracy>100 or sample is null or not isfinite(sample) or sample<clock_timestamp()-interval '30 seconds' or sample>clock_timestamp()+interval '10 seconds' then raise sqlstate 'PT400' using message='Location sample must be recent and accurate';end if;
 lat1:=radians((p_location->>'latitude')::double precision);lat2:=radians((s.location->>'latitude')::double precision);dlon:=radians((p_location->>'longitude')::double precision-(s.location->>'longitude')::double precision);
 distance_m:=6371000*2*asin(sqrt(least(1.0,power(sin((lat2-lat1)/2),2)+cos(lat1)*cos(lat2)*power(sin(dlon/2),2))));
 if distance_m+accuracy>100 then raise sqlstate 'PT403' using message='Reported location is outside the allowed radius'; end if;
 if (select count(*) from public.journal_uploads where owner_id=actor and created_at>now()-interval '1 hour')>=20 then raise sqlstate 'PT429' using message='Upload session rate limit reached';end if;
 u.id:=gen_random_uuid();
 insert into public.journal_uploads(id,owner_id,trip_id,stop_id,request_id,input,input_hash,declared_type,raw_path,ready_path)
 values(u.id,actor,t.id,s.id,p_request_id,input-'location',md5(input::text),p_content_type,actor::text||'/'||u.id::text||'/original',actor::text||'/'||u.id::text||'/photo.jpg') returning * into u;
 return jsonb_build_object('upload_id',u.id,'bucket','c67-journal-raw','path',u.raw_path,'expires_at',u.expires_at,'state',u.state);
exception when data_exception then raise sqlstate 'PT400' using message='Malformed upload input';
end;
$$;
create function public.submit_journal_upload(p_upload_id uuid) returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare u public.journal_uploads%rowtype; actor uuid:=auth.uid();
begin
 if actor is null then raise sqlstate 'PT401' using message='Traveller session required';end if;
 select * into u from public.journal_uploads where id=p_upload_id and owner_id=actor for update;
 if not found then raise sqlstate 'PT404' using message='Upload not found';end if;
 if u.state='uploading' then
  if u.expires_at<now() then raise sqlstate 'PT409' using message='Upload expired';end if;
  if not exists(select 1 from storage.objects where bucket_id='c67-journal-raw' and name=u.raw_path) then raise sqlstate 'PT409' using message='Upload bytes are missing';end if;
  update public.journal_uploads set state='queued' where id=u.id;u.state:='queued';
 end if;
 return jsonb_build_object('upload_id',u.id,'state',u.state,'failure_code',u.failure_code);
end;
$$;
create function public.claim_journal_job() returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare u public.journal_uploads%rowtype;
begin
 if auth.role() is distinct from 'service_role' then raise insufficient_privilege;end if;
 select * into u from public.journal_uploads where owner_id is not null and trip_id is not null and stop_id is not null and attempts<5 and (state='queued' or (state='processing' and lease_until<now())) order by created_at for update skip locked limit 1;
 if not found then return null;end if;
 update public.journal_uploads set state='processing',attempts=attempts+1,lease_id=gen_random_uuid(),lease_until=now()+interval '2 minutes' where id=u.id returning * into u;
 return jsonb_build_object('upload_id',u.id,'lease_id',u.lease_id,'raw_path',u.raw_path,'ready_path',u.ready_path,'content_type',u.declared_type);
end;
$$;
create function public.finish_journal_job(p_upload_id uuid,p_lease_id uuid,p_result jsonb) returns void language plpgsql volatile security definer set search_path='' as $$
declare u public.journal_uploads%rowtype; t public.trips%rowtype;
begin
 if auth.role() is distinct from 'service_role' then raise insufficient_privilege;end if;
 -- Match the edit lock order: trip first, upload second. Never hold SQL locks during IO.
 select * into u from public.journal_uploads where id=p_upload_id;
 select * into t from public.trips where id=u.trip_id for update;
 select * into u from public.journal_uploads where id=p_upload_id for update;
 if u.id is null or u.lease_id is distinct from p_lease_id or u.state<>'processing' or u.lease_until<now() then raise sqlstate 'PT409' using message='Worker lease is stale';end if;
 if u.owner_id is null or t.id is null or u.stop_id is null then update public.journal_uploads set state='rejected',failure_code='owner_or_trip_removed' where id=u.id;return;end if;
 if p_result->>'failure_code' is not null then
  if p_result->>'failure_code' not in ('invalid_image','too_large','unsupported_type','dimensions_exceeded') then raise invalid_parameter_value;end if;
  update public.journal_uploads set state='rejected',failure_code=p_result->>'failure_code' where id=u.id;return;
 end if;
 if (p_result->>'width')::integer not between 1 and 2048 or (p_result->>'height')::integer not between 1 and 2048 or p_result->>'sha256' !~ '^[a-f0-9]{64}$' then raise invalid_parameter_value;end if;
 if not exists(select 1 from storage.objects where bucket_id='c67-journal-ready' and name=u.ready_path) then raise sqlstate 'PT409' using message='Processed bytes are missing';end if;
 insert into public.journal_entries(owner_id,trip_id,stop_id,upload_id,object_path,width,height,sha256)
 values(u.owner_id,u.trip_id,u.stop_id,u.id,u.ready_path,(p_result->>'width')::integer,(p_result->>'height')::integer,p_result->>'sha256') on conflict(upload_id) do nothing;
 update public.journal_uploads set state='ready',width=(p_result->>'width')::integer,height=(p_result->>'height')::integer,sha256=p_result->>'sha256',input=input-'location' where id=u.id;
 -- Accepted journal is part of the aggregate, but does not complete the visit/trip.
 update public.trips set revision=revision where id=t.id;
end;
$$;
create function public.list_trip_album(p_trip_id uuid) returns jsonb language plpgsql stable security invoker set search_path='' as $$
begin
 if auth.uid() is null then raise sqlstate 'PT401' using message='Traveller session required';end if;
 if not exists(select 1 from public.trips where id=p_trip_id and owner_id=auth.uid()) then raise sqlstate 'PT404' using message='Trip not found';end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',id,'stop_id',stop_id,'accepted_at',accepted_at,'bucket','c67-journal-ready','object_path',object_path,'width',width,'height',height,'verification_origin',verification_origin) order by accepted_at,id) from public.journal_entries where trip_id=p_trip_id and owner_id=auth.uid()),'[]'::jsonb);
end;
$$;
-- Expired/unowned/exhausted sessions are purged only AFTER Storage API deletes both paths.
create function public.journal_cleanup_candidates() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if auth.role() is distinct from 'service_role' then raise insufficient_privilege;end if;
 return coalesce((select jsonb_agg(jsonb_build_object('upload_id',id,'raw_path',raw_path,'ready_path',ready_path)) from (select * from public.journal_uploads where owner_id is null or trip_id is null or stop_id is null or (state='rejected' and created_at<now()-interval '24 hours') or (state='uploading' and expires_at<now()-interval '24 hours') or (state='processing' and attempts>=5 and lease_until<now()) order by created_at limit 100) x),'[]'::jsonb);
end;
$$;
create function public.purge_journal_job(p_upload_id uuid) returns void language plpgsql volatile security definer set search_path='' as $$
declare u public.journal_uploads%rowtype;
begin
 if auth.role() is distinct from 'service_role' then raise insufficient_privilege;end if;
 select * into u from public.journal_uploads where id=p_upload_id for update;
 if not found then return;end if;
 if exists(select 1 from public.journal_entries where upload_id=u.id) or exists(select 1 from storage.objects where (bucket_id='c67-journal-raw' and name=u.raw_path) or (bucket_id='c67-journal-ready' and name=u.ready_path)) then raise sqlstate 'PT409' using message='Remove candidate bytes before purging';end if;
 if u.owner_id is not null and u.trip_id is not null and u.stop_id is not null and u.state<>'rejected' and not(u.state='uploading' and u.expires_at<now()) and not(u.state='processing' and u.attempts>=5 and u.lease_until<now()) then raise sqlstate 'PT409' using message='Active journal job cannot be purged';end if;
 delete from public.journal_uploads where id=u.id;
end;
$$;
-- Freeze topology after any accepted journal, and while an upload is in progress, under the same trip lock.
create function public.protect_journal_plan() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.stops is distinct from old.stops then
  if exists(select 1 from public.journal_entries where trip_id=old.id) or exists(select 1 from public.journal_uploads where trip_id=old.id and state in ('uploading','queued','processing') and (state<>'uploading' or expires_at>now())) then raise sqlstate 'PT409' using message='Journaled or pending-upload plan is protected';end if;
 end if;
 return new;
end;
$$;
revoke all on function public.protect_journal_plan() from public,anon,authenticated,service_role;
create trigger protect_journal_plan before update on public.trips for each row execute function public.protect_journal_plan();
revoke all on function public.begin_journal_upload(uuid,uuid,uuid,text,jsonb),public.submit_journal_upload(uuid),public.list_trip_album(uuid) from public,anon,authenticated;
grant execute on function public.begin_journal_upload(uuid,uuid,uuid,text,jsonb),public.submit_journal_upload(uuid),public.list_trip_album(uuid) to authenticated;
revoke all on function public.claim_journal_job(),public.finish_journal_job(uuid,uuid,jsonb),public.journal_cleanup_candidates(),public.purge_journal_job(uuid) from public,anon,authenticated,service_role;
grant execute on function public.claim_journal_job(),public.finish_journal_job(uuid,uuid,jsonb),public.journal_cleanup_candidates(),public.purge_journal_job(uuid) to service_role;

create function public.journal_raw_cleanup_candidates() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if auth.role() is distinct from 'service_role' then raise insufficient_privilege;end if;
 return coalesce((select jsonb_agg(jsonb_build_object('raw_path',u.raw_path)) from (select raw_path from public.journal_uploads where state='ready' and exists(select 1 from storage.objects o where o.bucket_id='c67-journal-raw' and o.name=raw_path) order by created_at limit 100) u),'[]'::jsonb);
end;
$$;
revoke all on function public.journal_raw_cleanup_candidates() from public,anon,authenticated,service_role;
grant execute on function public.journal_raw_cleanup_candidates() to service_role;
