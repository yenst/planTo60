# planTo60

A leveling planner for WoW Forever and Classic Era. Set a target level, a deadline and the hours you can play; planTo60 gives you a daily XP target and recalculates it after every daily reset. Slash command: `/pt60`.

## How the plan works

- **Same time every day (default).** XP comes much faster at high levels, roughly 8k XP/h in levels 1–10 versus about 46k in the 50s. So planTo60 splits the remaining *play time* evenly instead of the XP. Targets start lower and grow as you level, but each play day takes about the same time. The guide curve (`Curve.lua`) comes from the hours players report per 10-level bracket, divided into each bracket's XP. Only its shape matters for the targets; your measured pace converts it into your own hours.
- **Same XP every day** is the alternative mode: `remaining XP × today's weight ÷ sum of weights of the play days left`.
- **Fixed at reset.** Targets are set at the server daily reset, deadline day included, so they don't shrink while you play.
- **Recalculation.** Each reset recalculates the plan. Missed XP is spread over the days that remain, and XP earned ahead of plan lowers later targets.
- **Schedule = hours you can play.** You set hours per weekday (0–8h in 30-minute steps) as bars: click a bar to set it, scroll for ±30m, right-click for a day off. The filled part of each bar is how much of that time the goal needs. Single days can be marked off in the calendar.
- **Changing today's time.** Lost time to AFK or a break, or got extra? Use the Overview's `-30m / +30m / Reset` buttons, `/pt60 afk 30` or `/pt60 time 1.5`. Only today's target changes; what you drop moves to later days. AFK time never lowers your pace, since only active minutes count.
- **Status.** Ahead, behind and on track are measured against the plan as it was on the day you set the goal, and shown in days. You're **At risk** when the goal needs more time than you set aside before the deadline.
- **Banked XP:** XP from quests that are finished but not handed in shows as "+12k ready" and as a lighter part of the bar. It shortens the time left today but counts as gained only once handed in, so XP handed in after the reset counts for the next day.
- **Pace** = the guide XP/hour for your level × your personal factor. Each active minute (XP gained or in combat) over the last 5 active hours is stored as a ratio against the guide rate for the level you were at. Until about 10 active minutes are recorded, the guide rate is used and marked "(guide)".

## In game

- **Setup wizard:** opens on first login, or with `/pt60 setup`. It walks through goal, schedule and tracker.
- **Tracker:** an XP-bar style bar for today's target, with finished quests and rested XP as extra segments. Drag to move, right-click to lock. If EllesmereUI is loaded, the tracker also registers with its unlock mode and uses its accent color and font.
- **Planner (`/pt60`):** five pages:
  - Overview: stat cards and a month calendar with the level you should be at each day; click a day to mark it off, Shift-click to make it the deadline.
  - Goal & schedule.
  - History: plan-vs-actual chart and a daily log.
  - Characters: every character's level, goal and status.
  - Settings.
- **LDB feed:** for Titan Panel, ElvUI or EllesmereUI data bars, if one of them is installed.
- **Commands:** `/pt60 goal 60 12/12/2026`, `/pt60 afk 30`, `/pt60 time 1.5`, `/pt60 status`, `/pt60 tracker`, `/pt60 lock`, `/pt60 export`, `/pt60 import`.

## JSON export

Settings → Export JSON, or `/pt60 export`, opens a text box with the JSON for this character or all characters, already selected, so you can Ctrl+C and paste it anywhere. Import (`/pt60 import`) takes a pasted export and applies its goal and schedule to the current character.

Format: `{ format: "planto60-export", version: 1, exportedAt, characters: [ { name, realm, class, level, xp, totalXP, lastSeen, goal: { level, deadline, mode, setOn, startTotalXP }, schedule: { hoursPerWeekday: { monday… }, offDays: [] }, history: [ { date, level, startTotalXP, gained, target, hit } ] } ] }`

## Install

From CurseForge, or download the zip from the GitHub releases and extract the `planTo60` folder into `World of Warcraft/_forever_/Interface/AddOns/` (or `_classic_era_`).

## Develop

The addon files live at the repo root, so the repo itself is the addon folder.

```sh
tools/install.sh          # symlink the repo into AddOns/planTo60 for every Forever/Classic install; /reload picks up edits
tools/install.sh --copy   # copy the addon files instead
lua5.1 tests/run.lua      # plan math, pace, JSON, export/import
lua5.1 tests/smoke.lua    # whole addon against a mocked WoW API
```

`tools/install.sh` looks under `$WOW_DIR` (or pass the WoW folder as an argument).

## Release

Push a version tag and GitHub Actions runs the tests, then builds the zip with the [BigWigs packager](https://github.com/BigWigsMods/packager) and attaches it to a GitHub release:

```sh
git tag v1.0.0 && git push origin v1.0.0
```

Uploading to CurseForge as well needs two things, once: the project ID in `planTo60.toc` (`## X-Curse-Project-ID: 123456`) and a CurseForge API token stored as the repo secret `CF_API_KEY`.

## License

MIT
