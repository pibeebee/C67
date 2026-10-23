begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(14);

insert into auth.users(id, email) values
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'starter-a@example.invalid'),
 ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'starter-b@example.invalid');
insert into public.rundown_versions(id, title, area, summary, stops, published)
values ('99999999-9999-4999-8999-999999999999', 'Unpublished', 'Test', 'Hidden', '[]', false);

set local role anon;
select is(jsonb_array_length(public.list_rundowns()), 1, 'Anonymous catalog includes published seed only');
select is(public.get_rundown('11111111-1111-4111-8111-111111111111')->>'title',
          'Kota Tua Photo Walk', 'Detail matches contract fixture');
select throws_ok($$select public.get_rundown('99999999-9999-4999-8999-999999999999')$$,
                 'PT404', 'Published version not found', 'Draft is hidden');
select throws_ok($$select * from public.trips$$, '42501', 'permission denied for table trips', 'Anonymous cannot read trips');
select throws_ok($$select public.create_trip('11111111-1111-4111-8111-111111111111', '2026-11-01T02:00:00Z', 'cccccccc-cccc-4ccc-8ccc-cccccccccccc')$$,
                 '42501', 'permission denied for function create_trip', 'Anonymous cannot create trips');

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', true);
select is(public.create_trip('11111111-1111-4111-8111-111111111111', '2026-11-01T02:00:00Z', 'cccccccc-cccc-4ccc-8ccc-cccccccccccc')->>'title',
          'Kota Tua Photo Walk', 'Authenticated user can copy a version');
select is((select count(*)::integer from public.trips), 1, 'Owner sees one trip');
select is(public.create_trip('11111111-1111-4111-8111-111111111111', '2026-11-01T02:00:00Z', 'cccccccc-cccc-4ccc-8ccc-cccccccccccc')->>'id',
          (select id::text from public.trips limit 1), 'Retry returns the same trip');
select throws_ok($$select public.create_trip('11111111-1111-4111-8111-111111111111', '2026-11-02T02:00:00Z', 'cccccccc-cccc-4ccc-8ccc-cccccccccccc')$$,
                 'PT409', 'Request ID reused with different input', 'Changed retry input is rejected');
select throws_ok($$update public.trips set title = 'Bypass'$$,
                 '42501', 'permission denied for table trips', 'Direct trip mutation is blocked');
select is((select stops from public.trips limit 1),
          (select stops from public.rundown_versions where id = '11111111-1111-4111-8111-111111111111'), 'Trip contains a source snapshot');
select throws_ok($$update public.rundown_versions set title = 'Bypass'$$,
                 '42501', 'permission denied for table rundown_versions', 'Published content cannot be edited by clients');
select set_config('request.jwt.claim.sub', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', true);
select is((select count(*)::integer from public.trips), 0, 'Another account cannot read the first account trip');
select set_config('request.jwt.claim.sub', '', true);
select throws_ok($$select public.create_trip('11111111-1111-4111-8111-111111111111', '2026-11-01T02:00:00Z', 'dddddddd-dddd-4ddd-8ddd-dddddddddddd')$$,
                 'PT401', 'Traveller session required', 'Definer function rejects a missing subject');

reset role;
select * from finish();
rollback;
