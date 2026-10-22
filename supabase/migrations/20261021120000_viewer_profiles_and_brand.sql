-- Viewer profiles (Nuvio-style "Who's watching?"), up to six per account.
-- PINs never leave the device, so there is no PIN column here.
create table if not exists public.viewer_profiles (
    user_id uuid not null references auth.users (id) on delete cascade,
    id uuid not null,
    name text not null check (char_length(name) between 1 and 24),
    avatar_id text check (avatar_id is null or char_length(avatar_id) <= 80),
    color_hex text not null check (color_hex ~ '^[0-9A-Fa-f]{6}$'),
    position smallint not null default 0 check (position between 0 and 5),
    is_locked boolean not null default false,
    deleted_at timestamptz,
    created_at timestamptz not null default timezone('utc', now()),
    updated_at timestamptz not null default timezone('utc', now()),
    primary key (user_id, id)
);

comment on table public.viewer_profiles is
    'A signed-in user''s viewer profiles. Deleted profiles keep a tombstone (deleted_at) so other devices drop them too.';

alter table public.viewer_profiles enable row level security;

create policy "Users can read their viewer profiles"
    on public.viewer_profiles for select to authenticated
    using ((select auth.uid()) = user_id);

create policy "Users can create their viewer profiles"
    on public.viewer_profiles for insert to authenticated
    with check ((select auth.uid()) = user_id);

create policy "Users can update their viewer profiles"
    on public.viewer_profiles for update to authenticated
    using ((select auth.uid()) = user_id)
    with check ((select auth.uid()) = user_id);

create policy "Users can remove their viewer profiles"
    on public.viewer_profiles for delete to authenticated
    using ((select auth.uid()) = user_id);

-- Public, read-only brand images for the auth emails (the Omnia wordmark).
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('brand', 'brand', true, 1048576, array['image/png'])
on conflict (id) do nothing;
