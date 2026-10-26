# Reliability audit, October 2026

Status record for the architectural, reliability, data-integrity and
performance audit run on 2026-10-24 against `main` at `42e43e4`
(schema 7, `0.2.0-dev.2c`). Updated 2026-10-26.

This document covers **defects and performance**. Permanent history
retention is a separate design, `docs/design/permanent-history.md` (PR #8),
and its work is tracked there, not here.

## Status terms

| Term | Meaning |
|---|---|
| **Fixed – in PR** | Reproduced by a regression test that failed before the fix and passes after, committed on its own branch, PR open, **not merged, not validated in-game** |
| **Measured – in PR** | Performance issue reproduced by a benchmark and improved by a committed change; PR open, not merged |
| **Confirmed – not fixed** | Established by reading the code or by measurement, but no fix committed |
| **Plausible** | A real code path exists, but no reproduction shows it causes harm in practice |
| **Speculative** | Needs unusual or corrupt input; recorded for completeness |
| **Sound** | Reviewed and no defect found |

Regression baseline before any fix: `lua tests/RunAll.lua` on Lua 5.1.5,
20 of 20 test files passing. Every branch below passes the full suite.

## Fixed – in PR

| ID | PR | Finding | Severity | Evidence |
|---|---|---|---|---|
| A1 | [#3](https://github.com/Bromeego/WarbandFYI/pull/3) | After a break of about three months or more, the last month played was never rolled up, and retention then deleted its rows, so the month became empty. | High (data loss) | New `tests/MonthHistoryGapTest.lua`: 6 checks failed before the fix. |
| A2 | [#4](https://github.com/Bromeego/WarbandFYI/pull/4) | A second transfer of the same amount between the same two characters was never recorded, and the receiving side could be lost when the sending side was recorded live. | Medium (transfer history; earned/spent unaffected) | 3 new checks in `tests/WarbandCurrencyTest.lua` failed before the fix. |
| A3 | [#5](https://github.com/Bromeego/WarbandFYI/pull/5) | The warband total on a tracked Notebook item line stayed at the last scanned amount after spending items, until the tracker rescanned. | Low (display) | 2 new checks in `tests/NotebookSmartTest.lua` failed before the fix. |

Notes:

- A1 and permanent history: PR #3 is still needed under the permanent-history
  design; it is scheduled there for stage 2a. It does not change retention or
  caps.
- A2: the same time bound was applied to account-data reconciliation
  (`ApplyAuthoritative`), which has no test harness. That part is
  **untested** and called out in the PR.

## Measured – in PR

| ID | PR | Finding | Before → after (desktop Lua 5.1, benchmark) |
|---|---|---|---|
| P1 | [#6](https://github.com/Bromeego/WarbandFYI/pull/6) | Every Notebook read re-checked the whole notebook, quadratic in its size. | 20 pages / 300 blocks: page list 1.6 s → 0.4 ms; `GetBlock` 9.5 ms → under 0.01 ms; building an 80-page notebook did not finish in 2 minutes before. |
| P2 | [#7](https://github.com/Bromeego/WarbandFYI/pull/7) | Dashboard currency tiles scanned and sorted the full event log once per resource. | 80 resources, 8,000 events: week view ~100–300 ms → ~26 ms; repeated month view ~200 ms → ~53 ms. |

Neither adds a regression test of its own (output is unchanged); both pass
the full suite.

## Confirmed – not fixed

| ID | Finding | Severity | Evidence | Where it is handled |
|---|---|---|---|---|
| B1 | Warband-bank gold is not tracked, so a deposit counts as spending on one character and a withdrawal as earning on another. Period Net Gold is wrong whenever the two fall in different periods. | Medium (accuracy) | No use of the Warband bank money APIs anywhere in the code. | Needs its own design (track the bank balance and pair deposits with withdrawals as transfers). Not started. |
| B2 | `MigrateWarband` deletes events it judges by heuristic to be copies of a shared balance, without folding them into lifetime totals. | Medium (data loss, once per currency) | Code reading (`Tracking/Resources.lua`); not reproduced by a test. | Permanent history, stage 2a (quarantine). |
| B3 | `WarbandFYI_Backup` is replaced by the next schema upgrade, losing the older safety copy. | Medium (backup loss, on upgrade) | Code reading (`ApplyMigrations`); reproduced by the stage 1 tests. | Permanent history, stage 1. |
| B4 | Load-time normalisers silently delete orphaned Notebook sections and blocks, FYI triggers whose event left the catalog, empty-titled FYIs, and FYI completion history beyond fixed counts. | Medium (user content) | Code reading; full list in the permanent-history design, section 2. | Permanent history, stage 2a. |
| B5 | Stock Lua 5.1 cannot load a chunk with more than 262,143 constants. Without the current caps, a typical history would stop loading after about 3 years. | High if the caps were removed; none today | Desktop measurement; **not yet confirmed in WoW**. | Permanent history; the caps stay. |
| B6 | Rolling up many unfinished months at once is slow: 120 months took 104 s on desktop Lua. | Low today (retention limits this to a few months) | Benchmark. | Permanent history, stage 5. |

## Plausible

| ID | Finding | Why not higher |
|---|---|---|
| C1 | Lifetime "gained" and "spent" for a resource can be inflated when a dip-and-return pair of events is pruned: the display hides such pairs, but retention folds both halves. | `RepairHistory` already removed existing pairs once, and the pending/confirm logic prevents most new ones. Net is unaffected. |
| C2 | A holiday checklist is unticked whenever the event's occurrence key changes, so a key that drifts would clear progress. | Keys are snapped to a 15-minute grid since the October hardening; no drift observed. A guard (only reset when the new occurrence starts more than a day later) is a cheap option. |

## Speculative

| ID | Finding |
|---|---|
| D1 | A corrupt, very early timestamp (for example 0) would make month finalisation stop after 360 months, before reaching recent months. |
| D2 | A session left without `endedAt` and no longer active is never expired, and its open segment keeps counting play time. No code path that creates one was found. |
| D3 | Event start and end use the server clock while "now" uses the PC clock, so a PC clock several minutes off shifts when event FYIs appear and disappear. |

## Performance opportunities not yet taken

- The Warband (all-time) view still takes about 170 ms to build with a full
  event log, spread over play time, snapshots and world activity. Not
  profiled further.
- `Sessions.Find` scans all sessions from the start on every call; scanning
  from the end would find the active session at once.
- Per-day totals and time indexes (permanent history, stage 5).

## Reviewed and sound

- Character identity: adopting legacy name-and-realm records and moving
  their history, lifetime totals and gold to the GUID.
- Gold: per-session baselines, between-session deltas, ignoring the 0-gold
  reading when entering the world.
- Event dispatch: one listener's error does not stop the others.
- UI: hidden windows skip refreshes; refreshes in combat are deferred.
- Event FYI occurrence keys: stable across reloads since the October fix.
- Pets: caged or released pets show as "Pet unavailable" instead of failing;
  the Rematch integration is read-only and wrapped in `pcall`.
- Sessions: resume within the timeout, close at the last activity.

## In-game validation still needed

Nothing in this document has been validated in WoW. Per PR:

- **#3**: hard to reproduce live; test on a **copy** of SavedVariables with
  every timestamp shifted back about 100 days, then check Month history.
- **#4**: transfer the same amount of a currency between the same two
  characters on two different days; both transfers should appear.
- **#5**: spend or bank a tracked item referenced in the Notebook; the Total
  should update straight away.
- **#6**: switch pages in a large Notebook while pet journal updates fire.
- **#7**: keep the dashboard open while currencies change; no hitches.
