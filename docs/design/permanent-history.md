# Permanent history retention

Status: **proposal for review**. Nothing in this document is implemented yet.
Date: 2026-10-24. Applies to schema 7 (`0.2.0-dev.2c`).

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

Those same limits are what keep the save file loadable. Lua 5.1 refuses to
compile a chunk with more than 2^18 − 1 = **262,143 constants**, and a
SavedVariables file is one chunk. Each unique timestamp, id, balance and
amount in it is a constant.

Measured with stock Lua 5.1.5 on a desktop (not yet in WoW, see section 12):

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

If WoW's loader shares this limit, a file that fails to load leaves the addon
with no data, and the next logout writes that empty state over the file. In
other words, removing the caps without another storage format would risk
losing **all** history at once. This design keeps the working set bounded
for as long as it takes to prove an archive works.

Profiles used throughout (rates per active day):

| Profile | Active days/yr | Sessions/day | Events | Snapshots | Gold ledger lines | Gathering rows |
|---|---|---|---|---|---|---|
| light | 120 | 1.0 | 40 | 12 | 10 | 3 |
| typical | 220 | 1.6 | 130 | 40 | 35 | 12 |
| heavy | 330 | 2.0 | 350 | 100 | 80 | 40 |

The event mix follows what `Tracking/*.lua` records (about 42% resource
changes, 22% quests, 8% pet battles, and so on). Real data will differ; the
profiles exist to compare designs, not to predict exact sizes.

## 2. Every path that deletes or discards recorded data

Classification:

- **H** – permanent gameplay history.
- **U** – user-authored content or configuration.
- **C** – disposable cache or duplicate guard.
- **S** – current-state baseline (needed, but describes the present, not history).

| # | Path | Class | What it removes | Treatment |
|---|---|---|---|---|
| 1 | `Database.Prune` – 120-day retention, at every login and new session (`Core/Database.lua`, `Core/Sessions.lua`) | H | Events, snapshots and whole sessions (segments, gold ledger, gathering rows), folded into lifetime totals | Archive before removal (stage 3) |
| 2 | Event cap 8,000 → 7,000 (`Core/Events.lua`) | H | Oldest events, folded into lifetime | Archive before removal (stage 3) |
| 3 | Snapshot cap 4,000 → 3,200 (`Database.AddSnapshot`) | H | Oldest snapshots; only the earliest level and item level survive | Archive before removal (stage 3) |
| 4 | `MigrateWarband` (`Tracking/Resources.lua`), once per currency when it becomes warband-wide | H | Events judged to be per-character copies of a shared balance, by heuristic, **not** folded into lifetime | Quarantine instead of delete (stage 2) |
| 5 | `RepairHistory` (`Tracking/Resources.lua`), once per ledger version | H | Transient dip-and-return pairs, merged sync rows | Quarantine instead of delete (stage 2) |
| 6 | `/wbfyi resetresource` | H (user-initiated) | Every event for one resource | Archive the removed rows (stage 2) |
| 7 | FYI `PruneOccurrences` (12 per FYI) and `PruneHistory` (48 rows, 6 per event) (`Core/ContextFyi.lua`) | H | Which occurrences of a recurring reminder were completed | Stop pruning; growth is about tens of rows a year (stage 2) |
| 8 | World activity `MAX_ROWS` 2,500 per session | H (precision) | Not deleted: later gathering merges into an existing row and loses its own time | Keep; revisit in stage 6 |
| 9 | `EnsureNotebook`, every load | U | Sections whose page is missing, blocks whose section is missing | Quarantine (stage 2) |
| 10 | `NotebookFyi.Ensure`, every load | U | Triggers whose event is not in the current catalog, whose target is gone, or duplicate targets | Quarantine (stage 2) |
| 11 | `ContextFyi.Ensure` / `Normalize`, every load | U | FYIs with an empty title; item text re-clipped and items beyond 12 dropped | Quarantine; clip only on write (stage 2) |
| 12 | `EnsureContextFyis`, `EnsureNotebook` | U | Rows that are not tables (corrupt values) | Quarantine the raw value (stage 2) |
| 13 | Migration 4 | U | `db.plans` deleted without a copy when `notebookLegacy` already exists (only after a downgrade) | Copy into `notebookLegacy.extraPlans` (stage 2) |
| 14 | `ApplyMigrations` backup | U | The previous `WarbandFYI_Backup` is replaced by the next schema upgrade | Never overwrite (stage 1, first PR) |
| 15 | Collection Hunts `Remove` (user action) | U | The hunt's completion record | Keep the completion when hiding (stage 2) |
| 16 | `ClearSample` (user command) | — | Rows marked `sample = true` only | Keep as is; sample rows are not history |
| 17 | `Crafts.ClearSimulated` (debug command) | — | Events marked `meta.simulated` only | Keep as is |
| 18 | Notebook and FYI deletes (user action) | U | The deleted item | Out of scope; possible trash/undo later |
| 19 | Transient `dedupe` keys expire with retention | C | Duplicate guards | Keep expiring, on their own 120-day TTL instead of the retention setting |
| 20 | `transferSeen` (90 days), `recentClaims`, `pendingObserve`, world-activity sources and seen rares, FYI notice "seen", zone visits, holiday icon cache, recipe cache, Housing XP and Prey runtime lists, `currentInstance` | C | Caches | Unchanged |
| 21 | Renown root rebuild, resource `acceptedBalance`/`observed`, `goldLast` | S | Malformed current-state rows | Unchanged; these are not history |

