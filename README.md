# Overhead

See what each project costs your Mac.

Overhead is a free, open-source menu bar app for developers. Activity Monitor lists hundreds of processes; Overhead
adds them up by the git checkout they run from, so `node`, `xcodebuild` and a Python server show up as one line:
"my-app, 6.1 GB".

## Status: 0.2, early

Working now:

- Memory in use in the menu bar, with memory pressure and swap. On battery, the menu bar also shows how long the
  battery lasts at your current pace.
- Memory and CPU per project. A process counts toward the deepest git checkout its working directory is in, so a
  worktree gets its own row. Checkouts are found up to two folders below your home folder, plus agent worktrees in
  `.claude/worktrees/`.
- Battery time at this pace: remaining watt-hours divided by your average draw over the last 10 minutes. It starts
  over when you unplug, so it follows how you work now rather than the last hour.

CPU per project is also the best guide to which project drains the battery: macOS does not report power per
process.

Planned:

- Keep the Mac awake while a build, deploy or coding agent runs, and let it sleep when they finish.
- Ports and dev servers per project, with a Stop button.
- Booted simulators and the memory they hold.
- Park a project: stop its servers and simulators in one click, and start them again later. Parking never deletes
  files.

## Build

Requires macOS 14 or later and Xcode 15 or later.

```bash
swift test                  # OverheadCore tests
./scripts/build-app.sh      # builds build/Overhead.app
open build/Overhead.app
```

## Privacy

Overhead reads process names, memory figures and working directories on your Mac. It sends nothing anywhere: no
account, no analytics, no network access.

## From the same developer

- [DevSweeper](https://devsweeper.com): finds disk space you can safely reclaim from caches, build output,
  simulators and old worktrees.
- AgentNod: answer your coding agents' permission prompts from a HUD, a notification or your phone.

## License

MIT. See `LICENSE`.
