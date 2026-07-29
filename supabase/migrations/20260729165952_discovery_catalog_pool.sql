-- A server-managed discovery index gives Omnia a predictable initial catalog
-- without exposing provider credentials or metadata records to app clients.
-- Entries are populated only by the metadata Edge Function using service_role.
create table public.discovery_catalog_entries (
    id uuid primary key default extensions.gen_random_uuid(),
    media_type text not null check (media_type in ('movie', 'series')),
    catalog_category text not null check (catalog_category in ('popular')),
    source_page integer not null check (source_page > 0),
    position integer not null check (position > 0),
    metadata_record_id uuid not null references public.metadata_records (id) on delete cascade,
    created_at timestamptz not null default timezone('utc', now()),
    updated_at timestamptz not null default timezone('utc', now()),
    unique (media_type, catalog_category, source_page, position),
    unique (media_type, catalog_category, metadata_record_id)
);

create index discovery_catalog_entries_page_idx
    on public.discovery_catalog_entries (media_type, catalog_category, source_page, position);

alter table public.discovery_catalog_entries enable row level security;
revoke all on table public.discovery_catalog_entries from anon, authenticated;
grant all on table public.discovery_catalog_entries to service_role;

create policy "Service role manages discovery catalog"
    on public.discovery_catalog_entries for all to service_role
    using (true)
    with check (true);

comment on table public.discovery_catalog_entries is 'Server-managed discovery index seeded from licensed provider catalog pages. No direct client policy.';
