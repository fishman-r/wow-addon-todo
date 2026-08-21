# Todo

[简体中文](README.md) | **English**

[**⬇ Download Todo 1.0.0-beta.1 (ZIP)**](https://github.com/fishman-r/wow-addon-todo/raw/refs/heads/main/releases/Todo-1.0.0-beta.1.zip)

> Extract the archive and place the enclosed `Todo` folder in `_classic_titan_/Interface/AddOns/`. This version still requires validation in the live Titan Timewalking 38002 client.

Todo is a personal session-planning addon for level-80 characters on the “Titan Reforged · Timewalking” server. The current version is `1.0.0-beta.1`, targeting `Interface: 38002`.

For the complete product, interaction, data, and acceptance baseline, see [Todo v1 product and feature design (Chinese)](docs/Todo-v1-product-design.md). `beta.1` implements the first installable, plannable, executable, and persistent end-to-end development loop. Features that have not yet been validated in the live client are explicitly labeled “not observed,” “not verified,” or “unavailable” in the UI and `/todo doctor`; this build must not be described as fully compatible with 38002 yet.

## In-game UI preview

> These images are generated from the current ElvUI-inspired interactive prototype and sample data. They are development previews, not screenshots from the live Titan Timewalking 38002 client. The final in-game appearance remains subject to live-client validation.

### Current plan

![Todo current-plan development preview](docs/images/todo-plan-preview.jpg)

### Session setup

![Todo session-setup development preview](docs/images/todo-session-setup-preview.jpg)

## Implemented in beta.1

- Only characters at exactly level 80 can generate plans, track time, or collect valuation data. Other levels only see an access explanation.
- On an actual login, the player must confirm workday/holiday mode, minimum available playtime, and a manually selected starting area. A detectable `/reload` continues the current session.
- Planning always uses 85% of the actual remaining time, with no fixed limit on the number of recommendations.
- Workday mode does not automatically recommend raids or reward tasks estimated to take more than 30 minutes each.
- Holiday raid priority is P5 → P4 → P3 → P2 → P1 → Vault. A 25-player raid defaults to 120 minutes, while the 21-player Vault defaults to 30 minutes.
- Once generated, a plan freezes its members, route, and order. Completion, skipping, or price changes never reorder it automatically; only an explicit replan changes the plan.
- The main window displays `actual elapsed time / preset available playtime`. Elapsed time may exceed the preset. Editing parameters or choosing “Play 30 more minutes” does not reset elapsed time.
- Estimated durations for tasks, travel, and raids are read-only. Learned durations use the median of the current character's latest 20 valid samples.
- Concurrent task timing is dynamically split equally across the active set. Cross-area travel pauses task allocation to avoid double-counting.
- The UI has four fixed pages: Current Plan, All Candidates, Valuation Data, and Settings.
- Candidate search supports case-insensitive substring matching across task name, area, profession, activity type, and questID. Multiple keywords use AND matching.
- Candidate details allow corrections to unlock state, today's completion state, area, fixed cost, and the profession pool's current questID. Estimated duration has no edit control.
- Valuation source priority is: Todo native cache → current external provider → manual pre-auction-cut price → vendor price.
- Auction cache entries never expire automatically. Empty or failed observations do not erase older values.
- Todo never sends auction queries. Legacy auction-result events are read passively only after the player has initiated the current search.
- Auctionator's public read-only API is called only when the player clicks “Import required item prices,” and only for itemIDs currently needed by Todo.
- A reward bag with no samples is worth 0. The data model stores raw content distributions per bag count for revaluation against the current market.
- The standalone dark UI is inspired by ElvUI but does not depend on ElvUI code, configuration, or load order.
- A non-persistent window collapses 60 seconds after the last valid input or operation. Mouse hover neither pauses nor resets the countdown.
- Minimap entry: left-click toggles the window; right-click opens Settings.
- Schema v1 database, preservation of legacy prototype data, per-category two-step cleanup confirmation, and `/todo doctor`.

## Current conservative fallbacks

These boundaries are intentionally preserved until live 38002 testing is complete; guessed data is never used to fill the gaps:

- The P5 fixed-daily catalog currently prioritizes questID, area, and profession identity. Server-specific fixed gold, reward items, material costs, prerequisites, and Chinese titles still require individual verification. Task titles and direct gold values that the client can read unambiguously override placeholders.
- No unverified cross-area travel times are built in. A cross-area combination without a route sample is not added automatically. Players can create samples through start/arrival actions under Settings → Route Time Learning; minutes cannot be entered manually.
- Titan's per-listing semantics for `C_AuctionHouse` are not verified. Modern result events therefore record diagnostic state only and never pretend that an aggregated minimum is the “median of the lowest 20 listings.”
- The Auctionator call signature follows its public v1 API, but the adapter remains labeled “38002 live-client verification required.” TSM and Auctioneer are only unverified compatibility slots.
- Live mappings for actual instanceID/encounterID values for P1–P5 and Vault are not established. The beta observes name aliases and labels the result as unverified.
- Automatic reward-bag batch attribution is disabled. Samples will be recorded only after live testing can establish a reliable window containing bags of the same type and no ambiguous reward sources.
- Until reward items, selectable rewards, and task-cost catalogs are complete, explicit net value is a conservative lower bound. Tasks with unknown costs are not recommended automatically.

The first automatic reward plan may therefore contain very few tasks or even be empty. Todo displays the missing data instead of forcing tasks into the available time.

## Installation

Run:

```bash
./scripts/check.sh
./scripts/package.sh
```

The release package is written to:

```text
dist/Todo-1.0.0-beta.1.zip
```

After extraction, verify the folder layout:

```text
macOS:   /Applications/World of Warcraft/_classic_titan_/Interface/AddOns/Todo/Todo.toc
Windows: <WoW directory>/_classic_titan_/Interface/AddOns/Todo/Todo.toc
```

Enable Todo on the character-selection screen before entering the game. Once logged in, it is recommended to run:

```text
/console scriptErrors 1
/dump select(4, GetBuildInfo())
```

The second command should return `38002`.

## Usage

1. Log in with a level-80 character.
2. Select workday or holiday mode.
3. Enter the minimum available playtime.
4. Manually select a starting area. “Other / ignore the first travel segment” exempts only the first segment.
5. Choose whether raids should be considered automatically; multiple raids may also be reserved manually.
6. Review the read-only preview and generate the plan.
7. Use each plan row to start timing a task, travel segment, or raid, then mark it complete, partially complete, or skipped for this session.
8. Use Replan explicitly whenever plan membership or routing should change.

Slash commands:

```text
/todo                  Open or close the window
/todo help             Show help
/todo doctor           Open Settings and print compatibility diagnostics
/todo info             Show version, build, and level
/todo work 1.5         Prefill workday mode and 1.5 hours; confirmation is still required
/todo holiday 4        Prefill holiday mode and 4 hours; confirmation is still required
/todo replan           Replan using the actual remaining time
/todo extend 30        Set T to the current E + 30 minutes and replan
/todo stay             Toggle persistent display
/todo ping             Verify that the core loaded
```

There is no slash command for deleting data. Under Settings, the same delete control must be clicked a second time within five seconds to confirm.

## Code structure

```text
Todo/
├── Todo.toc             Metadata and load order
├── Compat38002.lua      Compatibility and fallback gateway for all game APIs
├── Catalog.lua          P5 task identities, areas, raids, and constants
├── Store.lua            Schema, scopes, cycles, migrations, and sample medians
├── Valuation.lua        Item/task/reward-bag valuation and auction sources
├── Planner.lua          Candidate state, search, route optimization, stable plans, and sessions
├── Tracking.lua         Concurrent task, travel, raid, and anomalous-sample timing
├── UI.lua               ElvUI-inspired four-page UI, parameter panel, and interactions
└── Todo.lua             Events, login policy, slash commands, and dispatch
```

Offline test coverage includes:

- combined-value optimization with no fixed recommendation-count cap;
- workday/holiday raid rules;
- `T/E/R/B` handling and continued timing past the preset;
- multi-keyword search;
- valuation source priority, lowest-20 median, and preservation after empty results;
- explicit, on-demand, zero-query Auctionator import;
- first reward-bag sample;
- equal allocation across three concurrent tasks, active-set changes, and travel exclusion;
- four-page UI, login parameter confirmation, 60-second hiding, T changes without resetting E, and the non-level-80 block.

## First live-client checklist for 38002

1. Enable script errors, log in at level 80, and complete one plan-generation flow.
2. After `/reload`, confirm that the plan and accumulated wall-clock time continue. After a full logout/login, confirm that the session does not resume silently.
3. Use two planned tasks to verify automatic start on acceptance, concurrent allocation, and stop on turn-in.
4. Learn one cross-area route manually, then replan and confirm that its source becomes “this character's measured median.”
5. In workday mode, confirm that there are no automatic raids or automatic tasks longer than 30 minutes.
6. With two holiday hours, only Vault may be selected automatically; with four hours, P5 raids should have priority.
7. Manually search for an item needed by Todo. Confirm that Todo sends no query and determine whether the recorded results truly represent individual listings.
8. Install the target Auctionator version and run one explicit import. Record its version, price semantics, market scope, and any failure.
9. Request raid lockout data and record every actual instanceID, encounterID, and name.
10. Use a level-79 character to confirm that timing and valuation collection are disabled.

Only after every live-client gate in section 22.10 of the product design has passed may “development preview” be changed to “compatible with 38002.”
