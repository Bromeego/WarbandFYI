# Permanent history retention

Status: **design under review** (PR #8). Only stage 1 is being implemented
(section 14, its own PR). Defect fixes from the October audit are tracked
separately in `docs/audit/2026-10-reliability-audit.md`.

- Revision 2, 2026-10-24: records the section 15 decisions, adds
  read-and-validate before any data moves, separates in-memory atomicity
  from on-disk durability, sizes migration backup chains, and adds a
  constant budget with early warnings.
- Revision 3, 2026-10-26: spells out what the load-failure guard can and
  cannot observe, including missing and unreadable files (4.3); marks the
  budget thresholds provisional until confirmed in WoW (7.3); replaces the
  two-week validation period with observed month boundaries, prunes, cap
  trims and reloads (9.2); adds probe test 7.

Applies to schema 7 (`0.2.0-dev.2c`).

## Principle

Recorded gameplay history must never be silently or irreversibly deleted.
WarbandFYI is a permanent record of the warband, whether the player is away
for three months or ten years. Priorities, in order: preservation, accuracy,
performance. Monthly rollups and lifetime totals supplement the original
records; they never replace them.

## 1. Why the current limits cannot simply be removed

Today the addon keeps a bounded working set: 120 days of retention, at most
8,000 events and 4,000 snapshots. Everything older is deleted, with only
lifetime totals and monthly rollups kept.

Those same limits keep the save file loadable. Lua 5.1 refuses to compile a
chunk with more than 2^18 − 1 = **262,143 constants**, and a SavedVariables
file is one chunk. Each distinct number and string in the file (values and
table keys) is a constant.

Measured with stock Lua 5.1.5 on a desktop (not yet in WoW, see section 13):

| Unique numbers in one file | Result |
|---|---|
| 262,000 | loads |
| 263,000 | `constant table overflow` |
| 600,000 rows as 120 encoded strings | loads; decoding one 5,000-row string takes 4 ms |

Simulated histories with retention and caps turned off, stored the way the
addon stores data today:

| Profile | Events | File | Loads? |
|---|---|---|---|
| light, 1 year | 5,280 | 2.7 MB | yes |
| light, 10 years | 46,800 | 24 MB | yes |
| typical, 1 year | 30,160 | 15.5 MB | yes |
| typical, 3 years | 81,510 | 42 MB | **no** |
| typical, 5 / 10 years | 139k / 281k | 72 / 145 MB | **no** |
| heavy, 1 year | 114,800 | 58 MB | **no** |

Today's working set, with retention and caps applied, after a year of play:

| Profile | Working set | File | Constants |
|---|---|---|---|
| light | 1,640 events, 492 snapshots, 41 sessions | 0.8 MB | 8,848 (3%) |
| typical | 7,000 events, 3,120 snapshots, 118 sessions | 3.9 MB | 36,586 (14%) |
| heavy | 7,000 events, 3,200 snapshots, 216 sessions | 5.2 MB | 47,815 (18%) |

Constants were counted as distinct numbers and strings in the written file,
which matches how Lua 5.1 assigns them in a single chunk.

If WoW's loader shares this limit, a file that fails to load leaves the addon
with no data, and the next logout writes that state over the file
(section 4.3). Removing the caps without another storage format would risk
losing **all** history at once. This design keeps the working set bounded
until an archive is proven.

Profiles used throughout (rates per active day):

| Profile | Active days/yr | Sessions/day | Events | Snapshots | Gold ledger lines | Gathering rows |
|---|---|---|---|---|---|---|
| light | 120 | 1.0 | 40 | 12 | 10 | 3 |
| typical | 220 | 1.6 | 130 | 40 | 35 | 12 |
| heavy | 330 | 2.0 | 350 | 100 | 80 | 40 |

The event mix follows what `Tracking/*.lua` records (about 42% resource
changes, 22% quests, 8% pet battles, and so on). Real data will differ; the
profiles compare designs, not predict exact sizes.

## 2. Every path that deletes or discards recorded data

Classification:

- **H** – permanent gameplay history.
- **U** – user-authored content or configuration.
- **C** – disposable cache or duplicate guard.
- **S** – current-state baseline (needed, but describes the present, not history).

| # | Path | Class | What it removes | Treatment (stage) |
|---|---|---|---|---|
| 1 | `Database.Prune` – 120-day retention, at every login and new session (`Core/Database.lua`, `Core/Sessions.lua`) | H | Events, snapshots and whole sessions (segments, gold ledger, gathering rows), folded into lifetime totals | Copy to archive first (3b); move instead of delete (3c) |
| 2 | Event cap 8,000 → 7,000 (`Core/Events.lua`) | H | Oldest events, folded into lifetime | Same as row 1 |
| 3 | Snapshot cap 4,000 → 3,200 (`Database.AddSnapshot`) | H | Oldest snapshots; only the earliest level and item level survive | Same as row 1 |
| 4 | `MigrateWarband` (`Tracking/Resources.lua`), once per currency when it becomes warband-wide | H | Events judged by heuristic to be per-character copies of a shared balance, **not** folded into lifetime | Quarantine (2a) |
| 5 | `RepairHistory` (`Tracking/Resources.lua`), once per ledger version | H | Transient dip-and-return pairs, merged sync rows | Quarantine (2a) |
| 6 | `/wbfyi resetresource` | H (user-initiated) | Every event for one resource | Quarantine the removed rows (2a) |
| 7 | FYI `PruneOccurrences` (12 per FYI) and `PruneHistory` (48 rows, 6 per event) (`Core/ContextFyi.lua`) | H | Which occurrences of a recurring reminder were completed | Stop pruning; tens of rows a year (2a) |
| 8 | World activity `MAX_ROWS` 2,500 per session | H (precision) | Not deleted: later gathering merges into an existing row and loses its own time | Keep; revisit in stage 6 |
| 9 | `EnsureNotebook`, every load | U | Sections whose page is missing, blocks whose section is missing | Quarantine (2a) |
| 10 | `NotebookFyi.Ensure`, every load | U | Triggers whose event is not in the current catalog, whose target is gone, or duplicate targets | Quarantine (2a) |
| 11 | `ContextFyi.Ensure` / `Normalize`, every load | U | FYIs with an empty title; item text re-clipped and items beyond 12 dropped | Quarantine; clip only on write (2a) |
| 12 | `EnsureContextFyis`, `EnsureNotebook` | U | Rows that are not tables (corrupt values) | Quarantine the raw value (2a) |
| 13 | Migration 4 | U | `db.plans` deleted without a copy when `notebookLegacy` already exists (only after a downgrade) | Copy into `notebookLegacy.extraPlans` (2a) |
| 14 | `ApplyMigrations` backup | U | The previous `WarbandFYI_Backup` is replaced by the next schema upgrade | Never overwrite (1) |
| 15 | Collection Hunts `Remove` (user action) | U | The hunt's completion record | Keep the completion when hiding (2a) |
| 16 | `ClearSample` (user command) | — | Rows marked `sample = true` only | Unchanged; sample rows are not history |
| 17 | `Crafts.ClearSimulated` (debug command) | — | Events marked `meta.simulated` only | Unchanged |
| 18 | Notebook and FYI deletes (user action) | U | The deleted item | Out of scope; possible trash/undo later |
| 19 | Transient `dedupe` keys expire with retention | C | Duplicate guards | Keep expiring, on their own 120-day TTL instead of the retention setting (3c) |
| 20 | `transferSeen` (90 days), `recentClaims`, `pendingObserve`, world-activity sources and seen rares, FYI notice "seen", zone visits, holiday icon cache, recipe cache, Housing XP and Prey runtime lists, `currentInstance` | C | Caches | Unchanged |
| 21 | Renown root rebuild, resource `acceptedBalance`/`observed`, `goldLast` | S | Malformed current-state rows | Unchanged; these are not history |

## 3. Permanent history vs disposable caches

**Permanent** (never deleted automatically; archived or quarantined instead):

- `events`, `snapshots`, `sessions` (segments, `goldByCharacter`, `goldLedger`, `world.rows`)
- `monthHistory` rollups and `lifetime` totals (supplementary, but they are
  the only remaining record of history deleted before this design)
- `characters`
- `notebook` (pages, sections, blocks, quick notes, FYI triggers), `contextFyis`
  including `completedOccurrences` and `fyiHistory`, `notebookLegacy`
- `housing.collected`, Collection Hunts completions, resource `lifetime` blocks
- `WarbandFYI_Backup` and its chain
- the new `archive`, `recovery` and `trackingGaps` stores

**Disposable** (may be rebuilt or expire without loss of history): rows 19–21
above, every in-memory table, summary caches and decoded archive blocks.

A field is permanent unless it can be rebuilt from permanent data or from
the game client. Every PR that adds stored data must say which kind it is.

## 4. Physical storage, atomicity and durability

### 4.1 Files

Documented behaviour ([warcraft.wiki.gg: SavedVariables](https://warcraft.wiki.gg/wiki/SavedVariables)):

- All `## SavedVariables` of one addon are written to **one file**,
  `WTF/Account/<ACCOUNT>/SavedVariables/<AddonName>.lua`.
- `## SavedVariablesPerCharacter` go to a **different file per character**,
  `WTF/Account/<ACCOUNT>/<Realm>/<Character>/SavedVariables/<AddonName>.lua`.
- A second account-wide variable such as `WarbandFYI_Archive` therefore
  shares a file with `WarbandFYI_DB` and `WarbandFYI_Backup`. It gives no
  file-level isolation: one parse error or one oversized constant table fails
  all of them.
- WoW keeps one previous copy as `<AddonName>.lua.bak`, replaced at every
  save. It is not a long-term backup.

Unverified, to be tested with the probe (section 13):

- whether WoW's loader has the same 262,143-constant limit;
- whether an installed but unloaded addon keeps its file untouched;
- what WoW writes to the file and to `.bak` when a variable failed to load
  and the addon leaves it `nil` or replaces it;
- how long WoW takes to write and read files of 25, 50 and 100 MB.

### 4.2 Atomic in memory is not durable on disk

Two different guarantees, which this design keeps separate:

- **Atomic state change (in memory).** WoW runs each addon call to
  completion before anything else runs, and SavedVariables are serialised
  from the in-memory tables only at logout, `/reload` or disconnect. A change
  made inside one function call is therefore either entirely in the next
  saved snapshot or entirely absent. The archive commit (6.1) relies on this,
  so a save can never hold a half-moved block.
- **Durability (on disk).** Nothing is on disk until the next save. A crash
  or forced quit loses every change since the last save; the file on disk
  stays as it was. A save itself is an ordinary file write: if power is lost,
  the disk fills or the client dies while writing, the file can be truncated
  and fail to load. Atomic commits do not protect against that; a bigger file
  takes longer to write and is exposed for longer.

What protects against loss of the file itself:

- external dated backups (section 12), the only protection that survives a
  bad file plus a further save;
- WoW's `.bak`, only until the next save;
- the load-failure guard (4.3), which stops a failed load from being saved
  over the last good data without a warning.

### 4.3 Load-failure guard (stage 2c)

#### Problem

If `WarbandFYI.lua` is missing or fails to load, the addon sees
`WarbandFYI_DB == nil`. Today `Database.Init` then creates a fresh empty
database, and the next logout writes it to the file.

#### What the addon can and cannot observe

The addon cannot read files. It only sees which globals exist after WoW has
run each SavedVariables file. From inside the addon, these situations look
like this:

| On disk | What the addon sees |
|---|---|
| File missing: first install, file deleted or moved, WTF folder reset | `WarbandFYI_DB == nil` |
| File fails to compile: syntax error, truncation mid-statement, constant overflow | `WarbandFYI_DB == nil` (a chunk that fails to compile defines nothing) |
| File truncated exactly between two top-level assignments | Some variables present, later ones `nil`. WoW writes `WarbandFYI_DB` before `WarbandFYI_Backup` in practice, but the order is not documented. |
| File holds an older save (restored external copy, or WoW fell back to `.bak`) | `WarbandFYI_DB` present but older |
| `WarbandFYI_DB` is not a table | A non-table value (`Init` replaces it today) |

So "missing" and "unreadable" cannot be told apart from inside the addon,
and neither can be told apart from a genuine first install without another
signal.

**Assumptions that must be checked with the probe (section 13, tests 2, 3
and 7)**, because the guard depends on them:

1. A failed account-wide file does not affect the per-character file, and
   vice versa.
2. A file that fails to load leaves its globals `nil` rather than partly set.
3. What WoW writes on logout after a failed load, to both the file and
   `.bak`, when the addon leaves the variable `nil` and when it replaces it.
4. Whether WoW ever falls back to `.bak` on its own.

Until those are confirmed, the guard only warns and pauses writes it
controls; it does not promise that the file on disk is safe.

#### Signal: a per-character sentinel

`WarbandFYI_Sentinel` (`## SavedVariablesPerCharacter`, a separate physical
file per character) is written at every logout with:

- `saveSerial`: a counter also stored in `WarbandFYI_DB.saveSerial`, raised
  by one at every logout;
- schema, addon version, save time;
- counts of events, snapshots, sessions, Notebook pages and archive blocks.

Both files are written by the same logout, so after a clean save they agree.

#### Decisions at login

| `WarbandFYI_DB` | Sentinel | Meaning | Action |
|---|---|---|---|
| table, `saveSerial` equal | present | Normal | Normal |
| table, `saveSerial` higher | present | Another character saved since; normal | Normal |
| table, `saveSerial` lower | present | Older file: a restore or a `.bak` fallback | Load normally; one clear notice naming the save time the sentinel expected and the one found. A restore is often intentional, so this never blocks. |
| `nil` or not a table | present with data | **Missing or unreadable file** | Guard (below) |
| `nil` | absent | First install, or a character that never played with this version | Create defaults, as today |
| `nil` | present but empty (counts all zero) | Nothing was ever recorded | Create defaults |
| table | absent or unreadable | Sentinel lost; data fine | Normal; rebuild the sentinel at logout |

#### Guard

- Do not create defaults and do not record anything. The addon stays in
  read-only mode with no data.
- Show a blocking dialog and a chat message, worded around what is known:
  "WarbandFYI could not load its saved data, which existed at your last
  logout (save N, date). Do not log out yet. Copy the whole `WTF` folder
  somewhere safe now, then close the game and restore `WarbandFYI.lua` from
  your latest backup or from `WarbandFYI.lua.bak`." The final wording follows
  the probe results.
- `/wbfyi startfresh` lets the player confirm that an empty start is
  intended (for example a deliberately deleted file). It asks for
  confirmation and records the decision, with its time, in the new database.
- The guard never deletes, renames or edits the sentinel. It is only
  replaced at the next normal logout.

#### Limits

- A character with no sentinel (new, or not played since this version)
  cannot detect a failed load. Logging in on such a character first would
  create defaults as today. Maintenance and the guide say so, and the
  external backup routine (section 12) is the protection.
- If the per-character file is also lost (for example the whole `WTF` folder
  was reset), the situation is indistinguishable from a first install.
- The guard cannot make WoW keep the old file. Its job is to stop the addon
  making things worse and to tell the player to copy the files while they
  still can.

## 5. Archive format

### 5.1 Layout

```lua
WarbandFYI_DB.archive = {
    format = 1,                      -- archive layout version
    blocks = {                       -- keyed deterministically
        ["events:2026-09:000001"] = {
            kind = "events",         -- events | snapshots | sessions | recovery
            month = "2026-09",       -- local calendar month of the rows' time field
            seq = 1,                 -- block number within kind+month
            codec = 1,               -- encoding version
            mode = "copy",           -- "copy" (rows still live, stage 3b) or "moved" (stage 3c)
            rows = 1000,             -- row count
            bytes = 412337,          -- length of data
            checksum = 3141592653,   -- Adler-32 of data
            firstAt = ..., lastAt = ...,
            firstId = ..., lastId = ..., -- events and sessions
            idSum = ...,             -- sum of ids, a cheap second check
            folded = false,          -- true once rows were folded into lifetime
            createdAt = ...,
            addonVersion = "...",
            data = "return{...}",    -- the rows, encoded
        },
    },
    state = {                        -- progress and errors, never row data
        lastError = nil,             -- { at, stage, key, message }
        lastVerifiedAt = nil,
    },
}
WarbandFYI_DB.archiveCommitted = 0   -- outside the archive table; raised by every commit
```

### 5.2 Encoding rules (codec 1)

- A block is a Lua table constructor of the rows, exactly as stored. Every
  field, id, timestamp, GUID and `meta` entry is kept. Nothing is renamed,
  rounded or summarised.
- **Deterministic**: table keys in a fixed order (by type, then value).
  Integers with `%d`, other numbers with `%.17g`, strings with `%q`. The same
  rows always give the same bytes. Measured: byte-identical on re-encode of
  500, 3,000 and 10,000 rows.
- Only strings, numbers, booleans and tables. A function, userdata, NaN,
  infinity or a cycle fails the encode (section 7).
- Rows keep their original order. At most 1,000 rows per block, so one block
  decodes in about 12 ms on desktop Lua.
- Decoding uses `loadstring` in an empty environment (`setfenv(chunk, {})`),
  so a block cannot read or change any global.
- Each block is one string constant, so the archive adds about 16 constants
  per block (its metadata) to the file, whatever its size.

### 5.3 Verification

A block is valid only if all of these hold:

1. `#data == bytes` and Adler-32 of `data == checksum`.
2. `data` compiles and returns a table of exactly `rows` entries.
3. `firstAt`, `lastAt`, `firstId`, `lastId` and `idSum` match the decoded rows.
4. When written, and for every copy-mode block on each verification pass:
   the decoded rows are deeply equal to the live rows they copy, and
   re-encoding them gives identical bytes.

Measured on desktop Lua: a single changed byte is caught by the checksum, and
a truncated block fails to compile. Adler-32 detects accidental corruption,
which is its only job; the row and id checks back it up.

### 5.4 Versioning

- `archive.format` versions the container; `block.codec` versions each block.
- A newer addon reads every older codec forever. Existing blocks are never
  re-encoded automatically.
- Compression (stage 6, LibDeflate) is a new codec number. A compressed
  block is only kept after it decompresses to bytes identical to the
  uncompressed codec-1 encoding of the same rows; the codec-1 form is the
  reference for every integrity check.
- An older addon that meets an unknown `archive` table leaves it alone:
  `Database.Init` keeps unknown top-level keys (checked in schema 7 code).

## 6. Archiving protocol

### 6.1 Copy, then move

- **Copy mode (stage 3b).** Blocks are written as copies of rows that stay in
  the working set. Retention and caps still delete exactly as today, but rows
  about to be deleted are copied into a block first. If that copy fails, the
  rows are deleted as today (no worse than now) and the error is recorded.
- **Move mode (stage 3c).** Retention and caps remove a row from the working
  set only by committing it to a verified block. If the block cannot be
  written, the row stays.

Both modes use the same steps:

1. **Select.** Rows grouped by kind and month, up to 1,000 per block.
2. **Prepare (sliced).** Encode a few rows per frame into an in-memory
   buffer, about 4 ms per frame. Nothing is written into `WarbandFYI_DB`.
   A logout or reload just loses the buffer.
3. **Verify (sliced).** Section 5.3, including deep comparison.
4. **Commit (one call).** In a single synchronous function: refuse an
   existing key; add the block; raise `archiveCommitted`. In move mode also:
   fold the rows into lifetime totals exactly as `Prune` does today, set
   `folded = true`, remove exactly those rows (matched by identity) from the
   working set, and update the archived-through markers.

Measured per row on desktop Lua: encode 0.04–0.05 ms, checksum 0.018 ms,
decode 0.012 ms, deep verify 0.006–0.013 ms; about 0.08 ms in total. At
4 ms per frame that is about 50 rows a frame: a 1,000-row block takes about
20 frames, a third of a second at 60 fps.

### 6.2 Idempotence and interruption

- Block keys are deterministic and a commit refuses an existing key.
- A copy-mode block whose rows later move (stage 3c) is not written twice:
  the move switches `mode` to `"moved"` and folds, after re-verifying the
  block against the live rows in the same call.
- If the working set holds rows that a moved block also holds (impossible
  by 6.1, but a downgrade or manual edit could cause it), the loader compares
  them. Equal rows are dropped from the working set **without** folding
  again; different rows are both kept and the conflict is quarantined.
- Re-running after a reload starts from step 1 with the same rows and
  produces the same bytes.

| Interrupted at | Saved state | Next login |
|---|---|---|
| select / prepare / verify | Unchanged | Starts again |
| between commits | Some blocks committed, rest still live | Continues |
| crash or forced quit | The last saved file | Same as above |
| a save that does not complete | Possibly unreadable file | Load-failure guard (4.3); restore (12) |
| downgrade to an older version | `archive` left untouched; old code prunes as before | Upgrading again finds the archive intact |

### 6.3 Lifetime totals are folded exactly once

- Rows are folded into `lifetime` only in a move-mode commit (or, until 3c,
  by today's `Prune`). Copy-mode blocks are never folded.
- `block.folded = true` records that its rows are already in lifetime.
  Warband totals keep today's formula, live rows + `lifetime`, and never
  decode blocks.
- Period queries (8) use rows, live and archived, and never `lifetime`.
- Rows pruned during stage 3b were folded by `Prune` and also exist in a
  copy-mode block with `folded = false`. Such blocks are marked
  `prunedCopy = true` at commit time, so they are never folded later and are
  never counted alongside lifetime in warband totals.

## 7. Failure handling, constant budget and the safety brake

### 7.1 Principle

Any encode, decode, verify or commit failure leaves the original rows where
they are, records the error and tells the player. Nothing is reset,
regenerated or discarded because of a failure.

### 7.2 Failure cases

| Failure | Response |
|---|---|
| Encode fails (unsupported value) | Rows stay live. `archive.state.lastError` records the row id and field. One chat line per session; a Maintenance line until resolved. |
| Verify fails | Buffer discarded; rows stay live; same reporting. |
| Stored block fails to decode or validate when read | Block kept untouched and marked `damaged`; its months show "archived data unavailable" rather than empty. Maintenance explains how to restore from an external backup. |
| `archive` missing or not a table while `archiveCommitted > 0` | Never create an empty archive over it. Archiving stops, the working set stays as is, and the player is told to restore from backup. |
| Duplicate between live rows and a moved block | Section 6.2. |
| Main file failed to load | Load-failure guard (4.3). |

### 7.3 Constant budget

The addon estimates its file's constant count by counting distinct strings
and numbers (values and keys) across `WarbandFYI_DB` and `WarbandFYI_Backup`,
which share the file. Copy-mode and moved blocks count as one string each
plus their metadata. The count runs once per session, a slice per frame,
and is shown in Maintenance with the file-size estimate.

The ceiling is 262,143 until the probe confirms WoW's real limit; if WoW
allows more, the ceiling stays at 262,143 unless a later reviewed PR changes
it.

**The thresholds below are provisional.** They come from desktop Lua
measurements, and none of the numbers behind them (the limit, the meter's
accuracy, load and save times) has been confirmed in WoW.

| Level | Provisional budget | Behaviour |
|---|---|---|
| Normal | below 35% | Maintenance shows the figure, marked "estimate" |
| Notice | 35% | Maintenance highlights it; one chat line per week |
| Warning | 45% | A chat line at every login with what to do (back up, export); archiving given priority once it exists |
| Brake | 55% | Degraded mode (7.4) |
| Read-only | 70% | All recording paused (7.4) |

While provisional:

- The values live in one table in the code, each marked provisional, and
  Maintenance labels them "provisional – not yet confirmed in WoW".
- Notices and warnings are always active, since they cost nothing.
- Degraded and read-only modes are active too, because they are the only
  protection if the file approaches a load failure. Because the caps remain
  until stage 3c, they can only be reached by backups accumulating or by
  repeated archive failures.

They become final in a separate reviewed PR, only when all of these hold:

1. The probe (section 13, test 1) has measured WoW's limit.
2. The meter's estimate has been compared with the offline counter
   (section 12) on real saved files, at least three of them at different
   sizes, and stays within 5% of it, always on the high side.
3. WoW load and save times are measured for files at each threshold
   (probe test 5).

Hysteresis: tracking resumes only when usage falls 5 points below the level
that stopped it. Today's measured working sets use 3–18%, so normal play
stays well below the Notice level. What could raise it is accumulated
backups (section 10) or archiving that keeps failing, and both trigger
warnings long before the brake.

### 7.4 Degraded and read-only modes

Decision 1: a clearly warned degraded mode, never a silent omission and never
a complete shutdown.

- **Degraded (Brake).** High-volume recording stops: resource balance
  changes, snapshots, gathering rows. Low-volume history continues (quests,
  achievements, collections, level-ups). All existing data stays viewable and
  exportable.
- **Read-only.** All new recording pauses. Viewing and export continue.
- Every stop and resume is written to `WarbandFYI_DB.trackingGaps` as
  `{ startedAt, endedAt, channels, level, reason, budget }`. Gaps are shown
  as such in the dashboard and in exports, so a missing period is always
  explained, never silent.
- A warning shows in the main window header and in chat at every login
  while a gap is open.
- Nothing already recorded is ever deleted to get out of either mode. The
  way out is fixing the cause (for example archiving succeeding again).

## 8. Queries over live and archived rows

### 8.1 Ownership

In move mode every row lives in exactly one place: the working set or one
moved block. Copy-mode blocks duplicate live rows by design, so queries read
copy-mode blocks only in validation (8.3), never for results.

### 8.2 Reading a period

```
rows(kind, startAt, endAt):
    months = calendar months overlapping [startAt, endAt]
    for each month: decode each valid moved block of that kind and month (cached), filter by time
    plus live rows filtered by time
    de-duplicate: events and sessions by id; snapshots by (guid, at, reason, level, itemLevel, money)
```

- De-duplication is defence in depth; 8.1 already guarantees it.
- A small cache of decoded blocks (for example 8), dropped when the window
  closes.
- Months before `db.prunedThrough` (PR #3) lost rows before this design.
  Their monthly rollup stays the authority, and the UI says detail is
  incomplete for them.

### 8.3 Read and validate before anything moves

Stage 3b ships the read path, not just the writer. Before stage 3c:

- On each login, every block is verified (5.3, steps 1–3), sliced across
  frames.
- For copy-mode blocks of rows still live, the query in 8.2 is run with the
  block in place of the live rows, and the result is compared with the live
  result: same rows, same order, same summary totals.
- `/wbfyi archive verify` runs the full check on demand and prints a report;
  Maintenance shows the last result.
- The offline verify tool (section 12) checks a copied file outside WoW.

### 8.4 Making period queries cheap (stage 5)

- **Per-day totals** kept up to date as events are recorded, so Today, Week
  and Month read tens of numbers instead of scanning rows.
- **Monthly rollups** become rebuildable caches, built in the background a
  few milliseconds per frame. This replaces the measured 104 s to roll up 120
  light-profile months at once on first load.
- **Time index**: the working set is append-mostly, so a binary search on
  time finds a period's first row.
- Activity lists and charts decode only the blocks for the months shown.

## 9. Migration sequence

Each stage is one or more focused PRs, reviewed and tested in-game before the
next starts. Nothing is merged, tagged or released automatically, and no
stage bumps the schema until 2b's budget meter is in place.

### 9.1 Stages

| Stage | Change | Caps and retention | Deletion stops for |
|---|---|---|---|
| 0 | Today | Delete | — |
| 1 | Keep every pre-migration backup (first PR, section 14) | Unchanged | Backups (row 14) |
| 2a | Quarantine instead of delete for migrations, repairs and normalisers; Maintenance recovery view and read-only export; land PR #3 | Unchanged | Rows 4–7, 9–13, 15 |
| 2b | Constant budget meter, early warnings, degraded and read-only modes, tracking-gap log | Unchanged | — |
| 2c | Load-failure guard (4.3) | Unchanged | — |
| 3a | Codec, verification, offline verify tool; tests only, not called in-game | Unchanged | — |
| 3b | Copy-mode archiving and the full read path (8.3); rows about to be pruned are copied first | Delete as today, after copying | Effectively rows 1–3, best effort (a failed copy still deletes) |
| 3c | **Move mode**: rows leave the working set only by verified commit | Bound the working set only | **Rows 1–3: all automatic deletion ends** |
| 4 | Month, gold, resource, pet and character views read archived months | Unchanged | — |
| 5 | Per-day totals, rollup backfill, time index | Unchanged | — |
| 6 | Optional LibDeflate codec after uncompressed blocks are validated in-game; larger working set if the probe allows | May be raised (9.4) | — |
| deferred | Separate archive addon: only if the probe confirms isolation and benchmarks justify a second install folder | — | — |

The probe (section 13) runs alongside stage 1 and must finish before 3c.

### 9.2 When the 120-day retention stops deleting

**At stage 3c, and not before.** All of these must hold:

1. Stage 3a's tests pass: round trip and determinism over every value type
   the addon stores; corruption, truncation and missing-block tests;
   interruption and repeated-run tests (section 11).
2. Stage 3b has **observed** each of the events below in-game on your
   account. Elapsed time alone counts for nothing: a save with less than 120
   days of history never prunes, and a light player may never reach a cap.
   The addon records each observation in `archive.state.validation` with its
   time and the blocks involved, and Maintenance shows the checklist; the
   gate is met only when every line is ticked.
   - **Month boundary**: a calendar month closed while 3b was active, its
     copy blocks were written, verified, and their query results matched the
     live rows.
   - **Retention prune**: a login or new session pruned rows by age, every
     pruned row was copied into a verified block first, and the copy
     decoded to exactly the rows that were then deleted.
   - **Event cap trim** and **snapshot cap trim**: each observed the same
     way. If your play does not reach a cap, the gate is met instead by
     `/wbfyi archive exercise cap`, which runs the same selection and copy
     path over the rows a trim would take, without deleting anything (copy
     mode never deletes), and verifies the result.
   - **Reload and relog**: at least one `/reload` and one full logout/login
     with every block re-verified afterwards.
   - **Offline check**: the verify tool (section 12) passed on an external
     copy taken after all of the above.
   - **No failures**: zero verification failures and zero query mismatches
     for the whole period. Any failure resets the checklist once the cause is
     fixed.
3. The probe has run, so WoW's real limits and save behaviour are known.
4. An external backup has been taken and a restore rehearsed on a copy.
5. Stages 2b and 2c are in place: the budget meter, warnings, degraded mode,
   gap log and load-failure guard are tested.

### 9.3 When the count caps stop deleting

Also at 3c: the 8,000-event and 4,000-snapshot caps keep their numbers but
become **archive triggers**. Above a cap, the oldest rows move into verified
blocks instead of being deleted.

### 9.4 When the caps can be raised

Never removed. They can be raised at stage 6 only if the probe shows WoW's
real limit and the budget meter keeps the file under the Notice level (35%)
at the new size in the heavy profile.

Retention as a time window stops meaning "delete after N days" at 3c; it
becomes "keep N days of rows unarchived for fast access". There is no
player-facing retention setting.

### 9.5 Expected file size with the archive

Measured on desktop Lua with the typical profile, working set = current
month, older months as uncompressed blocks:

| Typical history | File | Parse | Memory after load | Decode 1 month | Decode all |
|---|---|---|---|---|---|
| 1 year | 9.8 MB | 0.08 s | 10 MB | 18 ms | 0.2 s |
| 3 years | 26 MB | 0.19 s | 25 MB | 17 ms | 0.6 s |
| 5 years | 44 MB | 0.31 s | 43 MB | 18 ms | 1.1 s |
| 10 years | 89 MB | 0.62 s | 85 MB | 18 ms | 2.2 s |

Writing (logout) the 10-year file took 0.58 s, against 9.7 s for the same
history stored as tables (which then failed to load). The real working set
will be 120 days rather than one month, adding about 4 MB (section 1).
Deflate shrank the synthetic data about 8×; real data will compress less.

## 10. Migration backups vs archive references

### 10.1 What each protects

- **Migration backup** (`WarbandFYI_Backup`): a full copy of the database
  taken just before a schema upgrade. It protects against an upgrade that
  corrupts or mis-converts the working set. It lives in the same file, so it
  does not protect against losing or corrupting that file.
- **Archive reference**: a record of a block's key and checksum, without its
  data. It lets a backup say "this block existed and looked like this", but it
  cannot restore the block. **A reference is not a backup.**
- **External backup** (section 12): a copy of the whole file outside WoW.
  The only protection for archive blocks and for the file itself.

### 10.2 Sizes

Each migration backup copies the working set. With today's caps that is
0.8 MB (light), 3.9 MB (typical) or 5.2 MB (heavy) per backup as tables.
Schema upgrades are rare: one or two a year at most.

| Backups kept (typical) | As tables, file | As tables, constants | As codec-1 strings, file |
|---|---|---|---|
| 1 | +3.9 MB | +0–14% | about +2.5 MB |
| 3 | +12 MB | +0–42% | about +7.5 MB |
| 10 | +39 MB | +0–140% (over the limit) | about +25 MB |

A backup taken at upgrade time shares every constant with the live data
(0%). As the 120-day working set rotates, its values stop being shared, and
after about four months it adds its full share (14% typical, 18% heavy).
A chain of table backups would therefore exhaust the constant budget after
a handful of upgrades. Hence:

- **Stage 1 keeps the chain as tables** (the only lossless option before the
  codec exists). Schema upgrades are not allowed before 2b, and the budget
  meter counts every backup, so a growing chain raises a Notice long before
  it matters.
- **From stage 3a, new backups are stored as codec-1 blocks** (one string
  each), verified by round trip before the upgrade proceeds. If the backup
  cannot be written and verified, the upgrade does not run.
- **Existing table backups are never re-encoded automatically.** Converting
  them to strings is a lossless representation change, but it removes the
  table form, so it is a separate reviewed step that needs your explicit
  approval and keeps the table until the string is verified.
- **After stage 3c, backups exclude moved archive blocks**, which migrations
  never modify, and store references to them instead. The backup then
  protects the working set only. Archive blocks are protected by external
  backups (section 12), and Maintenance says so explicitly.
- No backup is ever deleted automatically, by count or by size.

## 11. Test plan

All tests run with `lua tests/RunAll.lua` (Lua 5.1), with no WoW client.

**Codec**
- Round trip and byte-identical re-encode for generated rows of every stored
  kind: events of each type with real `meta` shapes, snapshots, sessions with
  segments, gold ledger and world rows, recovery rows.
- Strings with quotes, backslashes, newlines, `\0`, high bytes and long text;
  negative numbers, zero, large integers (2^53 − 1), non-integer floats;
  booleans; empty and sparse tables; nested tables.
- Rejection, with no data changed, of functions, userdata, NaN, ±infinity and
  cycles.

**Integrity**
- Single-byte changes in every region of a block; truncated, empty and
  oversized blocks; wrong row count, ids or timestamps; unknown codec;
  missing `archive` table with `archiveCommitted > 0`; a block present twice
  under different keys.

**Lifecycle**
- Interruption after select, part-way through prepare and verify, and
  between commits; reload; identical end state and no double fold.
- Repeated runs commit nothing new.
- Copy-mode to move-mode switch: same block, no second encode, folded once.
- Rows pruned in copy mode: never folded again, never added to warband
  totals.
- Upgrade from schema 7; a save already holding legacy-pruned months (PR #3).
- Downgrade: a stage 3c save opened by schema 7 code keeps `archive`
  untouched; upgrading again resumes cleanly.
- Recovery: corrupt a block, confirm `damaged` handling; restore the file
  from an external copy and confirm every block validates.
- Totals: warband totals before and after archiving are identical; period
  totals for every month are identical whether rows are live or archived.

**Budget and modes**
- Meter accuracy against files whose constant counts are known; thresholds
  and hysteresis; gap records opened and closed exactly once per transition;
  existing data unchanged in degraded and read-only modes.
- Load-failure guard: missing or empty `WarbandFYI_DB` with a sentinel does
  not create defaults; without a sentinel behaves as today.

**Scale**
- The benchmark scripts used for this document move into `tests/bench/`
  (not part of `RunAll`): 1, 3, 5 and 10 years at each profile, reporting
  file size, write time, parse time, memory, decode time, constants, commit
  frame cost and dashboard build times.

## 12. External backup, restore and export

WoW's `.lua.bak` is one rolling copy, replaced at every save. It is not a
long-term backup: a bad session followed by one more logout replaces it.

**Backup procedure** (documented in `docs/GUIDE.md`):

1. Log out of WoW completely, so the file is written and consistent.
2. Copy `WTF/Account/<ACCOUNT>/SavedVariables/WarbandFYI.lua` (and the
   per-character `WarbandFYI.lua` files once the sentinel exists) to a dated
   folder outside the WoW directory, for example `WarbandFYI-backups/2026-10-24/`.
3. Run the offline verify tool on the copy (from stage 3a) and keep its
   report beside it.
4. Keep the recent copies plus one per month, on a second drive or a synced
   folder. Never delete older copies automatically.
5. Take a copy before installing any WarbandFYI update.

**Verify tool** (stage 3a, `tools/verify-archive.lua`, stock Lua 5.1):
reads a copied file, checks every block (5.3), counts constants, and prints
counts per month and kind. It never writes to the file.

**Export tool** (stage 2a for recovery records, stage 4 for history):
`tools/export-history.lua <copied file> <out dir>` writes JSON Lines (one row
per line, every field kept) and CSV summaries per month, plus the recovery
list and tracking gaps. It reads a copy, never the live file. The addon never
removes anything after an export.

**Restore procedure**: close WoW; copy a backup over `WarbandFYI.lua`; run
the verify tool on it; start WoW. A restored file is treated like any save,
and blocks are validated on read.

## 13. Disposable probe addon

A separate addon folder, `WarbandFYI_SVProbe`, kept outside the WarbandFYI
release in `tools/sv-probe/`. Its own TOC, its own variables (`WBFProbe_DB`,
plus `WBFProbeChar_DB` per character), and it never reads or writes any
WarbandFYI variable. Its files are `SavedVariables/WarbandFYI_SVProbe.lua`
and the per-character equivalent.

Tests, each driven by a slash command and a `/reload` or relog:

1. **Constant limit**: write N unique numbers, reload, report whether the
   variable came back. Step N through 200k, 262k, 263k, 300k, 500k, 1M.
2. **Failure scope**: after a failed load, are WarbandFYI's data and the
   probe's per-character file intact?
3. **Write after a failed load**: with the file made unloadable (oversized
   or a deliberate syntax error), log out with the variable left `nil`, and
   separately with it replaced. Record exactly what ends up in the file and
   in `.bak`. This decides the load-failure guard's wording (4.3).
4. **Unloaded addon**: a second probe addon, load-on-demand and never
   loaded, with a marker in its file; after several sessions, is the file
   byte-for-byte unchanged?
5. **Large strings**: save 10, 25, 50 and 100 MB of string data; record
   logout and login times and in-game memory.
6. **Forced exit**: quit with Alt+F4 or end the process after changes; is the
   file unchanged (expected: last save kept)?
7. **Missing, unreadable and partial files** (with WoW closed between
   steps, on the probe's own files only):
   - delete the probe's account file: are its globals `nil`, and is the
     per-character file still loaded?
   - put a syntax error at the end of the file: is any variable defined?
   - cut the file between two top-level assignments: is the first variable
     loaded and the second `nil`?
   - with the main file unreadable and a valid `.bak` beside it: does WoW
     ever load the `.bak` by itself?
   - after each, what do the file and `.bak` contain following a logout?

Precautions: take an external backup of the whole `WTF` folder first. The
probe can slow logout while large data is saved, and a failed load clears
only the probe's own variables. When finished, delete the probe folders and
their SavedVariables files. It is never shipped with WarbandFYI.

## 14. First implementation PR (stage 1): keep every pre-migration backup

### Why first

`ApplyMigrations` replaces `WarbandFYI_Backup` whenever a save is upgraded to
a newer schema than the one the backup targets. Later stages will need
schema 8, and that upgrade would replace the only existing safety copy.

### Change

- `Core/Database.lua` only, plus tests and changelog.
- When a new backup is needed and `WarbandFYI_Backup` already holds one, move
  the existing backup, unchanged, into `WarbandFYI_Backup.previous`, an array
  in creation order, before writing the new top-level fields. Existing fields
  (`createdAt`, `addonVersion`, `fromSchema`, `targetSchema`, `data`) keep
  their names and meaning, so the Maintenance panel and older code still read
  the newest backup.
- Never remove an entry from `previous`. No size- or count-based pruning.
- A `WarbandFYI_Backup` that is not a table is kept as
  `{ unreadable = <value> }` in `previous` instead of being overwritten.
- Maintenance shows how many backups are kept.
- No schema bump, no change to caps, retention or tracked data. Schema 7
  code has no pending upgrade, so on existing saves this PR changes nothing
  until a future schema bump.

### Acceptance criteria

1. A schema 7 save with an existing backup, upgraded through a test-only
   schema 8 migration, ends with the old backup in `previous[1]` deep-equal
   to before, and a new top-level backup of the schema 7 data.
2. Two further test upgrades leave two entries in `previous`, oldest first,
   both unchanged.
3. A failed migration step followed by a successful retry does not add a
   second backup (today's behaviour kept).
4. A save with no backup gets one exactly as today.
5. A non-table `WarbandFYI_Backup` is preserved under `previous`.
6. `WarbandFYI_DB` after migration is identical to what schema 7 code
   produces today.
7. All existing tests pass; new tests in `tests/BackupChainTest.lua`.
8. In-game: `/reload` on a current save changes nothing in the file (no
   upgrade, so no backup is written); Maintenance still shows the backup.

### Rollback

- Revert the PR. The data change is additive: older code ignores
  `WarbandFYI_Backup.previous` and keeps using the top-level fields.
- Older code would replace the whole `WarbandFYI_Backup`, `previous`
  included, only on its own next schema upgrade. Schema 7 code has none, so
  this cannot happen without first installing a newer build.
- Take an external backup (section 12) before testing any build of this PR.

## 15. Decisions

Recorded 2026-10-24 from review of PR #8.

1. **Safety brake**: a clearly warned degraded or read-only mode, not a
   shutdown. Existing records stay viewable and exportable. Warn before the
   limit; record exactly when tracking stops and resumes; never omit new
   history silently. (Section 7.)
2. **Recovery**: quarantined-record counts, reasons and inspection in
   Maintenance from stage 2a, with read-only export. Invalid records are
   never restored automatically. (Sections 9, 12.)
3. **Compression**: bundling LibDeflate is approved as an optional stage 6
   improvement, only after uncompressed blocks are validated in-game, with
   codec compatibility, integrity checks and lossless round-trip
   verification. (Section 5.4.)
4. **Separate archive addon**: deferred. Reconsidered only if the probe
   confirms real storage and failure isolation and benchmarks justify the
   extra installation step. (Sections 4.1, 9.1.)

## 16. Existing PRs

- **#3** (roll up the last month before a long break): still correct and
  needed. Rollups must depend on whether rows are complete, not on today's
  retention date. Its `prunedThrough` marker stops moving at stage 3c and
  becomes the permanent boundary of history deleted before the archive
  existed; archiving uses separate archived-through markers. Lands in 2a.
- **#4** (repeated currency transfers), **#5** (warband item total),
  **#6** (Notebook reads), **#7** (resource tiles): unrelated to retention;
  review independently.
