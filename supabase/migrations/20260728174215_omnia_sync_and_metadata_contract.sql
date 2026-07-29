-- Omnia's cloud contract intentionally separates user-owned data from provider
-- metadata. The iOS app reads and writes only its own profile, library, and
-- progress rows. TMDB and TVDB data is populated only by the Edge Function.

create extension if not exists pgcrypto with schema extensions;

create table public.profiles (
    id uuid primary key references auth.users (id) on delete cascade,
    display_name text,
    avatar_url text,
    created_at timestamptz not null default timezone('utc', now()),
    updated_at timestamptz not null default timezone('utc', now())
);

create table public.metadata_records (
    id uuid primary key default extensions.gen_random_uuid(),
    canonical_key text not null unique,
    provider text not null check (provider in ('tmdb', 'tvdb')),
    provider_id text not null,
    media_type text not null check (media_type in ('movie', 'series', 'episode')),
    title text not null,
    original_title text,
    overview text,
    release_date date,
    poster_path text,
    backdrop_path text,
    external_ids jsonb not null default '{}'::jsonb,
    payload jsonb not null default '{}'::jsonb,
    source_updated_at timestamptz not null,
    expires_at timestamptz not null,
    created_at timestamptz not null default timezone('utc', now()),
    updated_at timestamptz not null default timezone('utc', now()),
    unique (provider, provider_id, media_type)
);

create table public.library_entries (
    id uuid primary key default extensions.gen_random_uuid(),
    user_id uuid not null references auth.users (id) on delete cascade,
    metadata_record_id uuid not null references public.metadata_records (id) on delete restrict,
    state text not null default 'saved' check (state in ('saved', 'watching', 'completed')),
    is_favorite boolean not null default false,
    added_at timestamptz not null default timezone('utc', now()),
    updated_at timestamptz not null default timezone('utc', now()),
    unique (user_id, metadata_record_id)
);

create table public.playback_progress (
    id uuid primary key default extensions.gen_random_uuid(),
    user_id uuid not null references auth.users (id) on delete cascade,
    metadata_record_id uuid not null references public.metadata_records (id) on delete restrict,
    -- "feature" represents a movie or a series-level resume. Episodes use a
    -- stable provider-specific key, for example "s01e04".
    episode_key text not null default 'feature',
    position_seconds double precision not null default 0 check (position_seconds >= 0),
    duration_seconds double precision check (duration_seconds is null or duration_seconds >= 0),
    is_completed boolean not null default false,
    last_played_at timestamptz not null default timezone('utc', now()),
    updated_at timestamptz not null default timezone('utc', now()),
    unique (user_id, metadata_record_id, episode_key),
    check (duration_seconds is null or position_seconds <= duration_seconds)
);

create index library_entries_user_updated_idx
    on public.library_entries (user_id, updated_at desc);
create index playback_progress_user_played_idx
    on public.playback_progress (user_id, last_played_at desc);
create index metadata_records_expiry_idx
    on public.metadata_records (expires_at);

alter table public.profiles enable row level security;
alter table public.metadata_records enable row level security;
alter table public.library_entries enable row level security;
alter table public.playback_progress enable row level security;

-- A profile has no public directory. Authentication does not grant access to
-- another Omnia user's identity or media history.
create policy "Users can read their profile"
    on public.profiles for select to authenticated
    using ((select auth.uid()) = id);
create policy "Users can create their profile"
    on public.profiles for insert to authenticated
    with check ((select auth.uid()) = id);
create policy "Users can update their profile"
    on public.profiles for update to authenticated
    using ((select auth.uid()) = id)
    with check ((select auth.uid()) = id);

create policy "Users can read their library"
    on public.library_entries for select to authenticated
    using ((select auth.uid()) = user_id);
create policy "Users can save to their library"
    on public.library_entries for insert to authenticated
    with check ((select auth.uid()) = user_id);
create policy "Users can update their library"
    on public.library_entries for update to authenticated
    using ((select auth.uid()) = user_id)
    with check ((select auth.uid()) = user_id);
create policy "Users can remove from their library"
    on public.library_entries for delete to authenticated
    using ((select auth.uid()) = user_id);

create policy "Users can read their playback progress"
    on public.playback_progress for select to authenticated
    using ((select auth.uid()) = user_id);
create policy "Users can create their playback progress"
    on public.playback_progress for insert to authenticated
    with check ((select auth.uid()) = user_id);
create policy "Users can update their playback progress"
    on public.playback_progress for update to authenticated
    using ((select auth.uid()) = user_id)
    with check ((select auth.uid()) = user_id);
create policy "Users can remove their playback progress"
    on public.playback_progress for delete to authenticated
    using ((select auth.uid()) = user_id);

-- `metadata_records` has RLS but deliberately has no client policy. It is a
-- shared provider cache accessed only by the service-role Edge Function.
revoke all on table public.profiles from anon;
revoke all on table public.library_entries from anon;
revoke all on table public.playback_progress from anon;
revoke all on table public.metadata_records from anon, authenticated;

grant select, insert, update on table public.profiles to authenticated;
grant select, insert, update, delete on table public.library_entries to authenticated;
grant select, insert, update, delete on table public.playback_progress to authenticated;
grant all on table public.profiles, public.metadata_records, public.library_entries, public.playback_progress to service_role;

-- These two small, user-owned datasets are the only rows replicated to signed-
-- in devices. Metadata remains behind the authenticated Edge Function.
alter table public.library_entries replica identity full;
alter table public.playback_progress replica identity full;
alter publication supabase_realtime add table public.library_entries, public.playback_progress;

comment on table public.metadata_records is 'Server-managed TMDB/TVDB cache. No direct client policy.';
comment on table public.library_entries is 'A signed-in user''s saved media state.';
comment on table public.playback_progress is 'A signed-in user''s resumable playback state.';
