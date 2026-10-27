# Overhead

See what each project costs your Mac.

Overhead is a free, open-source menu bar app for developers. Activity Monitor lists hundreds of processes; Overhead
adds them up by the git checkout they run from, so `node`, `xcodebuild` and a Python server show up as one line:
"my-app, 6.1 GB".

## Status: 0.4, early

Working now:

- Memory in use in the menu bar, with memory pressure and swap. On battery, the menu bar also shows how long the
  battery lasts at your current pace.
- Memory and CPU per project. A process counts toward the deepest git checkout its working directory is in, so a
  worktree gets its own row. Checkouts are found up to two folders below your home folder, plus agent worktrees in
  `.claude/worktrees/`.
- Battery time at this pace: remaining watt-hours divided by your average draw over the last 10 minutes. It starts
  over when you unplug, so it follows how you work now rather than the last hour.

- Keep awake: Off, On, or Auto. Auto holds while a build tool or coding agent is actually working (above a quarter
  of one core), or while a project is busy, and lets go two minutes after the work stops. An idle agent session or
  a dev server waiting for requests does not keep your Mac up. The display can still sleep, and closing the lid on
  battery still sleeps the Mac. A cup appears in the menu bar while it holds; `pmset -g assertions` lists it as
  "Overhead: <reason>".
- Ports: dev servers listening in your projects, plus databases and Docker running outside them, each with a Stop
  button that sends a polite quit signal (SIGTERM) after you confirm. Other apps' listeners (AirPlay, Spotify) are
  only counted.

- Simulators: every booted simulator with its runtime, when it booted, how many processes it runs, and the memory
  and CPU of all of them together, with a Shut Down button (`xcrun simctl shutdown`; the device and its data stay).
  A booted iOS simulator runs close to 300 processes, so an idle one left open for a day can hold many gigabytes,
  much of it compressed or in swap.

CPU per project is also the best guide to which project drains the battery: macOS does not report power per
process. Memory per project and per simulator is the sum of each process's footprint, the figure Activity Monitor
shows; it includes compressed memory, so the parts can add up to more than "in use".

Planned:

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
