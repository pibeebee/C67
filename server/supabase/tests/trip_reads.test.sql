begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(26);

insert into auth.users(id, email) values
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'reads-a@example.invalid'),
 ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'reads-b@example.invalid'),
 ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'reads-c@example.invalid');
insert into public.trips(id,owner_id,source_version_id,title,starts_at,stops,request_id) values
 ('40000000-0000-4000-8000-000000000001','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','11111111-1111-4111-8111-111111111111','Saved snapshot','2026-11-01T02:00:00Z','[]','50000000-0000-4000-8000-000000000001'),
 ('40000000-0000-4000-8000-000000000002','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','11111111-1111-4111-8111-111111111111','Saved snapshot','2026-11-01T02:00:00Z','[]','50000000-0000-4000-8000-000000000002'),
 ('40000000-0000-4000-8000-000000000003','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','11111111-1111-4111-8111-111111111111','Saved snapshot','2026-11-02T02:00:00Z','[]','50000000-0000-4000-8000-000000000003'),
 ('40000000-0000-4000-8000-000000000004','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','11111111-1111-4111-8111-111111111111','B snapshot','2026-11-03T02:00:00Z','[]','50000000-0000-4000-8000-000000000004');

set local role anon;
select throws_ok($$select public.list_my_trips()$$,'42501','permission denied for function list_my_trips','Anonymous list denied');
select throws_ok($$select public.get_trip_snapshot('40000000-0000-4000-8000-000000000001')$$,'42501','permission denied for function get_trip_snapshot','Anonymous detail denied');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','',true);
select throws_ok($$select public.list_my_trips()$$,'PT401','Traveller session required','Missing subject list denied');
select throws_ok($$select public.get_trip_snapshot('40000000-0000-4000-8000-000000000001')$$,'PT401','Traveller session required','Missing subject detail denied');
select set_config('request.jwt.claim.sub','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',true);
select is(jsonb_array_length(public.list_my_trips(2)->'items'),2,'Page respects limit');
select ok(public.list_my_trips(2)->>'next_cursor' is not null,'Extra row produces continuation');
select is(public.list_my_trips(2)->'items'->0->>'id','40000000-0000-4000-8000-000000000003','Start time sorts descending');
select is(public.list_my_trips(2)->'items'->1->>'id','40000000-0000-4000-8000-000000000002','UUID breaks time ties descending');
select set_config('c67.read_cursor',public.list_my_trips(2)->>'next_cursor',true);
select is(jsonb_array_length(public.list_my_trips(2,current_setting('c67.read_cursor'))->'items'),1,'Final page contains remaining trip only');
select is(public.list_my_trips(2,current_setting('c67.read_cursor'))->'items'->0->>'id','40000000-0000-4000-8000-000000000001','No gap or duplicate across tied-time boundary');
select ok(public.list_my_trips(2,current_setting('c67.read_cursor'))->>'next_cursor' is null,'Final page has no continuation');
select is(jsonb_array_length(public.list_my_trips()->'items'),3,'Owner list excludes account B');
select is(public.get_trip_snapshot('40000000-0000-4000-8000-000000000001')->>'title','Saved snapshot','Detail uses personal snapshot');
select throws_ok($$select public.get_trip_snapshot('40000000-0000-4000-8000-000000000004')$$,'PT404','Trip not found','Foreign trip gives uniform 404');
select throws_ok($$select public.get_trip_snapshot('40000000-0000-4000-8000-000000000099')$$,'PT404','Trip not found','Missing trip gives uniform 404');
select throws_ok($$select public.get_trip_snapshot(null)$$,'PT400','Trip ID is required','Null ID rejected');
select throws_ok($$select public.list_my_trips(0)$$,'PT400','Limit must be between 1 and 100','Zero limit rejected');
select throws_ok($$select public.list_my_trips(101)$$,'PT400','Limit must be between 1 and 100','Excessive limit rejected');
select throws_ok($$select public.list_my_trips(null)$$,'PT400','Limit must be between 1 and 100','Null limit rejected');
select throws_ok($$select public.list_my_trips(2,'!!!')$$,'PT400','Invalid trip cursor','Malformed cursor rejected');
select throws_ok($$select public.list_my_trips(2,'e30=')$$,'PT400','Invalid trip cursor','Incomplete cursor rejected');
select set_config('request.jwt.claim.sub','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',true);
select throws_ok($$select public.list_my_trips(2,current_setting('c67.read_cursor'))$$,'PT400','Invalid trip cursor','Cursor is bound to account');
select is(jsonb_array_length(public.list_my_trips()->'items'),1,'Account B sees only its trip');
select set_config('request.jwt.claim.sub','cccccccc-cccc-4ccc-8ccc-cccccccccccc',true);
select is(public.list_my_trips(),'{"items":[],"next_cursor":null}'::jsonb,'Empty list is explicit');
reset role;
update public.rundown_versions set title='Changed creator source' where id='11111111-1111-4111-8111-111111111111';
set local role authenticated;
select set_config('request.jwt.claim.sub','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',true);
select is(public.get_trip_snapshot('40000000-0000-4000-8000-000000000001')->>'title','Saved snapshot','Source edit does not replace saved detail');
select throws_ok($$select public.create_trip('11111111-1111-4111-8111-111111111111','infinity','50000000-0000-4000-8000-000000000099')$$,'23514',null,'Non-finite start cannot create an unreadable/cursor-breaking trip');
reset role;
select * from finish();
rollback;
