-- Ciphertext only. The Edge Function derives p_owner from verified Auth identity.
create table public.credential_vault_entries (
  owner_id uuid not null references auth.users(id) on delete cascade,
  id text not null check (length(id) between 1 and 160),
  revision bigint not null check (revision > 0),
  deleted boolean not null,
  envelope jsonb,
  updated_at timestamptz not null default now(),
  primary key (owner_id, id),
  check ((deleted and envelope is null) or (not deleted and envelope is not null)),
  check (octet_length(envelope::text) <= 360000)
);
create table public.credential_vault_uploads (
  owner_id uuid not null references auth.users(id) on delete cascade,
  upload_id uuid not null,
  entry_id text not null,
  generation uuid not null,
  expected_revision bigint not null check (expected_revision >= 0),
  byte_count integer not null check (byte_count between 1 and 67108864),
  sha256 text not null check (sha256 ~ '^[a-f0-9]{64}$'),
  chunk_count integer not null check (chunk_count between 1 and 128),
  committed_revision bigint,
  created_at timestamptz not null default now(),
  retired_at timestamptz,
  primary key (owner_id, upload_id)
);
create table public.credential_vault_chunks (
  owner_id uuid not null,
  upload_id uuid not null,
  chunk_index integer not null check (chunk_index between 0 and 127),
  envelope jsonb not null check (octet_length(envelope::text) <= 710000),
  primary key (owner_id, upload_id, chunk_index),
  foreign key (owner_id, upload_id) references public.credential_vault_uploads(owner_id, upload_id) on delete cascade
);
alter table public.credential_vault_entries enable row level security;
alter table public.credential_vault_uploads enable row level security;
alter table public.credential_vault_chunks enable row level security;
revoke all on public.credential_vault_entries, public.credential_vault_uploads, public.credential_vault_chunks from public, anon, authenticated;
grant select, insert, update, delete on public.credential_vault_entries, public.credential_vault_uploads, public.credential_vault_chunks to service_role;

-- Every operation shares an account lock, including cleanup and quota reservations.
-- Invoker privileges; only service_role may execute. No request-selected SQL identifiers.
create function public.credential_vault_operation(p_owner uuid, p_action text, p_data jsonb)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare
  e public.credential_vault_entries;
  u public.credential_vault_uploads;
  n bigint;
  r bigint;
  result jsonb;
begin
  perform pg_advisory_xact_lock(hashtextextended(p_owner::text, 74923));
  delete from public.credential_vault_uploads where owner_id=p_owner
    and ((committed_revision is null and created_at < now()-interval '24 hours')
      or retired_at < now()-interval '24 hours');
  if p_action='list' then
    select coalesce(jsonb_agg(jsonb_build_object('id',v.id,'revision',v.revision,'deleted',v.deleted) order by v.id), '[]'::jsonb) into result
      from public.credential_vault_entries v where owner_id=p_owner;
    return result;
  elsif p_action='read' then
    select to_jsonb(v) into result from public.credential_vault_entries v where owner_id=p_owner and id=p_data->>'id';
    return result;
  elsif p_action='upload' then
    select * into u from public.credential_vault_uploads where owner_id=p_owner and upload_id=(p_data->>'uploadID')::uuid;
    return to_jsonb(u);
  elsif p_action='begin' then
    select count(*), coalesce(sum(((byte_count + chunk_count * 16 + 2) / 3) * 4 + chunk_count * 256),0) into n,r
      from public.credential_vault_uploads where owner_id=p_owner;
    if n >= 1000 or r+(((p_data->>'byteCount')::bigint+(p_data->>'chunkCount')::bigint*16+2)/3)*4+(p_data->>'chunkCount')::bigint*256 > 268435456 then
      raise exception using errcode='P0001', message='quota';
    end if;
    insert into public.credential_vault_uploads(owner_id,upload_id,entry_id,generation,expected_revision,byte_count,sha256,chunk_count)
      values(p_owner,(p_data->>'uploadID')::uuid,p_data->>'id',(p_data->>'generation')::uuid,
      (p_data->>'expectedRevision')::bigint,(p_data->>'byteCount')::integer,p_data->>'sha256',(p_data->>'chunkCount')::integer);
    return '{}'::jsonb;
  elsif p_action in ('put','chunk') then
    select * into u from public.credential_vault_uploads where owner_id=p_owner and upload_id=(p_data->>'uploadID')::uuid;
    if u.upload_id is null or u.retired_at is not null or (p_data->>'index')::integer >= u.chunk_count then
      raise exception using errcode='P0001', message='missing';
    end if;
    if p_action='chunk' then
      -- Access is tied to the current non-deleted entry revision.
      if u.committed_revision is distinct from (select revision from public.credential_vault_entries where owner_id=p_owner and id=u.entry_id and not deleted)
        then raise exception using errcode='P0001', message='missing'; end if;
      select envelope into result from public.credential_vault_chunks where owner_id=p_owner and upload_id=u.upload_id and chunk_index=(p_data->>'index')::integer;
      return result;
    end if;
    if u.committed_revision is not null then raise exception using errcode='P0001', message='complete'; end if;
    insert into public.credential_vault_chunks values(p_owner,u.upload_id,(p_data->>'index')::integer,p_data->'envelope')
      on conflict(owner_id,upload_id,chunk_index) do update set envelope=excluded.envelope;
    return '{}'::jsonb;
  elsif p_action in ('write','commit') then
    if p_action='commit' then
      select * into u from public.credential_vault_uploads where owner_id=p_owner and upload_id=(p_data->>'uploadID')::uuid;
      if u.upload_id is null or u.retired_at is not null then raise exception using errcode='P0001', message='missing'; end if;
      if (select count(*) from public.credential_vault_chunks where owner_id=p_owner and upload_id=u.upload_id) <> u.chunk_count then
        raise exception using errcode='P0001', message='incomplete'; end if;
    end if;
    select * into e from public.credential_vault_entries where owner_id=p_owner and id=p_data->>'id';
    if coalesce(e.revision,0) <> (p_data->>'expectedRevision')::bigint then
      return jsonb_build_object('conflict',true,'entry',case when e.id is null then jsonb_build_object('id',p_data->>'id','revision',0,'deleted',true) else to_jsonb(e) end);
    end if;
    if e.id is null and (select count(*) from public.credential_vault_entries where owner_id=p_owner)>=2000 then
      raise exception using errcode='P0001', message='quota'; end if;
    if not (p_data->>'deleted')::boolean and (e.id is null or e.deleted) and
      (select count(*) from public.credential_vault_entries where owner_id=p_owner and not deleted)>=1000 then
      raise exception using errcode='P0001', message='quota'; end if;
    insert into public.credential_vault_entries(owner_id,id,revision,deleted,envelope)
      values(p_owner,p_data->>'id',coalesce(e.revision,0)+1,(p_data->>'deleted')::boolean,nullif(p_data->'envelope','null'::jsonb))
      on conflict(owner_id,id) do update set revision=excluded.revision,deleted=excluded.deleted,envelope=excluded.envelope,updated_at=now()
      returning * into e;
    update public.credential_vault_uploads set retired_at=now() where owner_id=p_owner and entry_id=e.id and retired_at is null
      and (p_action<>'commit' or upload_id<>u.upload_id);
    if p_action='commit' then
      if u.entry_id<>e.id or u.expected_revision<>(p_data->>'expectedRevision')::bigint then
        raise exception using errcode='P0001', message='invalid'; end if;
      update public.credential_vault_uploads set committed_revision=e.revision where owner_id=p_owner and upload_id=u.upload_id;
    end if;
    return jsonb_build_object('conflict',false,'entry',case when e.id is null then jsonb_build_object('id',p_data->>'id','revision',0,'deleted',true) else to_jsonb(e) end);
  end if;
  raise exception using errcode='P0001', message='invalid';
