# Omnia Supabase contract

This directory is the deployment boundary for Omnia's cloud data. The Swift app
must never contain a TMDB read token, TVDB API key, TVDB subscriber PIN, or a
Supabase `service_role` key.

## What the first migration creates

| Resource | Client access | Purpose |
| --- | --- | --- |
| `profiles` | Own row only | Account identity presented by Omnia. |
| `library_entries` | Own rows only | Cross-device saved, watching, and completed states. |
| `playback_progress` | Own rows only | Resumable playback position, including episode-specific progress. |
| `metadata_records` | None | Shared TMDB/TVDB cache written by the Edge Function only. |

The library and progress tables are added to Realtime for signed-in device sync.
Every table in `public` has RLS enabled; policies use the authenticated user ID
as the ownership boundary.

## Metadata function contract

The authenticated `metadata` Edge Function accepts only POST requests:

```json
{ "action": "search", "query": "The Bear", "type": "series", "language": "en-US" }
```

```json
{ "action": "details", "provider": "tmdb", "id": "136311", "type": "series", "language": "en-US" }
```

Search returns normalized records from TMDB and TVDB. Details reads the server
cache first, refreshes an expired record from the selected provider, and returns
the normalized record plus a `cached` flag.

## Deployment sequence

1. Create or select the Supabase project and link this directory with `supabase link`.
2. In the Dashboard, expose only `profiles`, `library_entries`, and `playback_progress` through the Data API.
3. Configure Apple, Google, and Facebook providers under Auth. Add Omnia's native redirect URL to the Redirect URLs allow list.
4. Set the server-only secrets with `supabase secrets set --env-file supabase/.env` after creating a local file from `.env.example`.
5. Run `supabase db push`, then `supabase functions deploy metadata`.
6. Configure the app with the project URL and publishable key only, then test each account provider, a metadata search, a detail request, and a second-device progress update.

Local verification requires Docker because `supabase start`, `supabase db lint --local`, and `supabase functions serve` run the local Supabase stack in containers.
