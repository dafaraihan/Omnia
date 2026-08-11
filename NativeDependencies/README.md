# Native playback dependencies

This directory defines the native source inputs allowed for Omnia's macOS
playback work. It intentionally contains no prebuilt binaries.

`playback-dependencies.json` currently records a **provisional, incomplete**
top-level source set for local development. It is not a distribution approval.
The manifest verifier has two modes:

```sh
# Structural checks for local development; accepts explicitly pending review.
Scripts/verify-playback-manifest.sh --allow-pending-review \
  NativeDependencies/playback-dependencies.json

# Release gate; fails until the complete closure and independent reviews exist.
Scripts/verify-playback-manifest.sh \
  NativeDependencies/playback-dependencies.json
```

Before the release gate may pass, every bundled transitive library must be
listed with its exact source and digest, publisher signatures/checksums must be
validated where available, two clean builders must reproduce the artifacts,
and a named independent reviewer must approve provenance and license evidence.
Legal approval of the LGPL relinking/source-offer strategy is a separate human
gate. See the native dependency implementation plan and `SECURITY.md`.

The intended build profile keeps mpv in LGPL mode (`-Dgpl=false`) and FFmpeg
with both GPL and nonfree components disabled. GPL DVD libraries are excluded;
DVD inputs must remain visible but explicitly unsupported. libbluray covers
only unencrypted Blu-ray content and does not provide decryption keys.
