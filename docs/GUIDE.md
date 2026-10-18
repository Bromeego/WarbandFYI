# WarbandFYI guide

For an overview and installation steps, start with the [README](../README.md).

## Finding your way around

Open WarbandFYI with `/wbfyi` or `/warbandfyi`.

| View | What it is for |
| --- | --- |
| Current Session / Last Session | Reviewing your current or previous stretch of play. |
| Today / This Week / This Month | Seeing activity over a longer period. |
| Warband / Characters | Reviewing overall progress and individual characters. |
| Resources | Inspecting tracked resources and currencies. |
| Activity | Browsing recorded events. |
| Notebook | Keeping notes and plans together. |
| Collection Hunts | Managing collection goals and character participation. |

Collection Hunts relies on the targets and information the addon supports. A selected source is not proof that a custom item drops there, and an unknown eligibility or lockout state should not be treated as an available attempt.

## Useful commands

| Command | Action |
| --- | --- |
| `/wbfyi` | Toggle the main window. |
| `/wbfyi help` | Show available commands. |
| `/wbfyi status` | Show the active session and recorded data counts. |
| `/wbfyi hide` | Hide the main window. |
| `/wbfyi reset` | Reset the window's position and size; this does not erase activity history. |
| `/wbfyi notebook` | Open the Notebook. |
| `/wbfyi note <text>` | Add a quick note. |
| `/wbfyi search <text>` | Search from the addon. |
| `/wbfyi hunt list` | List collection hunts. |

## How tracking works

### Characters and sessions

The addon records activity while it is enabled and uses information supplied by the game. It cannot reconstruct a complete history from before installation. Log into your other characters to refresh their information.

Sessions can continue through a reload or a character switch. The default session timeout is one hour, with a setting to change it. Activity after a timeout starts a new session, so a session is not necessarily the same as a single login or pet battle.

### Pet progression

Pet level events retain the levels gained in each battle. Top Pets by Levels Gained sums those individual gains for the selected period.

Recent Pet Activity also shows the known progression within the saved session. If Boneshard goes from level 1 to 24 and then 24 to 25, the final row displays `Boneshard  1 -> 25 (session)`. The underlying final event still records `24 -> 25` and a gain of one level.

Session progression uses the pet's unique ID, so two pets with the same name stay separate. A pet starting at 23 shows 23 -> 25, and separate sessions are not combined. The displayed span uses retained session history, which can include earlier activity outside the selected date range or on another character in that session. Totals still follow the selected period and character.

If earlier history or identifying information is missing, the addon keeps the known event detail instead of assuming a starting level. Missing opening levels are not counted as an invented one-level gain.

### Pet Level Lists in Notebook

Open `/wbfyi notebook`, choose a page and section, then use **Add → Pet Level List**. **Add pet** opens a searchable, paged list of owned battle pets. Search by species, custom name or pet ID. Each copy has its own row; the short ID beside its name distinguishes duplicates, and the tooltip shows its full ID.

Lists are saved account-wide with Notebook. They store the chosen pet's ID, not a saved level: current levels and **Done** at level 25 come from Pet Journal. Click a listed pet to open it in the Journal; right-click to remove it. Lists support up to 60 pets and can be duplicated using the usual block menu.

Open the page or section in the floating Sheet to keep progress visible; **Hide completed** hides level-25 pets there. Existing Notebook FYI reminders include the list's live completion count and pet rows. Reminders remain opt-in through the usual FYI controls. This is a planning list, with no team loading or battle automation.

Older species-only entries show **Choose a copy**: add that species again and select the intended pet to replace the old entry. A caged, released or temporarily unavailable pet remains listed as **Pet unavailable**, and never borrows another copy's level. If the client lacks the unfiltered owned-pet API, the picker says **Journal filters apply**; clear Journal filters to find other pets. Already saved pets are always read directly by ID.

When Rematch is running with a compatible queue API, listed pets show **Queued in Rematch** in Notebook, Sheet and FYI. This optional badge matches the exact pet ID and updates when Rematch updates its queue. Unqueued pets and unavailable or incompatible Rematch installations show no Rematch status. Level-25 pets show completion instead. WarbandFYI only reads queue membership; it never adds, removes or reorders Rematch pets, and does not save a second copy of its queue.

### Saved data and history

WoW saves addon data locally using the `WarbandFYI_DB` and `WarbandFYI_Backup` saved variables. The account's `WTF/Account/<account>/SavedVariables/WarbandFYI.lua` file contains this data; it is separate from the addon code in `Interface/AddOns`.

Close WoW before manually copying or restoring saved data so the game does not overwrite your changes. Back up saved data before testing changes that alter storage or history.

Detailed history is bounded: the default retention period is 120 days, and the event list also has a size limit. Older detail may therefore be unavailable even when summary totals remain. Neither Git history nor updating the addon restores pruned gameplay events.

## Reporting a problem

Open a [GitHub issue](https://github.com/Bromeego/WarbandFYI/issues) with the addon version, what you expected, what happened, and steps to reproduce it. Include the relevant view, filters and any Lua error. A screenshot is useful for display problems; avoid posting your entire saved data file unless it is needed and you have checked its contents.

## Working on the addon

The repository contains the addon source directly at its root:

- `Core/` — startup, storage, sessions and aggregation.
- `Tracking/` — game event tracking and feature logic.
- `UI/` — windows, views and controls.
- `Utils/` — shared formatting, time and debugging helpers.
- `tests/` — standalone Lua regression checks.
- `WarbandFYI.toc` — addon metadata and file load order.

Run the current regression tests from the repository root with Lua 5.1:

```sh
lua tests/PetSessionProgressTest.lua
lua tests/ProfessionPetTest.lua
lua tests/CollectionHuntsTest.lua
lua tests/NotebookPetsTest.lua
git diff --check
```

These tests cover pet session progression, pet/profession aggregation, collection-hunt lockouts, and Notebook pet identity, persistence, progress and picker interactions. They do not replace in-game checks of rendering, game APIs or other features. For Pet Level Lists, check two copies of one species, level one to 25, reload, cage one, page through picker results, and open the same list in Notebook, Sheet and an FYI reminder.

Add a short entry under **Unreleased** in [CHANGELOG.md](../CHANGELOG.md) for each notable change. Use Added, Changed, Fixed or Removed as appropriate. When publishing a release, move those entries under its actual version and release date, and update the addon version in the TOC. Git commits retain the finer implementation history.
