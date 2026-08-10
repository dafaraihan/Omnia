# Repository Documentation Design

## Objective

Create a small, authoritative documentation set for Omnia that explains how to build, design, secure, operate, measure, and extend the product. Every statement must be traceable to repository evidence, an official platform reference, or a clearly labeled intended direction. The documents must not present unfinished work as implemented.

## Documentation Boundaries

- `README.md` is the entry point: product scope, supported platforms, setup, commands, current maturity, and links to deeper references.
- `DESIGN.md` owns product behavior: information architecture, flows, screen responsibilities, reusable UI elements, interaction states, accessibility, and platform adaptation.
- `SECURITY.md` owns the threat model, trust boundaries, secret handling, authentication, third-party input, playback resolution, dependency hardening, security verification, and open findings.
- `PERFORMANCE.md` owns measurable budgets, profiling, networking, caching, image handling, concurrency, rendering, playback, memory, energy, and performance findings.
- `INFRASTRUCTURE.md` owns deployment topology, environments, Supabase resources, database policies, Edge Functions, libmpv packaging, configuration, CI/CD, observability, backup, and rollback.
- `FUTURE-UPDATES.md` converts verified gaps into a prioritized P0/P1/P2 roadmap with dependencies and completion criteria. It is not a feature wish list.
- `AGENTS.md` gives contributors enforceable working rules and required verification. It links to the specialist documents instead of repeating them.

## Apple Design Reference Policy

Use Apple Design Resources, the Human Interface Guidelines, SF Symbols, and system components as primary references for Omnia flows, screens, and UI elements. Apple TV supplies cinematic hierarchy and playback inspiration, but Omnia must adapt behavior for touch, pointer, keyboard, window resizing, accessibility settings, and each supported platform. Do not reproduce Apple screens pixel for pixel or use private assets.

Each important screen description will state its purpose, primary action, navigation entry and exit, loading/empty/error states, platform adaptations, and accessibility requirements. Reusable UI descriptions will prefer semantic system components and materials over decorative custom controls.

## Audit Method and Finding Format

The documentation will be based on static inspection of Swift, Objective-C, TypeScript, SQL, Xcode settings, entitlements, Supabase configuration, tests, and repository structure. It will distinguish confirmed implementation, configuration that still needs production verification, and future intent.

Security, performance, and infrastructure findings will include:

1. Evidence or affected area.
2. Impact and priority.
3. Required hardening or measurement.
4. Objective completion criteria.

The audit is not a penetration test or a substitute for device profiling. Unknown production settings will be labeled for verification rather than described as vulnerabilities.

## Engineering Standards

Contributors must work from reproduced behavior and measured evidence. New abstractions, dependencies, caches, custom UI, security exceptions, and optimizations require a concrete need. Security-sensitive values stay out of source and logs; third-party data remains untrusted; performance claims require before-and-after measurements. UI work must cover loading, empty, error, accessibility, and platform-specific interaction states.

Changes are complete only after the relevant build, automated tests, static checks, and manual flow verification pass. Security and performance regressions block completion even when the primary feature appears to work.

## Deliverable Quality

The final documents will use direct language, repository paths, executable commands, named owners by subsystem rather than person, and links to official references. Repeated guidance will be replaced with cross-links. Open work will have priorities and exit criteria; vague promises, generic slogans, and invented metrics are excluded.