end;
$$;
revoke all on function public.credential_vault_operation(uuid,text,jsonb) from public, anon, authenticated;
grant execute on function public.credential_vault_operation(uuid,text,jsonb) to service_role;

-- Supabase platform extension; deployment requires pg_cron availability/enabling.
-- https://supabase.com/docs/guides/cron/install
-- https://supabase.com/docs/guides/cron/quickstart
create extension if not exists pg_cron with schema pg_catalog;
create schema if not exists credential_vault_private;
revoke all on schema credential_vault_private from public, anon, authenticated;
grant usage on schema credential_vault_private to service_role;

create index credential_vault_expirable_uploads
  on public.credential_vault_uploads (coalesce(retired_at, created_at), owner_id, upload_id)
  where retired_at is not null or committed_revision is null;

-- Inactive accounts must not retain orphaned ciphertext forever. A run examines
-- at most 128 candidates and deletes at most 16 uploads (each at most 128 chunks).
-- Busy accounts are skipped instead of blocking credential writes. Rechecking
-- eligibility after the SAME owner lock protects a concurrently committed upload.
-- Backlogs drain in subsequent hourly batches; monitor cron history and expired
-- row counts during rollout. Committed current generations and entry tombstones
-- are never deleted by maintenance. Tombstone IDs remain reserved (2,000 total).
create function credential_vault_private.cleanup_expired_uploads()
returns integer language plpgsql security invoker set search_path = '' as $$
declare
  candidate record;
  removed integer := 0;
  affected integer;
begin
  for candidate in
    select owner_id, upload_id
    from public.credential_vault_uploads
    where (retired_at is not null or committed_revision is null)
      and coalesce(retired_at, created_at) < now() - interval '24 hours'
    order by coalesce(retired_at, created_at), owner_id, upload_id
    limit 128
  loop
    if pg_try_advisory_xact_lock(hashtextextended(candidate.owner_id::text, 74923)) then
      delete from public.credential_vault_uploads
      where owner_id = candidate.owner_id and upload_id = candidate.upload_id
        and (retired_at is not null or committed_revision is null)
        and coalesce(retired_at, created_at) < now() - interval '24 hours';
      get diagnostics affected = row_count;
      removed := removed + affected;
      exit when removed >= 16;
    end if;
  end loop;
  return removed;
end;
$$;
revoke all on function credential_vault_private.cleanup_expired_uploads() from public, anon, authenticated;
grant execute on function credential_vault_private.cleanup_expired_uploads() to service_role;

-- Executes locally inside Postgres as the migration's scheduling role. No HTTP,
-- bearer token, service-role secret, or credential material enters cron metadata.
select cron.schedule(
  'credential-vault-expired-uploads',
  '0 * * * *',
  'set statement_timeout = ''45s''; select credential_vault_private.cleanup_expired_uploads();'
);
