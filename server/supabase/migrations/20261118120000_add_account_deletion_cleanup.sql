-- A service-only manifest lets Storage remove the bytes before GoTrue deletes the account.
create table c67_private.account_deletions (
    owner_id uuid primary key references auth.users(id) on delete cascade
);

revoke all on c67_private.account_deletions from public, anon, authenticated, service_role;

create function c67_private.block_deleting_account_upload() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
    perform 1 from auth.users where id = new.owner_id for key share;
    if exists (select 1 from c67_private.account_deletions where owner_id = new.owner_id) then
        raise sqlstate 'PT403' using message = 'Account deletion in progress';
    end if;
    return new;
end;
$$;

revoke all on function c67_private.block_deleting_account_upload() from public, anon, authenticated, service_role;
create trigger block_deleting_account_upload before insert on public.journal_uploads
    for each row execute function c67_private.block_deleting_account_upload();

alter table public.journal_uploads drop constraint journal_uploads_owner_id_fkey,
    add constraint journal_uploads_owner_id_fkey foreign key (owner_id) references auth.users(id) on delete cascade;
alter table public.journal_entries drop constraint journal_entries_upload_id_fkey,
    add constraint journal_entries_upload_id_fkey foreign key (upload_id) references public.journal_uploads(id) on delete cascade;

create function public.account_deletion_objects(p_owner uuid) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
begin
    if auth.role() is distinct from 'service_role' or p_owner is null then raise insufficient_privilege; end if;

    perform 1 from auth.users where id = p_owner for update;
    if found then
        insert into c67_private.account_deletions (owner_id) values (p_owner) on conflict do nothing;
    end if;

    -- Close pending uploads before listing bytes. Wait for already leased workers.
    update public.journal_uploads
       set state = 'rejected', failure_code = 'owner_or_trip_removed', lease_id = null, lease_until = null
     where owner_id = p_owner and
       (state in ('uploading', 'queued') or (state = 'processing' and lease_until <= now()));
    if exists (select 1 from public.journal_uploads where owner_id = p_owner and state = 'processing') then
        return null;
    end if;

    return coalesce((
        select jsonb_agg(to_jsonb(objects))
        from (
            select o.bucket_id, o.name from storage.objects o
             where o.owner_id = p_owner::text
                or (o.bucket_id in ('c67-journal-raw', 'c67-journal-ready')
                    and split_part(o.name, '/', 1) = p_owner::text)
             order by o.bucket_id, o.name limit 100
        ) objects
    ), '[]'::jsonb);
end;
$$;

revoke all on function public.account_deletion_objects(uuid) from public, anon, authenticated, service_role;
grant execute on function public.account_deletion_objects(uuid) to service_role;