Rows 16–21 stay as they are. Rows 1–15 change as described in section 9.

## 3. Permanent history vs disposable caches

**Permanent** (never deleted automatically; archived or quarantined instead):

- `events`, `snapshots`, `sessions` (segments, `goldByCharacter`, `goldLedger`, `world.rows`)
- `monthHistory` rollups and `lifetime` totals (supplementary, but they are
  the only remaining record of history already deleted before this design)
- `characters`
- `notebook` (pages, sections, blocks, quick notes, FYI triggers), `contextFyis`
  including `completedOccurrences` and `fyiHistory`, `notebookLegacy`
- `housing.collected`, Collection Hunts completions, resource `lifetime` blocks
- `WarbandFYI_Backup`
- the new `archive` and `recovery` stores

**Disposable** (may be rebuilt or expire without loss of history): rows 19–21
above, every in-memory table, summary caches and decoded archive blocks.

A field is permanent unless it can be rebuilt from permanent data or from
the game client. New tracking code must state which kind it adds.

## 4. Physical storage: what is known and what is not

Documented behaviour ([warcraft.wiki.gg: SavedVariables](https://warcraft.wiki.gg/wiki/SavedVariables)):

- All `## SavedVariables` of one addon are written to **one file**,
  `WTF/Account/<ACCOUNT>/SavedVariables/<AddonName>.lua`. Per-character
  variables go to `WTF/Account/<ACCOUNT>/<Realm>/<Character>/SavedVariables/<AddonName>.lua`.
- A second variable such as `WarbandFYI_Archive` in WarbandFYI's own TOC
  therefore shares a file with `WarbandFYI_DB` and `WarbandFYI_Backup`.
  It gives **no** file-level isolation: one parse error or one oversized
  constant table fails all of them.
- WoW keeps one previous copy as `<AddonName>.lua.bak`, replaced at every save.

Unverified, to be tested with the probe in section 12:

- Whether WoW's loader has the same 262,143-constant limit.
- Whether an addon that is installed but **not loaded** in a session keeps
  its SavedVariables file untouched. Only an old forum post says so.
- Whether a parse failure in one addon's file affects any other addon.
- How long WoW takes to write and read files of 25, 50 and 100 MB.

Consequences for this design:

- `WarbandFYI_Backup` already sits in the same file as the data it protects.
  It protects against a bad migration, not against a lost or corrupt file.
  External backup (section 11) is the only protection against that.
- Until the probe proves otherwise, the archive is stored as **strings** in
  the main file. Strings keep the constant count tiny whatever their size.
- A separate archive *addon* (`WarbandFYI_Archive`, load-on-demand, with its
  own file) is a stage 6 option, adopted only if the probe shows that an
  unloaded addon's file is left untouched and that a failure in one file
  does not affect the other.

## 5. Archive format

### 5.1 Layout

```lua
WarbandFYI_DB.archive = {
    format = 1,                      -- archive layout version
    blocks = {                       -- ordered by key; key is deterministic
        ["events:2026-09:000001"] = {
            kind = "events",         -- events | snapshots | sessions | recovery
            month = "2026-09",       -- local calendar month of the rows' time field
            seq = 1,                 -- block number within kind+month
            codec = 1,               -- encoding version
            rows = 1000,             -- row count
            bytes = 412337,          -- length of data
            checksum = 3141592653,   -- Adler-32 of data
            firstAt = ..., lastAt = ...,
            firstId = ..., lastId = ..., -- events and sessions
            idSum = ...,             -- sum of ids, a cheap second check
            folded = true,           -- rows were folded into lifetime when archived
            createdAt = ...,         -- addon time of the commit
            addonVersion = "...",
            data = "return{...}",    -- the rows, encoded
        },
    },
    state = {                        -- progress and errors, never row data
        lastError = nil,             -- { at, stage, key, message }
        brake = nil,                 -- see 7.3
    },
}
```

### 5.2 Encoding rules (codec 1)

- A block is a Lua table constructor of the rows, exactly as stored. Every
  field, id, timestamp, GUID and `meta` entry is kept. Nothing is renamed,
  rounded or summarised.
- **Deterministic**: table keys are written in a fixed order (by type, then
  value). Integers are written with `%d`, other numbers with `%.17g`, strings
  with `%q`. The same rows always produce the same bytes. Measured: byte-
  identical on re-encode of 500, 3,000 and 10,000 rows.
- Only strings, numbers, booleans and tables are allowed. A function,
  userdata, `NaN`, infinity or a cycle fails the encode (section 7).
- Rows keep their original order. A block holds up to 1,000 rows so that
  decoding one block stays well inside a frame (about 12 ms per 1,000 rows
  measured on desktop Lua).
- Decoding uses `loadstring` with an empty environment (`setfenv(chunk, {})`),
  so a block cannot read or change any global.

### 5.3 Verification

A block is valid only if all of these hold:

1. `#data == bytes` and Adler-32 of `data == checksum`.
2. `data` compiles and returns a table of exactly `rows` entries.
3. `firstAt`, `lastAt`, `firstId`, `lastId` and `idSum` match the decoded rows.
4. At commit time only: the decoded rows are deeply equal to the source rows,
   and re-encoding the decoded rows produces identical bytes.

Measured on desktop Lua: a single changed byte is caught by the checksum, and
a truncated block fails to compile. Adler-32 is not a security hash; it
detects accidental corruption, which is its only job here. Corruption that
happens to keep the checksum is caught by the row counts and id checks.

### 5.4 Versioning

- `archive.format` versions the container; `block.codec` versions each block.
- A newer addon reads every older codec forever. Upgrading never re-encodes
  existing blocks unless a later design says so explicitly, and then only by
  writing a new verified block before retiring the old one.
- An older addon that meets an unknown `archive` table leaves it alone:
  `Database.Init` keeps unknown top-level keys (checked in schema 7 code).

## 6. Archiving protocol

### 6.1 One atomic commit, prepared in slices

WoW runs addon Lua to completion before drawing the next frame, and writes
SavedVariables only on logout or `/reload`. If the client crashes, nothing is
written and the previous file stays. So a change made inside one function
call is either fully saved or not saved at all.

Archiving uses that:

1. **Select.** Choose the rows that retention or a cap would have removed,
   grouped by kind and month, up to 1,000 per block.
2. **Prepare (sliced).** Encode a few rows per frame into an in-memory
   buffer, within a budget of about 4 ms per frame. Nothing is written into
   `WarbandFYI_DB` during this stage. If the player logs out or reloads,
   the buffer is simply lost and the rows are still in the working set.
3. **Verify.** Run section 5.3, including the deep comparison, again sliced.
4. **Commit (one call).** In a single synchronous function: check that the
   block key does not already exist; add the block; fold the rows into
   lifetime totals exactly as `Prune` does today; set `folded = true`; remove
   exactly those rows (matched by identity) from the working set; update the
   archived-through markers. No yield happens inside this call.

Measured cost on desktop Lua, per row: encode 0.04–0.05 ms, checksum
0.018 ms, decode 0.012 ms, deep verify 0.006–0.013 ms; about 0.08 ms in
total. At 4 ms per frame that is about 50 rows a frame, so a 1,000-row block
takes about 20 frames, a third of a second at 60 fps.

### 6.2 Idempotence and interruption

- Block keys are deterministic (`kind:month:seq`), and a commit refuses to
  write a key that exists.
- If the working set still contains rows that a committed block also holds
  (which section 6.1 makes impossible, but a downgrade or manual edit could
  cause), the loader compares them. Equal rows are dropped from the working
  set **without** folding again. Different rows are both kept, and the
  conflict goes to `recovery` for review. Queries also de-duplicate (7.2).
- Re-running archiving after a reload starts again from step 1 with the same
  rows and produces the same bytes.

| Interrupted at | Saved state | Next login |
|---|---|---|
| select / prepare / verify | Unchanged (nothing written) | Starts again |
| between commits | Some blocks committed, rest still live | Continues; committed rows are no longer selected |
| crash at any point | The last saved file | Same as above |
| downgrade to an older version | `archive` left untouched; old code prunes the working set as before | Upgrading again finds the archive intact |

### 6.3 Lifetime totals are folded exactly once

Today a row is folded into `lifetime` when it is pruned. The archive keeps
that rule, so the warband (all-time) totals keep their formula: live rows +
`lifetime`.

- Folding happens only inside the commit in 6.1, together with the removal.
- `block.folded = true` records that the block's rows are already in
  lifetime. Warband totals never decode archive blocks.
- Period queries (7.1) use rows (live and archived) and **never** lifetime.
- Nothing ever un-archives a row into the working set. A later "rebuild
  lifetime from rows" tool would build a separate table and compare, not
  add to the existing one.

## 7. Failure handling

### 7.1 Principle

Any encode, decode, verify or commit failure leaves the original rows where
they are, records the error and tells the player. Nothing is reset,
regenerated or discarded because of a failure.

### 7.2 Cases

| Failure | Response |
|---|---|
| Encode fails (unsupported value) | Rows stay live. `archive.state.lastError` records the row id and field. One chat line per session; a Maintenance line until resolved. |
| Verify fails | Same as above; the prepared buffer is discarded, and the rows stay live. |
| Stored block fails to decode or validate at read time | The block is kept untouched and marked `damaged`; its months show "archived data unavailable" rather than empty. A Maintenance line explains how to restore from an external backup (section 11). |
| Archive table missing or not a table on load, while `db.archiveCommitted` (a count kept outside the archive table, raised by every commit) says blocks exist | Never create an empty archive over it. Archiving stops; the working set stays as is; the player is told to restore from backup. |
| Duplicate between live rows and a block | Section 6.2. |

### 7.3 Safety brake

If archiving cannot run and the working set keeps growing, the addon must not
delete rows, and it must not let the file grow past what can load. When the
working set reaches its hard ceiling (a constant budget, see 9.4), the addon
**stops recording new high-volume rows** (resource changes, snapshots, world
activity), keeps everything already recorded, and shows a persistent warning.
Losing new observations is recoverable by fixing the error; losing recorded
history is not.

## 8. Queries over live and archived rows

### 8.1 Ownership

Every row lives in exactly one place: the working set or one archive block.
The commit in 6.1 moves it in one step, so there are no gaps or overlaps by
construction.

### 8.2 Reading a period

```
rows(kind, startAt, endAt):
    months = calendar months overlapping [startAt, endAt]
    for each month older than the working set's oldest row:
        for each valid block of that kind and month: decode (cached), filter by time
    plus live rows filtered by time
    de-duplicate: events and sessions by id; snapshots by (guid, at, reason, level, itemLevel, money)
```

- De-duplication is defence in depth; 8.1 should already guarantee it.
- Decoded blocks go into a small cache (for example 8 blocks), dropped when
  the window closes.
- Months before `db.prunedThrough` (PR #3) lost rows to deletion before this
  design existed. Their monthly rollup stays the authority for them, and the
  UI says the detail is incomplete.

### 8.3 Making period queries cheap (stage 5)

- **Per-day totals** kept up to date as each event is recorded, so Today,
  Week and Month read tens of numbers instead of scanning rows.
- **Monthly rollups** become rebuildable caches. A missing rollup is built in
  the background a few milliseconds per frame. That replaces the measured
  104 s to roll up 120 light-profile months at once on first load.
- **Time index**: the working set is append-mostly, so a binary search on
  time finds a period's first row.
- Activity lists and charts decode only the blocks for the months shown.

## 9. Migration sequence

Each stage is one or more focused PRs, reviewed and tested in-game before the
next starts. Nothing is merged, tagged or released automatically.

### 9.1 Stages

| Stage | Change | Caps and retention | Deletion stops for |
|---|---|---|---|
| 0 | Today | Delete | — |
| 1 | Keep every pre-migration backup (first PR, section 13) | Unchanged | Backups (row 14) |
| 2 | Quarantine instead of delete for migrations, repairs and normalisers; land PR #3 | Unchanged | Rows 4–7, 9–13, 15 |
| 3a | Archive codec and verification, tests only, not called | Unchanged | — |
| 3b | Shadow archiving: archive rows before deleting them, keep deleting as today, compare | Delete, after archiving | — (proves the archive with real data) |
| 3c | **Archive instead of delete**: retention and caps remove a row only by committing it to a verified block | Bound the working set only | **Rows 1–3: all automatic deletion ends here** |
| 4 | Read the archive in month, gold, resource, pet and character views | Unchanged | — |
| 5 | Per-day totals, rollup backfill, time index | Unchanged | — |
| 6 | Optional: compression, separate archive addon, larger working set | May be raised, see 9.4 | — |

### 9.2 When the 120-day retention can stop deleting

**At stage 3c, and not before.** All of these must hold first:

1. Stage 3a's tests pass: round-trip and determinism over generated data
   covering every value type the addon stores; corruption, truncation and
   missing-block tests; interruption and repeated-run tests (section 10).
2. Stage 3b has run in-game for at least two weeks on your account with zero
   verification failures, and the shadow blocks decode to exactly the rows
   that were deleted.
3. The probe (section 12) has been run, so the working-set size limits are
   known for WoW itself.
4. An external backup procedure (section 11) has been followed at least once,
   and a restore from it has been rehearsed on a copy.
5. The safety brake (7.3) is in place and tested.

### 9.3 When the count caps can stop deleting

Also at 3c: the 8,000-event and 4,000-snapshot caps keep their numbers but
become **archive triggers**. Above the cap, the oldest rows are committed to
the archive instead of being deleted.

### 9.4 When the caps can be raised or removed

Never removed. The working set must always stay under a constant budget that
is known to load. They can be **raised** at stage 6 only if:

- the probe shows WoW's real limit, and
- the addon measures its own constant budget (an estimate kept in
  Maintenance) and keeps it under half of that limit.

Retention as a *time window* stops meaning "delete after N days" at 3c; it
becomes "keep N days of rows unarchived for fast access". The setting stays
internal; there is no player-facing retention option to set.

### 9.5 Expected file size with the archive

Measured on desktop Lua with the typical profile, working set = current
month, older months as uncompressed strings:

| Typical history | File | Parse | Memory after load | Decode 1 month | Decode all |
|---|---|---|---|---|---|
| 1 year | 9.8 MB | 0.08 s | 10 MB | 18 ms | 0.2 s |
| 3 years | 26 MB | 0.19 s | 25 MB | 17 ms | 0.6 s |
| 5 years | 44 MB | 0.31 s | 43 MB | 18 ms | 1.1 s |
| 10 years | 89 MB | 0.62 s | 85 MB | 18 ms | 2.2 s |

Writing (logout) the 10-year archive file took 0.58 s, against 9.7 s for the
same history stored as tables (which then failed to load). Deflate shrank the
synthetic data about 8×; real data will compress less. Compression is a
stage 6 option (bundled LibDeflate), only after the uncompressed format has
proved itself, so that a compression bug can never be the first archive.

## 10. Test plan

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
  missing `archive` table; a block present twice under different keys.

**Lifecycle**
- Interruption: stop after select, part-way through prepare and verify, and
  between commits; reload; confirm identical end state and no double fold.
- Repeated runs: archiving twice over the same state commits nothing new.
- Reload and upgrade: schema 7 save → each stage; a save already holding
  legacy-pruned months (PR #3 marker).
- Downgrade: a stage 3c save opened by schema 7 code keeps `archive`
  untouched; upgrading again resumes cleanly.
- Recovery: corrupt a block, confirm `damaged` handling; restore the file
  from an external backup copy and confirm every block validates.
- Totals: warband totals before and after archiving are identical; period
  totals for every month are identical whether rows are live or archived.

**Scale**
- The benchmark scripts used for this document move into `tests/bench/`
  (not part of `RunAll`): 1, 3, 5 and 10 years at each profile, reporting
  file size, write time, parse time, memory, decode time, archive commit
  frame cost and dashboard build times.

## 11. External backup and export

WoW's `.lua.bak` is one rolling copy, replaced at every save. It is not a
long-term backup: a bad session followed by one more logout overwrites it.

**Backup procedure** (documented in `docs/GUIDE.md`, no addon code needed):

1. Log out of WoW completely (the file is only consistent then).
2. Copy `WTF/Account/<ACCOUNT>/SavedVariables/WarbandFYI.lua` to a dated
   folder outside the WoW directory, for example
   `WarbandFYI-backups/2026-10-24/`.
3. Keep at least the last few dated copies plus one per month. Never delete
   older copies automatically.
4. Optionally store copies in a cloud-synced folder or on another drive.

**Verify tool** (stage 3a, in `tools/`, runs with stock Lua 5.1):
`lua tools/verify-archive.lua <WarbandFYI.lua>` loads a copied file, checks
every block (section 5.3) and prints counts per month. It never writes to the
file.

**Export tool** (stage 4): `lua tools/export-history.lua <WarbandFYI.lua> <out>`
writes JSON Lines (one row per line, all fields kept) and CSV summaries per
month. It reads a copy, never the live file, and the addon never removes
anything after an export.

**Restore procedure**: with WoW closed, copy a backup over
`WarbandFYI.lua`, run the verify tool on it, then start WoW. The addon treats
a restored file like any other save; archive blocks are validated on read.

## 12. Disposable probe addon

A separate addon folder, `WarbandFYI_SVProbe`, kept outside the WarbandFYI
release (in `tools/sv-probe/`). It has its own TOC and its own
SavedVariable, `WBFProbe_DB`, and never reads or writes any WarbandFYI
variable. Its file is `SavedVariables/WarbandFYI_SVProbe.lua`, separate from
WarbandFYI's.

Tests, each driven by a slash command and a `/reload`:

1. **Constant limit**: write N unique numbers as table rows, reload, report
   whether the variable came back. Step N through 200k, 262k, 263k, 300k,
   500k, 1M.
2. **Failure scope**: after a failed load, is WarbandFYI's own data intact?
   (Expected yes, as it is a different file; this confirms it.)
3. **Unloaded addon**: a second probe addon, load-on-demand and not loaded,
   with a marker in its file; after several sessions, is the file byte-for-
   byte unchanged?
4. **Large strings**: save 10, 25, 50 and 100 MB of string data; record
   logout and login times and in-game memory.
5. **Logout safety**: does a very slow save delay logout, and is the file
   complete afterwards?

Risks and precautions: the probe can make logouts slow while large data is
saved, and a failed load clears only the probe's own variable. Before
running it, take an external backup (section 11) anyway. When finished,
delete the probe folder and its SavedVariables file. The probe is not
shipped and never runs as part of WarbandFYI.

## 13. First implementation PR (stage 1): keep every pre-migration backup

### Why first

`ApplyMigrations` replaces `WarbandFYI_Backup` whenever a save is upgraded to
a newer schema than the one the backup targets. Stage 2 or 3 will need
schema 8, and that upgrade would replace the only existing safety copy.
This must be fixed before any schema change.

### Change

- `Core/Database.lua` only, plus tests and changelog.
- If `WarbandFYI_Backup` exists and a new backup is needed, move the existing
  backup into `WarbandFYI_Backup.previous`, an array kept in creation order,
  before writing the new top-level fields. Existing fields (`createdAt`,
  `addonVersion`, `fromSchema`, `targetSchema`, `data`) keep their names and
  meaning, so the Maintenance panel and older code still read the newest
  backup.
- Never remove an entry from `previous`. No size-based pruning.
- A backup that is not a table is kept as `{ unreadable = <value> }` inside
  `previous` instead of being overwritten.
- No schema bump, no change to caps, retention or any tracked data.

### Acceptance criteria

1. A schema 7 save with an existing backup, upgraded through a test-only
   schema 8 migration, ends with the old backup in `previous[1]` unchanged
   (deep-equal) and a new top-level backup of the schema 7 data.
2. Two further upgrades leave `previous` with two entries, oldest first, both
   unchanged.
3. A failed migration step followed by a successful retry does not add a
   second backup (current behaviour preserved).
4. A save with no backup gets one exactly as today.
5. A non-table `WarbandFYI_Backup` is preserved under `previous`.
6. `WarbandFYI_DB` after migration is identical to what schema 7 code
   produces today.
7. All existing tests pass; new tests in `tests/BackupChainTest.lua`.
8. In-game: `/reload` on a current save changes nothing (no upgrade, so no
   backup is written); the Maintenance panel still shows the backup.

### Rollback

- Revert the PR. The data change is additive: older code ignores
  `WarbandFYI_Backup.previous` and keeps using the top-level fields.
- Caveat: older code, on its own next schema upgrade, would replace the whole
  `WarbandFYI_Backup` table, `previous` included. There is no such upgrade in
  schema 7 code, so this cannot happen without a newer version first.
- If a reverted build must be run, take an external backup first
  (section 11).

### Size note

Each kept backup is a full copy. Today that is bounded by the caps. After
stage 3 the archive strings would be copied into each backup too; stage 3a
will propose excluding committed, immutable archive blocks from backups by
reference to their key and checksum, since migrations never modify them.

## 14. Existing PRs

- **#3** (roll up the last month before a long break): still correct and
  needed. Rollups must depend on whether rows are complete, not on today's
  retention date. Under this design its `prunedThrough` marker stops moving
  at stage 3c and becomes the permanent boundary of history lost before the
  archive existed. Archiving uses separate archived-through markers, because
  archived rows are not lost. Land it in stage 2.
- **#4** (repeated currency transfers), **#5** (warband item total): unrelated
  to retention; review independently.
- **#6** (Notebook reads), **#7** (resource tiles): performance work that
  matters more as data grows; review independently.

## 15. Open questions for review

1. Is stopping new high-volume recording (7.3) the right last resort, or
   would you rather the addon disable itself until the error is fixed?
2. Should the recovery list be visible in the UI from stage 2, or only in
   Maintenance and the export tool?
3. Is a bundled LibDeflate acceptable for stage 6, or should compression stay
   out entirely?
4. Should the separate archive addon (stage 6) be pursued if the probe shows
   it isolates failures, given it adds a second folder to install?
