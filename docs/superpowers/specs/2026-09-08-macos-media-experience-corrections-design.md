# macOS Media Experience Corrections Design

## Scope

This change is macOS-only. It must preserve the existing Omnia navigation,
library state, source resolution, context menus, playback controls, aspect
ratio control, watch-state actions, subtitle menus, and Liquid Glass behavior
unless this specification explicitly changes them. No iPhone or iPad UI work
or iOS build is part of this batch.

## Window Hero Composition

Omnia will render one hero artwork canvas at the macOS window root. The image
is sized against the full window rather than either `NavigationSplitView`
column, so opening and closing the sidebar does not rescale or duplicate it.
Home and title-detail heroes contribute only foreground content on macOS:
transparent logo, metadata and MDBList ratings, synopsis, actions, carousel
navigation, and page control. The sidebar remains the native split-view
sidebar and refracts this single canvas.

On iOS, the existing local hero artwork remains unchanged. The detail content
below the hero uses the same blurred, darkened artwork-accent background as
Home instead of the plain window background.

## Glass Modals

Synopsis and source selection remain same-window, single-surface glass
overlays on macOS. Their material is darker and more contrast-preserving,
matching the legibility of the native context menu while still refracting the
artwork beneath it. The modal must not become an opaque gray panel. Modal
controls retain their existing hover and press contracts.

## macOS Toolbar and Settings Layout

Every macOS root destination and pushed subpage displays its page title in the
leading toolbar area. Page actions and filters use the trailing toolbar area.
Library and Discover filters are trailing controls. Settings search is a
trailing toolbar search field.

The Settings root and every Settings destination use a shared responsive,
left-aligned content container. The container consumes the useful width of the
detail pane with a readable maximum line length and modest outer margins; it
must not be centered as a narrow column or leave excessive unused space.

## Library Information Architecture

The Library root shows three mutually exclusive horizontal shelves:

- My List: titles explicitly added to the library that have no unfinished
  playback progress and are not completed.
- Continue Watching: titles with unfinished playback progress, regardless of
  whether they were explicitly added to the library.
- Rewatch: completed titles.

An unfinished saved title appears only in Continue Watching. A completed
title appears only in Rewatch. Each shelf title and chevron opens a dedicated
grid page for that collection. Continue Watching reuses the existing resume
card and playback behavior.

The Library toolbar filter applies simultaneously to all three shelves and
their source collections. Existing kind and sorting choices remain. Its SF
Symbols are unfilled and white at rest on macOS, not accent blue.

## Discover and Catalog Filtering

Discover uses native macOS toolbar menus consistent with Library. Available
filters are Genre, Catalogs, Kind, and Date.

Date contains two independent sections:

- Release period: Any Date, This Year, Last Year, Last 5 Years, and Choose
  Year with a scrollable year list.
- Sort: Catalog Order, Newest First, and Oldest First.

The Catalogs filter reflects Settings > Catalogs. Built-in home-shelf and
installed add-on catalog toggles determine which shelves appear in Discover,
and changes apply immediately. Kind hides incompatible shelves and items.
Genre and date criteria are sent to providers only where the provider contract
supports them. Unsupported add-on criteria are applied locally to returned
metadata without inventing add-on parameters. Filter changes must affect real
results, reset pagination where applicable, cancel stale requests, and expose
loading, empty, partial-success, and retry states.

## Subtitle Preference Ownership

SettingsPreferences is the durable source of truth for subtitle enablement,
preferred and fallback language, font, background, size, scale, position,
shadow opacity, and shadow blur. Settings > Subtitle exposes these values and
keeps its preview synchronized.

Every playback session initializes MPV subtitle selection and style from the
stored preferences. Changes made in the playback subtitle panel update the
same preferences and apply immediately to the active player. Track identifiers
are session-local and are not persisted; the selected track's normalized
language is persisted instead. Disabling subtitles persists the disabled
preference.

## Resume Persistence

Playback progress is saved using the active media identity, episode identity,
position, and duration. It is persisted periodically and forced on player
close, stop, source replacement, and app/window teardown. Writes must not be
lost behind unstructured asynchronous refreshes.

Movie Play and Rewatch start at zero; Movie Resume starts at the saved
timestamp. Series, TV, and anime Play and Rewatch target S1E1 at zero; Resume
targets the saved episode and timestamp. The explicit playback intent survives
source selection and the initial seek is applied only when the playback engine
can honor it. The behavior must survive application relaunch.

## Skip Intro and Up Next

IntroDB lookup remains read-only, bounded, and cancellable. Its current lookup
identity and automation thresholds are regression-tested against the current
playback session. A valid active intro produces a Skip Intro pill above the
bottom-left metadata block. Up Next appears above the bottom-right audio,
subtitle, and speed controls. Neither may overlap the timeline or transport
controls.

Both prompts use the existing interactive playback Liquid Glass treatment:
lift and darken on hover, darken on press, white unfilled SF Symbols where an
unfilled symbol exists, keyboard activation, and full-pill hit targets. Up
Next opens the existing source selector for the next episode.

## Verification

Each behavior change starts with a focused failing XCTest. Verification
includes the relevant focused tests, the full macOS XCTest suite, a macOS app
build, `git diff --check`, and live macOS smoke checks for sidebar shown/hidden,
Home/detail continuity, Library and Discover filtering, Settings layout,
subtitle persistence, movie/series resume, Skip Intro, and Up Next placement.
Provider-backed behavior that cannot be deterministically exercised is
reported separately rather than inferred. No iOS build is run.
