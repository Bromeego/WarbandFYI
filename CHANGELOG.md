# Changelog

Notable changes to WarbandFYI are recorded here. Work that has not been published as a versioned release stays under Unreleased.

## Unreleased

### Added

- Collection Hunts can track things that don't drop from a boss, such as quest rewards, vendor items, world drops and secrets, as **goals**. When the Journal shows it isn't a raid or dungeon boss drop, for example *Vendor: Breanni, Zone: Dalaran*, the form picks **Not a boss drop: track as a goal** for you. You can also choose it from the source list. A goal shows where to get it and stays on your list until you collect it. Mounts, pets, achievements and appearances complete on their own, and items are marked complete by hand. Goals have no lockout, so they never appear in the login FYI.

### Changed

- Collection Hunts finds the raid or dungeon boss for most drops on its own. When the Journal says something like *Drop: Siegecrafter Blackfuse, Raid: Siege of Orgrimmar*, WarbandFYI checks the Encounter Journal that this boss is in that raid and uses it as the source. Weekly lockouts then work like any other hunt. Which difficulty drops it isn't checked yet. Hand-maintained sources with special rules, such as Invincible's 25-player Heroic or the Headless Horseman's daily bag, still take priority.
- Pet hunts count every character as eligible, so they show attempts and appear in the login FYI.
- The login FYI for Collection Hunts is now a short nudge for the character you're playing: each hunt it can make an attempt at, with its icon and where it drops, for example *Drake of the South Wind — Throne of the Four Winds - Al'Akir*. Other characters stay on the Collection Hunts page, and the card is skipped when this character has nothing to attempt.
- That card joins whichever FYI popup is already open at login, such as **Active events**, instead of waiting unseen until that popup is closed. It has an **Open Hunts** button.
- The card can be brought back at any time: **Show in FYI** on the Collection Hunts page, the **Collection Hunts** button at the bottom of any FYI popup, or `/wbfyi hunt fyi`.
- Collection Hunts trusts each character's raid lockouts until the weekly reset instead of for only 24 hours. A lockout only changes when that character plays, which rescans it. Characters last seen before this week's reset show as available again, and a holiday daily bag shows as available again after the daily reset.
- Adding a Collection Hunt uses one box for every kind of target. Type a mount name and pick it from the suggestions, Shift-click a bag item or Pet Journal pet, enter an item ID, or click **Use Current Selection** to take what's selected in the open Mount Journal, Pet Journal or Achievements window. The line under the form says what it recognised, such as "Pet: Arfus" or "Mount: Invincible's Reins".
- Collection Hunts reads where a mount or pet comes from in its Journal entry (for example *Drop: Headless Horseman, Zone: Scarlet Monastery*) and picks the matching raid or boss automatically. Only bosses WarbandFYI already supports are chosen. Anything else shows the Journal text and asks you to pick.
- The Add Hunt form is tidier: mount suggestions show their icon with an **Owned** tag, the source and Add Hunt buttons span the form, Add Hunt stays disabled until something is entered, and dropdowns use an arrow instead of a trailing "v".
- Dashboard currency tooltips list each figure on its own line, with the label on the left and the value on the right: net for the period, current balance, earned and spent, each in its own colour.

### Fixed

- Shift-clicking a pet in the Pet Journal, in the list or on the pet card, now fills the Collection Hunts target box, including pets you have not collected yet. The box no longer needs to be clicked into first.
- Blizzard's internal tracking currencies marked **[DNT]** ("do not translate"), such as **[DNT] Nebulous Voidcore Turn-In Tracker**, no longer appear on the Dashboard, in Resources or in activity. Any already tracked disappear after the next login or `/reload`. The same check already kept quests marked [DNT], [NYI] or [PH] out of activity.

## 0.2.0-dev.2i — 2026-10-31

### Changed

- Close buttons on the main window, the Notebook sheet, the FYI popup and its windows, and the Settings copy dialog now match the WarbandFYI theme instead of Blizzard's red X.
- Hover, selected and pressed states, row highlights and tooltip text use one consistent set of colours across every page, so the same kind of thing looks the same everywhere.
- Less work while you play. When the Notebook or an FYI is open, bag, currency and achievement updates are now gathered into one redraw instead of redrawing the whole window for each one, and the redraw waits until combat ends. The quest log is read at most once a second while questing, and rare tracking no longer checks every health change of an ordinary target.

