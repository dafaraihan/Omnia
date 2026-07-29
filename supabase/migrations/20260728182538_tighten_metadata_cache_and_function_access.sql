-- `metadata_records` is intentionally server-only. An explicit service-role
-- policy documents that design without granting browser clients any access.
create policy "Service role manages metadata cache"
    on public.metadata_records for all to service_role
    using (true)
    with check (true);

-- This pre-existing event-trigger function is needed to enable RLS for newly
-- created public tables, but it is not an RPC API. Event triggers do not need
-- browser roles to have EXECUTE on their backing function.
revoke execute on function public.rls_auto_enable() from public, anon, authenticated;
