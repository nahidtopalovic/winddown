# Winddown

A macOS menu bar app that ends your workday at 6pm without locking you out of your laptop.

The laptop stays usable for personal stuff. Only work apps (VS Code, Claude by default) get quit and kept closed until morning.

## How it works

- **5:30pm** — menu bar icon turns amber, countdown appears.
- **5:45pm** — notification: 15 minutes left, start wrapping up.
- **6:00pm** — a panel takes over: it shows today's Claude Code sessions (read from `~/.claude/projects`) and asks two questions — *what did I finish* and *what's first tomorrow*. Answers are saved to a daily markdown note in `~/Documents/winddown/`.
- **After 6pm** — blocked apps are quit; relaunching them quits them again with a notification. Everything else works normally. Ends at 5am.

## Escape hatches

- **Work late…** — type a reason, pick 30/60/120 min. The reason is logged into the daily note, so late nights leave a trail.
- **Pause until tomorrow** — full off switch for real emergencies, from the menu.

## Build

```bash
./build.sh
open build/Winddown.app        # or: cp -R build/Winddown.app /Applications/
```

Swift Package Manager only — no Xcode project. Requires macOS 14+.

## Configure

Settings window (menu bar icon → Settings…): cutoff time, ramp/warning lead, blocked-until time, weekdays only, blocklist (bundle ids), note directory, launch at login.

Find an app's bundle id:

```bash
osascript -e 'id of app "AppName"'
```

## Notes

- Blocking is intentionally soft: it targets GUI apps by bundle id. Terminal `claude` processes are not killed (too risky mid-write). The point is friction plus ritual, not a jail.
- App termination is polite first (apps get their save dialogs), forced only after 10 seconds.