### Fixed

- The one-time clean-up of saved currency history now runs. It removes brief false dips, where a balance read low for a moment and bounced straight back, from Resources graphs and activity. A mistake meant it had never run outside the tests.

## 0.2.0-dev.2h — 2026-10-31

### Changed

- The Collection Hunts page lays out its detail column top to bottom: target, actions, collection goal, farming characters, this week's status, then the character lists. Sections no longer overlap, and the page uses the full window width when it is wider.
- The selected hunt in the list is highlighted, and hunt icons no longer disappear behind the button.
- Empty pages now explain what will show up and how to get started: Activity, the Dashboard, detail pages, Pet Battles and Collection Hunts with no hunts.
- Notebook reads no longer re-check the whole notebook on every call. Listing 20 pages with 300 blocks went from about 1.6 seconds to under a millisecond in testing, so large notebooks stay responsive.
- Dashboard currency tiles read the event log once per refresh instead of once per tracked resource, cutting a full-log week refresh from roughly 100–300 ms to under 30 ms in testing.

### Fixed

- Moving the same amount of a currency between the same two characters more than once now records every transfer. Previously any earlier identical transfer hid the new one, and a transfer recorded live on the sending character could hide the receiving side.
- The warband total on a tracked Notebook item line counts this character and the Warband bank live, so spending or moving items no longer leaves the total stuck at the last scanned amount until the tracker rescans.
- FYI popups no longer replace each other. When login, event and zone reminders arrive together, each opens in turn as you close the one before. Login reminders that come due during combat now open when combat ends instead of being skipped.

## 0.2.0-dev.2g — 2026-10-30

### Changed

- Buttons, text boxes and scrollbars now match the WarbandFYI theme everywhere, replacing the stock red Blizzard buttons and input boxes. Buttons highlight gold on hover and dim when unavailable.
- Status colours are consistent across Collection Hunts, the Dashboard and Resources: one green for available or collected, one amber for done or attempted, and one grey for unverified.

### Fixed

- Shift-clicking an item from your bags now fills the Notebook **Track Item** box, even with chat closed.
- Blizzard's internal data-store currencies (Dragon Racing **Temp Storage** and **Scoreboard** entries, Housing **Personal Best Record** entries) no longer show up under Resources as Unknown / Other.

## 0.2.0-dev.2f — 2026-10-30

### Added

- Collection Hunts can track the **Headless Horseman** daily loot bag during Hallow's End. Each character shows Available or Done today, resetting daily, and the login FYI lists characters that have not looted today's bag. Hunts can now target pets (Shift-click in the Pet Journal or a pet item) and complete automatically once the pet is collected.

### Fixed

- Item counts on FYI lines no longer appear twice: the item line shows only its name, with You, Warband bank and Total each on their own line below.

## 0.2.0-dev.2e — 2026-10-28

### Fixed

- The last month you played before a break of about three months or more is now rolled up when you return, instead of being lost as retention removed its rows. A closed month whose raw rows were trimmed reads its complete rollup.

## 0.2.0-dev.2d — 2026-10-27

### Added

- Optional, read-only **Queued in Rematch** status on Notebook pets, Sheet and FYI. Hidden when Rematch is unavailable or the exact pet is not queued; no extra notifications or queue management.
- Individual-pet Notebook level lists with saved GUIDs, live level-25 completion, a paged picker, floating Sheet support and FYI progress. Older species entries remain available for choosing a specific copy.
- A concise addon README and a separate guide covering usage, tracking behaviour, saved data and development checks.
- This changelog to track notable changes alongside the Git commit history.
- `lua tests/RunAll.lua` to run every regression test from the repository root.
- Regression tests for pet session progression and existing pet/profession aggregation behaviour.

### Fixed

- A saved-data upgrade no longer replaces the previous pre-upgrade backup. Every earlier backup is kept, unchanged, in `WarbandFYI_Backup.previous`, and Maintenance shows how many are kept.
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
