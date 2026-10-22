-- Profiles: sharing with the main profile, per-profile data, uploaded avatars.

-- Whether a profile uses the main profile's settings, add-ons and plugins
-- instead of its own (Nuvio's "uses primary add-ons/plugins").
alter table public.viewer_profiles
    add column if not exists uses_main_settings boolean not null default false,
    add column if not exists uses_main_addons boolean not null default false,
    add column if not exists uses_main_plugins boolean not null default false;

-- Uploaded avatars are stored as "omnia:<storage path>", longer than the
-- illustrated "style:seed" ids.
alter table public.viewer_profiles drop constraint if exists viewer_profiles_avatar_id_check;
alter table public.viewer_profiles
    add constraint viewer_profiles_avatar_id_check
    check (avatar_id is null or char_length(avatar_id) <= 220);

-- One row per profile and kind of data. The payload is the app's own JSON,
-- newest updated_at wins on every device.
create table if not exists public.profile_data (
    user_id uuid not null references auth.users (id) on delete cascade,
    profile_id uuid not null,
    kind text not null check (kind in ('settings', 'home_layout', 'collections', 'addons', 'plugins', 'library', 'stats')),
    payload text not null check (octet_length(payload) <= 8388608),
    updated_at timestamptz not null default timezone('utc', now()),
    primary key (user_id, profile_id, kind)
);

comment on table public.profile_data is
    'Per-profile settings, home layout, collections, add-ons, plugins, library and watch time. Add-on payloads hold add-on addresses, which can carry the user''s own tokens: only the owner can read them.';

alter table public.profile_data enable row level security;

create policy "Users can read their profile data"
    on public.profile_data for select to authenticated
    using ((select auth.uid()) = user_id);

create policy "Users can save their profile data"
    on public.profile_data for insert to authenticated
    with check ((select auth.uid()) = user_id);

create policy "Users can update their profile data"
    on public.profile_data for update to authenticated
    using ((select auth.uid()) = user_id)
    with check ((select auth.uid()) = user_id);

create policy "Users can remove their profile data"
    on public.profile_data for delete to authenticated
    using ((select auth.uid()) = user_id);

-- Avatars uploaded by Omnia's owner to the public "avatars" bucket. The
-- picker shows them as categories before the illustrated sets.
create table if not exists public.avatar_catalog (
    id uuid primary key default gen_random_uuid(),
    display_name text not null default '' check (char_length(display_name) <= 60),
    storage_path text not null unique check (char_length(storage_path) between 1 and 200 and storage_path !~ '\.\.'),
    category text not null check (char_length(category) between 1 and 40),
    sort_order integer not null default 0,
    is_active boolean not null default true,
    created_at timestamptz not null default timezone('utc', now())
);

comment on table public.avatar_catalog is
    'Avatars in the public avatars bucket. storage_path is the object path inside that bucket.';

alter table public.avatar_catalog enable row level security;

create policy "Anyone can read active avatars"
    on public.avatar_catalog for select to anon, authenticated
    using (is_active);

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', true, 524288, array['image/png', 'image/jpeg', 'image/webp'])
on conflict (id) do nothing;
