-- Additive personal-planning aggregate. Existing rundown/trip/journal contracts are unchanged.
create table public.personal_planning_trips (
 id uuid primary key default gen_random_uuid(), owner_id uuid not null references auth.users(id) on delete cascade,
 title text not null, revision bigint not null default 1 check(revision>0),
 status text not null default 'planned' check(status in ('planned','active','completed')),
 input jsonb not null, plan jsonb not null, completed_stop_ids jsonb not null default '[]',
 current_stop_id uuid, current_arrived_at timestamptz,
 synthetic boolean not null default false, created_at timestamptz not null default now()
);
create index personal_planning_owner_idx on public.personal_planning_trips(owner_id,created_at desc,id);
alter table public.personal_planning_trips enable row level security;
revoke all on public.personal_planning_trips from public,anon,authenticated;
grant select on public.personal_planning_trips to authenticated;
create policy personal_planning_owner_read on public.personal_planning_trips for select to authenticated using(owner_id=(select auth.uid()));

create table c67_private.planning_jobs (
 id uuid primary key default gen_random_uuid(), owner_id uuid not null references auth.users(id) on delete cascade,
 request_id uuid not null, purpose text not null check(purpose in ('plan','suggest','replan')),
 request_payload jsonb not null, input jsonb not null,
 trip_id uuid references public.personal_planning_trips(id) on delete cascade, base_revision bigint,
 status text not null default 'queued' check(status in ('queued','running','succeeded','failed')),
 result jsonb, error_code text, attempts integer not null default 0,
 lease_token uuid, lease_expires_at timestamptz, finished_at timestamptz,
 applied_response jsonb, created_at timestamptz not null default now(), unique(owner_id,request_id)
);
create index planning_jobs_queue_idx on c67_private.planning_jobs(created_at) where status in ('queued','running');
create index planning_jobs_owner_idx on c67_private.planning_jobs(owner_id,created_at);
create table c67_private.planning_receipts (
 owner_id uuid not null references auth.users(id) on delete cascade, request_id uuid not null,
 input jsonb not null, response jsonb not null, primary key(owner_id,request_id)
);
create table c67_private.personal_planning_events (
 id uuid primary key default gen_random_uuid(), owner_id uuid not null references auth.users(id) on delete cascade,
 trip_id uuid not null references public.personal_planning_trips(id) on delete cascade,
 revision bigint not null, kind text not null, payload jsonb not null, recorded_at timestamptz not null default now()
);
create index personal_planning_events_trip_idx on c67_private.personal_planning_events(trip_id,revision);
revoke all on c67_private.planning_jobs,c67_private.planning_receipts,c67_private.personal_planning_events from public,anon,authenticated,service_role;
alter table c67_private.planning_jobs enable row level security;
alter table c67_private.planning_receipts enable row level security;
alter table c67_private.personal_planning_events enable row level security;

