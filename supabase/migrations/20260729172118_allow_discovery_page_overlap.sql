-- Provider popularity order can move between requests. A title may therefore
-- appear at the boundary of adjacent pages; preserve that legitimate overlap
-- and keep uniqueness scoped to a page position only.
alter table public.discovery_catalog_entries
    drop constraint discovery_catalog_entries_media_type_catalog_category_metad_key;
