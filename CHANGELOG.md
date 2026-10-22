# Changelog

Notable changes to WarbandFYI are recorded here. Work that has not been published as a versioned release stays under Unreleased.

## Unreleased

### Added

- Optional, read-only **Queued in Rematch** status on Notebook pets, Sheet and FYI. Hidden when Rematch is unavailable or the exact pet is not queued; no extra notifications or queue management.
- Individual-pet Notebook level lists with saved GUIDs, live level-25 completion, a paged picker, floating Sheet support and FYI progress. Older species entries remain available for choosing a specific copy.
- A concise addon README and a separate guide covering usage, tracking behaviour, saved data and development checks.
- This changelog to track notable changes alongside the Git commit history.
- `lua tests/RunAll.lua` to run every regression test from the repository root.
- Regression tests for pet session progression and existing pet/profession aggregation behaviour.

### Fixed

- Recurring event FYIs keep the same occurrence across a reload, so a completed or hidden holiday checklist no longer comes back a few seconds later.
- Dashboard **Net Gold** opens the gold chart for the period you are viewing.
- Pet Level Lists can be renamed from the block menu.
- Day, week, and month boundaries stay on local midnight across a daylight-saving change.
- Restored session and event rows cannot reuse an id the counter had already passed.
- Learned holiday icons are capped, so that cache cannot grow without limit.
- Adopting a name-and-realm character record now carries its lifetime totals and gold with it.
- A finished month that was never rolled up still shows its remaining days after retention, instead of an empty month.
- `/wbfyi search` matches any capitalisation of the command.
- Search no longer covers the window close button, and the copy dialog closes with Esc or when the main window hides.
- Typing in a search box during combat no longer calls a protected keyboard API.
- Pet Battles **New Pets** only lists new-species captures.
- Duplicating a checklist keeps a linked resource goal.
- Adding a Pet Level List from an empty Notebook page now creates a section and opens the pet picker.
- Collection Hunts no longer treats a Raid Finder Ji-Kun kill as a finished Clutch of Ji-Kun attempt. Normal and Heroic lockouts still count.
- `/wbfyi hunt` only handles the hunt command, so words that merely start with "hunt" open the window again.
- `/wbfyi search` only handles the search command, so a word such as "searching" is not treated as a query.
- The live session clock no longer keeps ticking while Collection Hunts is the open view.
- Recent Pet Activity now shows known pet levelling progression within a session, so a pet trained from 1 to 25 can show that full span instead of only the last battle's 24 -> 25. Individual events and their original gains are preserved.
- Session progression respects starting levels, unique pet IDs and session boundaries, and falls back safely when history is missing.
- An unavailable starting level no longer produces an assumed one-level gain.

### Changed

- Balance History and Net Gold History draw a smooth, anti-aliased line with a soft glow and a gradient fill. Observation dots appear on hover; only the latest point stays marked.

### Removed

- The unused Plans window. Notes and plans live in the Notebook, and saved Plans data still migrates into it.
- The outdated `COLLECTION-HUNTS-1K-NOTES.txt` and `COLLECTION-HUNTS-README.txt` development notes.

## Repository baseline — 2026-10-16

- Imported the installed Retail addon into this repository, with addon version `0.2.0-dev.2c`.
- Preserved the repository's MIT licence.

This marks the start of the repository history, not a new addon release. Changes from before the import have not been reconstructed.
