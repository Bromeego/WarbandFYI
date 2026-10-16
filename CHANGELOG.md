# Changelog

Notable changes to WarbandFYI are recorded here. Work that has not been published as a versioned release stays under Unreleased.

## Unreleased

### Added

- Optional, read-only **Queued in Rematch** status on Notebook pets, Sheet and FYI. Hidden when Rematch is unavailable or the exact pet is not queued; no extra notifications or queue management.

- Individual-pet Notebook level lists with saved GUIDs, live level-25 completion, a paged picker, floating Sheet support and FYI progress. Older species entries remain available for choosing a specific copy.

- A concise addon README and a separate guide covering usage, tracking behaviour, saved data and development checks.
- This changelog to track notable changes alongside the Git commit history.
- Regression tests for pet session progression and existing pet/profession aggregation behaviour.

### Fixed

- Recent Pet Activity now shows known pet levelling progression within a session, so a pet trained from 1 to 25 can show that full span instead of only the last battle's 24 -> 25. Individual events and their original gains are preserved.
- Session progression respects starting levels, unique pet IDs and session boundaries, and falls back safely when history is missing.
- An unavailable starting level no longer produces an assumed one-level gain.

### Removed

- The outdated `COLLECTION-HUNTS-1K-NOTES.txt` and `COLLECTION-HUNTS-README.txt` development notes.

## Repository baseline — 2026-10-16

- Imported the installed Retail addon into this repository, with addon version `0.2.0-dev.2c`.
- Preserved the repository's MIT licence.

This marks the start of the repository history, not a new addon release. Changes from before the import have not been reconstructed.