create function c67_private.validate_planning_input(v jsonb) returns void language plpgsql stable set search_path='' as $$
declare p jsonb; n integer; start_at timestamptz; finish_at timestamptz;
begin
 if jsonb_typeof(v) is distinct from 'object' or jsonb_typeof(v->'places') is distinct from 'array' then raise sqlstate 'PT400' using message='Invalid planning input';end if;
 if jsonb_typeof(v->'title') is distinct from 'string' or length(btrim(v->>'title')) not between 1 and 120 or jsonb_typeof(v->'preferences') is distinct from 'string' or length(v->>'preferences')>2000 then raise sqlstate 'PT400' using message='Invalid title or preferences';end if;
 if v->>'mode' is null or v->>'mode' not in ('walking','automobile') then raise sqlstate 'PT400' using message='Unsupported travel mode';end if;
 if not exists(select 1 from pg_catalog.pg_timezone_names where name=v->>'time_zone') then raise sqlstate 'PT400' using message='Invalid time zone';end if;
 if (v->>'starts_at') !~ 'T.*(Z|[+-][0-9]{2}:[0-9]{2})$' or (v->>'finish_by') !~ 'T.*(Z|[+-][0-9]{2}:[0-9]{2})$' then raise sqlstate 'PT400' using message='Offset-bearing time required';end if;
 start_at:=(v->>'starts_at')::timestamptz; finish_at:=(v->>'finish_by')::timestamptz;
 if start_at is null or finish_at is null or not isfinite(start_at) or not isfinite(finish_at) or finish_at<=start_at or finish_at>start_at+interval '24 hours' then raise sqlstate 'PT400' using message='Invalid time range';end if;
 if jsonb_typeof(v#>'{origin,latitude}') is distinct from 'number' or jsonb_typeof(v#>'{origin,longitude}') is distinct from 'number' or abs((v#>>'{origin,latitude}')::numeric)>90 or abs((v#>>'{origin,longitude}')::numeric)>180 then raise sqlstate 'PT400' using message='Invalid origin';end if;
 n:=jsonb_array_length(v->'places');
 if n not between 1 and 6 or (select count(distinct (item->>'id')::uuid) from jsonb_array_elements(v->'places') item)<>n then raise sqlstate 'PT400' using message='One to six distinct places required';end if;
 for p in select value from jsonb_array_elements(v->'places') loop
  if p->>'id' is null or jsonb_typeof(p->'name') is distinct from 'string' or length(btrim(p->>'name')) not between 1 and 200 then raise sqlstate 'PT400' using message='Invalid place';end if;
  perform (p->>'id')::uuid;
  if jsonb_typeof(p#>'{location,latitude}') is distinct from 'number' or jsonb_typeof(p#>'{location,longitude}') is distinct from 'number' or abs((p#>>'{location,latitude}')::numeric)>90 or abs((p#>>'{location,longitude}')::numeric)>180 then raise sqlstate 'PT400' using message='Invalid place location';end if;
  if jsonb_typeof(p->'visit_seconds') is distinct from 'number' or (p->>'visit_seconds')::numeric not between 0 and 86400 or (p->>'visit_seconds')::numeric<>trunc((p->>'visit_seconds')::numeric) then raise sqlstate 'PT400' using message='Invalid visit duration';end if;
  if p->>'website' is not null and (jsonb_typeof(p->'website')<>'string' or length(p->>'website')>2048) then raise sqlstate 'PT400' using message='Invalid website';end if;
  if p->>'preferred_after' is not null and ((p->>'preferred_after') !~ 'T.*(Z|[+-][0-9]{2}:[0-9]{2})$' or not isfinite((p->>'preferred_after')::timestamptz)) then raise sqlstate 'PT400' using message='Invalid preferred time';end if;
  if p->>'preferred_before' is not null and ((p->>'preferred_before') !~ 'T.*(Z|[+-][0-9]{2}:[0-9]{2})$' or not isfinite((p->>'preferred_before')::timestamptz)) then raise sqlstate 'PT400' using message='Invalid preferred time';end if;
  if (p->>'preferred_after')::timestamptz>(p->>'preferred_before')::timestamptz then raise sqlstate 'PT400' using message='Invalid preferred window';end if;
 end loop;
 if v->>'first_place_id' is not null and not exists(select 1 from jsonb_array_elements(v->'places') item where (item->>'id')::uuid=(v->>'first_place_id')::uuid) then raise sqlstate 'PT400' using message='Invalid first place';end if;
exception when data_exception then raise sqlstate 'PT400' using message='Malformed planning input';
end;$$;

-- Typed clients may re-encode UUID case, equivalent time offsets and absent optional
-- fields. Compare their meaning without allowing changes to immutable trip input.
create function c67_private.planning_input_identity(v jsonb) returns jsonb language plpgsql stable set search_path='' as $$
declare normalized jsonb:=jsonb_strip_nulls(v); places jsonb:='[]'; item jsonb;
begin
 normalized:=jsonb_set(normalized,'{starts_at}',to_jsonb(extract(epoch from (v->>'starts_at')::timestamptz)));
 normalized:=jsonb_set(normalized,'{finish_by}',to_jsonb(extract(epoch from (v->>'finish_by')::timestamptz)));
 if v->>'first_place_id' is not null then normalized:=jsonb_set(normalized,'{first_place_id}',to_jsonb((v->>'first_place_id')::uuid));end if;
 for item in select value from jsonb_array_elements(normalized->'places') loop
  item:=jsonb_set(item,'{id}',to_jsonb((item->>'id')::uuid));
  if item->>'preferred_after' is not null then item:=jsonb_set(item,'{preferred_after}',to_jsonb(extract(epoch from (item->>'preferred_after')::timestamptz)));end if;
  if item->>'preferred_before' is not null then item:=jsonb_set(item,'{preferred_before}',to_jsonb(extract(epoch from (item->>'preferred_before')::timestamptz)));end if;
  places:=places||jsonb_build_array(item);
 end loop;
 return jsonb_set(normalized,'{places}',places);
end;$$;
revoke all on function c67_private.planning_input_identity(jsonb) from public,anon,authenticated,service_role;

create function c67_private.planning_trip_json(t public.personal_planning_trips) returns jsonb language sql immutable set search_path='' as $$
 select to_jsonb(t)-'owner_id';
$$;
create function c67_private.planning_job_json(j c67_private.planning_jobs) returns jsonb language sql stable set search_path='' as $$
 select jsonb_build_object('id',j.id,'status',j.status,'purpose',j.purpose,'input',j.input,'trip_id',j.trip_id,'base_revision',j.base_revision,'result',j.result,'error_code',j.error_code,'created_at',j.created_at);
$$;
revoke all on function c67_private.validate_planning_input(jsonb),c67_private.planning_trip_json(public.personal_planning_trips),c67_private.planning_job_json(c67_private.planning_jobs) from public,anon,authenticated,service_role;

create function public.request_planning_job(p_request jsonb) returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare actor uuid:=auth.uid(); rid uuid; j c67_private.planning_jobs; t public.personal_planning_trips; v jsonb; remaining jsonb; first_stop jsonb; start_at timestamptz; origin jsonb; arrived boolean;
begin
 if actor is null or auth.role()<>'authenticated' then raise sqlstate 'PT401' using message='Traveller session required';end if;
 if jsonb_typeof(p_request) is distinct from 'object' or pg_column_size(p_request)>65536 then raise sqlstate 'PT400' using message='Invalid request';end if;
 rid:=(p_request->>'request_id')::uuid;
 if rid is null or p_request->>'purpose' is null or p_request->>'purpose' not in ('plan','suggest','replan') then raise sqlstate 'PT400' using message='Invalid request identity';end if;
 -- Serialize the owner's admission check so concurrent request IDs cannot bypass quotas.
 perform pg_advisory_xact_lock(hashtextextended(actor::text,0));
 perform pg_advisory_xact_lock(hashtextextended(actor::text||rid::text,0));
 select * into j from c67_private.planning_jobs where owner_id=actor and request_id=rid;
 if found then
  if j.request_payload<>p_request then raise sqlstate 'PT409' using message='Request ID reused with different input';end if;
  return c67_private.planning_job_json(j);
 end if;
 if exists(select 1 from c67_private.planning_receipts where owner_id=actor and request_id=rid) then raise sqlstate 'PT409' using message='Request ID already used';end if;
 perform c67_private.validate_planning_input(p_request->'input');v:=p_request->'input';
 if (select count(*) from c67_private.planning_jobs where owner_id=actor and created_at>now()-interval '1 hour')>=10 then raise sqlstate 'PT429' using message='Planning rate limit reached';end if;
 if (select count(*) from c67_private.planning_jobs where owner_id=actor and status in ('queued','running') and created_at>now()-interval '10 minutes')>=2 then raise sqlstate 'PT429' using message='Planning already in progress';end if;
 if p_request->>'purpose'='replan' then
  select * into t from public.personal_planning_trips where id=(p_request->>'trip_id')::uuid and owner_id=actor for update;
  if not found then raise sqlstate 'PT404' using message='Trip not found';end if;
  if (p_request->>'base_revision')::bigint is distinct from t.revision or t.status='completed' then raise sqlstate 'PT409' using message='Trip revision changed';end if;
  if c67_private.planning_input_identity(v)<>c67_private.planning_input_identity(t.input) then raise sqlstate 'PT409' using message='Trip inputs changed';end if;
  v:=t.input;
  if t.status='active' then
   select coalesce(jsonb_agg(s order by ord),'[]') into remaining from jsonb_array_elements(t.plan->'stops') with ordinality a(s,ord) where not t.completed_stop_ids ? (s->>'id');
   first_stop:=remaining->0;start_at:=date_trunc('milliseconds',clock_timestamp());
   if first_stop is null or start_at>=(v->>'finish_by')::timestamptz then raise sqlstate 'PT409' using message='No remaining trip time';end if;
   arrived:=t.current_stop_id=(first_stop->>'id')::uuid;
   if coalesce(arrived,false) then origin:=first_stop->'location';
   elsif p_request->>'current_origin' is not null then origin:=p_request->'current_origin';
   else select s->'location' into origin from jsonb_array_elements(t.plan->'stops') with ordinality a(s,ord) where t.completed_stop_ids ? (s->>'id') order by ord desc limit 1;origin:=coalesce(origin,v->'origin');end if;
   select jsonb_agg(p || jsonb_build_object('visit_seconds',case when coalesce(arrived,false) and p->>'id'=first_stop->>'id' then greatest(0,ceil(extract(epoch from (first_stop->>'departure_at')::timestamptz-start_at))) else (p->>'visit_seconds')::numeric end) order by ord) into remaining
   from jsonb_array_elements(remaining) with ordinality a(s,ord) join lateral (select value p from jsonb_array_elements(v->'places') where value->>'id'=s->>'id') q on true;
   v:=v || jsonb_build_object('starts_at',start_at,'origin',origin,'first_place_id',case when coalesce(arrived,false) then first_stop->>'id' else null end,'places',remaining);
   perform c67_private.validate_planning_input(v);
  end if;
 elsif p_request->>'trip_id' is not null or p_request->>'base_revision' is not null or p_request->>'current_origin' is not null then raise sqlstate 'PT400' using message='Unexpected trip reference';
 end if;
 insert into c67_private.planning_jobs(owner_id,request_id,purpose,request_payload,input,trip_id,base_revision)
 values(actor,rid,p_request->>'purpose',p_request,v,t.id,t.revision) returning * into j;
 return c67_private.planning_job_json(j);
exception when data_exception then raise sqlstate 'PT400' using message='Malformed planning request';end;$$;

create function public.get_planning_job(p_job_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare j c67_private.planning_jobs;begin
 if auth.uid() is null or auth.role()<>'authenticated' then raise sqlstate 'PT401' using message='Traveller session required';end if;
 select * into j from c67_private.planning_jobs where id=p_job_id and owner_id=auth.uid();
 if not found then raise sqlstate 'PT404' using message='Job not found';end if;
 return c67_private.planning_job_json(j);
end;$$;
create function public.list_personal_planning_trips() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null or auth.role()<>'authenticated' then raise sqlstate 'PT401' using message='Traveller session required';end if;
 return (select coalesce(jsonb_agg(c67_private.planning_trip_json(t) order by t.created_at desc,t.id),'[]') from (select * from public.personal_planning_trips where owner_id=auth.uid() order by created_at desc,id limit 50) t);
end;$$;

create function public.claim_planning_job() returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare j c67_private.planning_jobs;begin
 if auth.role() is distinct from 'service_role' then raise sqlstate 'PT403' using message='Worker access required';end if;
 update c67_private.planning_jobs set status='failed',error_code='JOB_EXPIRED',finished_at=now() where status in ('queued','running') and (created_at<now()-interval '10 minutes' or (attempts>=3 and lease_expires_at<now()));
 select * into j from c67_private.planning_jobs where status='queued' or (status='running' and lease_expires_at<now() and attempts<3) order by created_at for update skip locked limit 1;
 if not found then return null;end if;
 update c67_private.planning_jobs set status='running',attempts=attempts+1,lease_token=gen_random_uuid(),lease_expires_at=least(now()+interval '120 seconds',created_at+interval '10 minutes') where id=j.id returning * into j;
 return c67_private.planning_job_json(j)||jsonb_build_object('owner_id',j.owner_id,'lease_token',j.lease_token);
end;$$;
create function public.renew_planning_job(p_job_id uuid,p_lease_token uuid) returns jsonb language plpgsql volatile security definer set search_path='' as $$
begin
 if auth.role() is distinct from 'service_role' then raise sqlstate 'PT403' using message='Worker access required';end if;
 update c67_private.planning_jobs set lease_expires_at=least(now()+interval '120 seconds',created_at+interval '10 minutes') where id=p_job_id and status='running' and lease_token=p_lease_token and lease_expires_at>now() and created_at>now()-interval '10 minutes';
 if not found then raise sqlstate 'PT409' using message='Worker lease expired';end if;return '{}'::jsonb;
end;$$;

create function public.finish_planning_job(p_job_id uuid,p_lease_token uuid,p_result jsonb,p_error_code text) returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare j c67_private.planning_jobs; proposal jsonb; s jsonb; p jsonb; at_time timestamptz; arrival timestamptz; departure timestamptz;
begin
 if auth.role() is distinct from 'service_role' then raise sqlstate 'PT403' using message='Worker access required';end if;
 select * into j from c67_private.planning_jobs where id=p_job_id for update;
 if not found or j.status<>'running' or j.lease_token is distinct from p_lease_token or j.lease_expires_at<=now() then raise sqlstate 'PT409' using message='Worker lease expired';end if;
 if p_error_code is not null then
  if p_error_code !~ '^[A-Z_]{1,64}$' then raise sqlstate 'PT400' using message='Invalid error code';end if;
  update c67_private.planning_jobs set status='failed',error_code=p_error_code,finished_at=now(),result=null where id=j.id;return '{}'::jsonb;
 end if;
 if p_result is null or pg_column_size(p_result)>262144 or jsonb_typeof(p_result->'synthetic') is distinct from 'boolean' or jsonb_typeof(p_result->'candidates') is distinct from 'array' or jsonb_typeof(p_result->'warnings') is distinct from 'array' then raise sqlstate 'PT400' using message='Invalid planning result';end if;
 if j.purpose='suggest' then
  if p_result->>'proposal' is not null or jsonb_array_length(p_result->'candidates')>4 then raise sqlstate 'PT400' using message='Invalid suggestions';end if;
  for p in select value from jsonb_array_elements(p_result->'candidates') loop perform c67_private.validate_planning_input(j.input||jsonb_build_object('places',jsonb_build_array(p),'first_place_id',null));end loop;
 else
  proposal:=p_result->'proposal';
  if jsonb_typeof(proposal) is distinct from 'object' or proposal->'input' is distinct from j.input or jsonb_typeof(proposal->'stops') is distinct from 'array' or jsonb_array_length(proposal->'stops')<>jsonb_array_length(j.input->'places') or jsonb_typeof(proposal->'feasible') is distinct from 'boolean' then raise sqlstate 'PT400' using message='Invalid proposal';end if;
  if proposal->>'id' is null or jsonb_typeof(proposal->'explanation') is distinct from 'string' or length(proposal->>'explanation')>3000 or jsonb_typeof(proposal->'warnings') is distinct from 'array' or jsonb_typeof(proposal->'evidence') is distinct from 'array' or jsonb_array_length(proposal->'evidence')>100 or proposal->'synthetic' is distinct from p_result->'synthetic' or jsonb_array_length(p_result->'candidates')<>0 then raise sqlstate 'PT400' using message='Invalid proposal metadata';end if;
  perform (proposal->>'id')::uuid;
  if (select count(distinct (value->>'id')::uuid) from jsonb_array_elements(proposal->'stops'))<>jsonb_array_length(j.input->'places') then raise sqlstate 'PT400' using message='Duplicate stop';end if;
  at_time:=(j.input->>'starts_at')::timestamptz;
  for s in select value from jsonb_array_elements(proposal->'stops') loop
   select value into p from jsonb_array_elements(j.input->'places') where (value->>'id')::uuid=(s->>'id')::uuid;
   if p is null or s->>'name' is distinct from p->>'name' or s->'location' is distinct from p->'location' or s->'visit_seconds' is distinct from p->'visit_seconds' or jsonb_typeof(s->'warnings') is distinct from 'array' or jsonb_typeof(s->'travel_seconds') is distinct from 'number' or (s->>'travel_seconds')::numeric<0 or (s->>'travel_seconds')::numeric<>trunc((s->>'travel_seconds')::numeric) then raise sqlstate 'PT400' using message='Invalid scheduled stop';end if;
   arrival:=(s->>'arrival_at')::timestamptz;departure:=(s->>'departure_at')::timestamptz;
   if arrival is null or departure is null or arrival<>at_time+make_interval(secs=>(s->>'travel_seconds')::double precision) or departure<>arrival+make_interval(secs=>(p->>'visit_seconds')::double precision) then raise sqlstate 'PT400' using message='Invalid schedule arithmetic';end if;
   at_time:=departure;
  end loop;
  if (proposal->>'finishes_at')::timestamptz is distinct from at_time or (proposal->>'feasible')::boolean is distinct from (at_time<=(j.input->>'finish_by')::timestamptz) then raise sqlstate 'PT400' using message='Invalid finish time';end if;
  if j.input->>'first_place_id' is not null and (proposal#>>'{stops,0,id}')::uuid<>(j.input->>'first_place_id')::uuid then raise sqlstate 'PT400' using message='Current stop must remain first';end if;
 end if;
 update c67_private.planning_jobs set status='succeeded',result=p_result,error_code=null,finished_at=now() where id=j.id;return '{}'::jsonb;
exception when data_exception then raise sqlstate 'PT400' using message='Malformed worker result';end;$$;

create function public.apply_planning_proposal(p_job_id uuid,p_request_id uuid,p_expected_revision bigint default null) returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare actor uuid:=auth.uid(); j c67_private.planning_jobs; t public.personal_planning_trips; r c67_private.planning_receipts; cmd jsonb:=jsonb_build_object('operation','apply','job_id',p_job_id,'revision',p_expected_revision); v jsonb; visited jsonb; response jsonb;
begin
 if actor is null or auth.role()<>'authenticated' then raise sqlstate 'PT401' using message='Traveller session required';end if;
 if p_request_id is null then raise sqlstate 'PT400' using message='Request ID required';end if;
 perform pg_advisory_xact_lock(hashtextextended(actor::text||p_request_id::text,0));
 select * into r from c67_private.planning_receipts where owner_id=actor and request_id=p_request_id;
 if found then if r.input<>cmd then raise sqlstate 'PT409' using message='Request ID reused';end if;return r.response;end if;
 if exists(select 1 from c67_private.planning_jobs where owner_id=actor and request_id=p_request_id) then raise sqlstate 'PT409' using message='Request ID already used';end if;
 select * into j from c67_private.planning_jobs where id=p_job_id and owner_id=actor for update;
 if not found then raise sqlstate 'PT404' using message='Proposal not found';end if;
 if p_expected_revision is distinct from j.base_revision then raise sqlstate 'PT409' using message='Proposal revision changed';end if;
 if j.applied_response is not null then response:=j.applied_response;
 else
  if j.status<>'succeeded' or j.purpose='suggest' or j.result#>>'{proposal,feasible}' is distinct from 'true' or j.finished_at<now()-interval '15 minutes' then raise sqlstate 'PT409' using message='Proposal is not applicable';end if;
  v:=j.result->'proposal';
  if j.trip_id is null then
   insert into public.personal_planning_trips(owner_id,title,input,plan,synthetic) values(actor,j.input->>'title',j.input,v,(j.result->>'synthetic')::boolean) returning * into t;
  else
   select * into t from public.personal_planning_trips where id=j.trip_id and owner_id=actor for update;
   if not found or t.revision<>j.base_revision or t.status='completed' then raise sqlstate 'PT409' using message='Trip revision changed';end if;
   select coalesce(jsonb_agg(s order by ord),'[]') into visited from jsonb_array_elements(t.plan->'stops') with ordinality a(s,ord) where t.completed_stop_ids ? (s->>'id');
   v:=jsonb_set(v,'{stops}',visited||(v->'stops'));
   update public.personal_planning_trips set plan=v,revision=revision+1 where id=t.id returning * into t;
  end if;
  response:=c67_private.planning_trip_json(t);
  update c67_private.planning_jobs set applied_response=response where id=j.id;
  insert into c67_private.personal_planning_events(owner_id,trip_id,revision,kind,payload) values(actor,t.id,t.revision,'apply',jsonb_build_object('job_id',j.id,'plan',t.plan));
 end if;
 insert into c67_private.planning_receipts values(actor,p_request_id,cmd,response);return response;
end;$$;

create function public.record_planning_event(p_trip_id uuid,p_event jsonb) returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare actor uuid:=auth.uid(); rid uuid; t public.personal_planning_trips; r c67_private.planning_receipts; cmd jsonb:=jsonb_build_object('operation','event','trip_id',p_trip_id,'event',p_event); next_stop jsonb; idx integer; extra integer; updated jsonb; response jsonb;
begin
 if actor is null or auth.role()<>'authenticated' then raise sqlstate 'PT401' using message='Traveller session required';end if;
 if jsonb_typeof(p_event) is distinct from 'object' or pg_column_size(p_event)>65536 then raise sqlstate 'PT400' using message='Invalid trip event';end if;
 rid:=(p_event->>'request_id')::uuid;
 if rid is null then raise sqlstate 'PT400' using message='Request ID required';end if;
 perform pg_advisory_xact_lock(hashtextextended(actor::text||rid::text,0));
 select * into r from c67_private.planning_receipts where owner_id=actor and request_id=rid;
 if found then if r.input<>cmd then raise sqlstate 'PT409' using message='Request ID reused';end if;return r.response;end if;
 if exists(select 1 from c67_private.planning_jobs where owner_id=actor and request_id=rid) then raise sqlstate 'PT409' using message='Request ID already used';end if;
 select * into t from public.personal_planning_trips where id=p_trip_id and owner_id=actor for update;
 if not found then raise sqlstate 'PT404' using message='Trip not found';end if;
 if (p_event->>'expected_revision')::bigint is distinct from t.revision or t.status='completed' then raise sqlstate 'PT409' using message='Trip revision changed';end if;
 select s,(ord-1)::integer into next_stop,idx from jsonb_array_elements(t.plan->'stops') with ordinality a(s,ord) where not t.completed_stop_ids ? (s->>'id') order by ord limit 1;
 if p_event->>'kind'='start' and t.status='planned' then
  update public.personal_planning_trips set status='active',revision=revision+1 where id=t.id returning * into t;
 elsif p_event->>'kind'='arrive' and t.status='active' and t.current_stop_id is null and (p_event->>'stop_id')::uuid=(next_stop->>'id')::uuid then
  updated:=jsonb_set(t.plan,array['stops',idx::text,'departure_at'],to_jsonb(date_trunc('milliseconds',clock_timestamp())+make_interval(secs=>(next_stop->>'visit_seconds')::integer)));
  update public.personal_planning_trips set current_stop_id=(next_stop->>'id')::uuid,current_arrived_at=clock_timestamp(),plan=updated,revision=revision+1 where id=t.id returning * into t;
 elsif p_event->>'kind'='complete_stop' and t.status='active' and (p_event->>'stop_id')::uuid=(next_stop->>'id')::uuid and t.current_stop_id=(next_stop->>'id')::uuid then
  update public.personal_planning_trips set completed_stop_ids=completed_stop_ids||jsonb_build_array(next_stop->>'id'),current_stop_id=null,current_arrived_at=null,revision=revision+1,status=case when jsonb_array_length(completed_stop_ids)+1=jsonb_array_length(plan->'stops') then 'completed' else 'active' end where id=t.id returning * into t;
 elsif p_event->>'kind'='extend_stay' and t.status='active' and (p_event->>'stop_id')::uuid=(next_stop->>'id')::uuid and t.current_stop_id=(next_stop->>'id')::uuid then
  extra:=(p_event->>'extra_seconds')::integer;
  if extra is null or extra not between 1 and 7200 then raise sqlstate 'PT400' using message='Invalid extension';end if;
  updated:=jsonb_set(t.plan,array['stops',idx::text,'departure_at'],to_jsonb(greatest(clock_timestamp(),(next_stop->>'departure_at')::timestamptz)+make_interval(secs=>extra)));
  update public.personal_planning_trips set plan=updated,revision=revision+1 where id=t.id returning * into t;
 else raise sqlstate 'PT400' using message='Invalid trip event';end if;
 response:=c67_private.planning_trip_json(t);
 insert into c67_private.personal_planning_events(owner_id,trip_id,revision,kind,payload) values(actor,t.id,t.revision,p_event->>'kind',p_event);
 insert into c67_private.planning_receipts values(actor,rid,cmd,response);return response;
exception when data_exception then raise sqlstate 'PT400' using message='Malformed trip event';end;$$;

revoke all on function public.request_planning_job(jsonb),public.get_planning_job(uuid),public.list_personal_planning_trips(),public.apply_planning_proposal(uuid,uuid,bigint),public.record_planning_event(uuid,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.request_planning_job(jsonb),public.get_planning_job(uuid),public.list_personal_planning_trips(),public.apply_planning_proposal(uuid,uuid,bigint),public.record_planning_event(uuid,jsonb) to authenticated;
revoke all on function public.claim_planning_job(),public.renew_planning_job(uuid,uuid),public.finish_planning_job(uuid,uuid,jsonb,text) from public,anon,authenticated,service_role;
grant execute on function public.claim_planning_job(),public.renew_planning_job(uuid,uuid),public.finish_planning_job(uuid,uuid,jsonb,text) to service_role;
