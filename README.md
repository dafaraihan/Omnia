# Omnia

Omnia is a native media discovery, library, and HTTPS playback hub for iPhone, iPad, and Mac. It brings built-in metadata, user-selected providers, and declarative HTTPS add-ons into one Apple-platform experience.

Apple TV is a design reference for cinematic hierarchy, focus, and playback inspiration. It is not a current deployment target: the Xcode project supports iOS, iPadOS, and macOS, and tvOS needs a dedicated target and platform-specific design work before it can be supported.

## Scope

Omnia helps people discover titles, inspect metadata, save media to a local library, choose sources from enabled add-ons, and play approved HTTPS media URLs. It does not:

- host media;
- embed torrent or peer-to-peer transport; or
- trust add-on manifests, responses, resolvers, or stream URLs by default.

Torrent identifiers are data, not playable media. A resolver is optional and must be explicitly configured by the user; only an approved HTTPS result may reach the player.

## Requirements

- Xcode for Apple-platform development and SwiftUI previews.
- Homebrew and libmpv for macOS builds: `brew install mpv`. The macOS target links libmpv and bundles the locally installed runtime during its build.
- The Supabase CLI and Docker for the local Supabase stack.
- Deno for checking and testing the metadata Edge Function.

## Get started

1. Configure the Apple app with the Supabase project URL and publishable key only. Do not put provider credentials or a `service_role` key in the app.
2. For the server-side metadata function, create a local-only `supabase/.env` from `supabase/.env.example`; it must never be committed. Set the required server-only values: `TMDB_READ_ACCESS_TOKEN`, `TVDB_API_KEY`, and `METADATA_SEED_TOKEN`. `TVDB_SUBSCRIBER_PIN` is optional.
3. Open the project:

   ```sh
   open Omnia.xcodeproj
   ```

The documentation map below contains the full credential boundary, Auth configuration, and hosted deployment sequence.

### Build and test

Run the macOS build and XCTest suite from the repository root. The test host must be signed for the bundled libmpv runtime.

```sh
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' build
xcodebuild -project Omnia.xcodeproj -scheme Omnia -destination 'platform=macOS' test
```

Check and test the metadata Edge Function:

```sh
deno check --config supabase/functions/metadata/deno.json \
  --lock supabase/functions/metadata/deno.lock --frozen \
  supabase/functions/metadata/index.ts
deno test --config supabase/functions/metadata/deno.json \
  --lock supabase/functions/metadata/deno.lock --frozen \
  supabase/functions/metadata
```

### Local Supabase

Docker is required for each local Supabase command below.

```sh
supabase start
supabase db lint --local
supabase functions serve metadata --env-file supabase/.env
```

### Deployment and secrets

**Pending manual deployment — these live-state changes require explicit human authorization.** The metadata update described in [INFRASTRUCTURE.md](INFRASTRUCTURE.md#pending-metadata-deployment) has not been deployed. Verify the target, reviewed source, and rollback evidence before linking the intended Supabase project, changing secrets, applying migrations, or deploying the function:

```sh
supabase link
supabase secrets set --env-file supabase/.env
supabase db push
supabase functions deploy metadata
```

The hosted runtime supplies `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY`; do not add either to `supabase/.env`. The documentation map below includes the required Dashboard configuration and post-deployment checks.

## Current maturity

The repository contains the native app target, a macOS libmpv playback integration, a Supabase schema, and a metadata Edge Function, alongside focused Apple and Edge Function tests. The experience is still under active development: cloud library synchronization is not connected to app state, tvOS is not a target, several provider and playback paths have intentionally limited scope, and broader UI, accessibility, backend, and device verification remains planned. Consult the design and future-update references before treating an integration as production-ready.

## Documentation map

- [Product and interaction design](DESIGN.md)
- [Security boundaries and verification](SECURITY.md)
- [Performance budgets and profiling](PERFORMANCE.md)
- [Infrastructure and operations](INFRASTRUCTURE.md)
- [Prioritized future updates](FUTURE-UPDATES.md)
- [Contributor repository guidelines](AGENTS.md)
- [Supabase deployment contract](supabase/README.md)
