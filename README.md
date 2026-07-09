# 🐿️ Squirrel Trap

A tiny macOS menu-bar app that catches you right before you get distracted.

Every time you press **Cmd+Tab**, Squirrel Trap pops up a small floating prompt asking "what are you about to do?" — the moment right before a keyboard-driven app switch is exactly when it's easiest to get sidetracked chasing something unrelated. It also keeps a running checklist of what you said, so you can check things off as you actually get to them.

## Download

**[⬇ Download Squirrel Trap (latest release)](../../releases/latest)**

Unzip it and drag `Squirrel Trap.app` anywhere you like (your Applications folder, or just your Desktop — it doesn't matter). It's signed with a Developer ID certificate and notarized by Apple, so it just opens normally — no security warnings, no workarounds needed.

## First launch

Squirrel Trap needs **Input Monitoring** permission to detect the Cmd+Tab keypress — it's a passive, listen-only observation and never records anything else you type. The app will show you a one-time explainer with a "Grant Access" button.

If it doesn't show up automatically in **System Settings → Privacy & Security → Input Monitoring**, click the **+** button there and add `Squirrel Trap.app` manually, then toggle it on.

## What it does with your data

Nothing leaves your Mac. Everything you log is stored locally at `~/Library/Application Support/SquirrelTrap/`. There's no account, no server, no syncing.

## Feedback

This is an early, personal project — if something breaks or feels off, that's genuinely useful to know. Let me know directly.

## Notes

Conceived by human, coded by Claude, logo design by ChatGPT
