# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-05-28

### Added

- **Scopes** — `chrono.scope(config?)` creates independent lifecycle containers for scheduled work.
- **`scope:after(delay, fn, config?)`** — one-shot delayed execution.
- **`scope:every(interval, fn, config?)`** — repeating interval with immediate first run.
- **`scope:frame(fn, config?)`** — per-frame callback via `RunService.Heartbeat` with wall-clock `dt`.
- **`scope:tick(hz, fn, config?)`** — fixed-rate simulation loop, fires multiple times per frame to catch up.
- **Handles** — all scheduling methods return a `Handle` with `cancel()`, `pause()`, `resume()`, `setInterval()`, `isPaused()`, `isCancelled()`.
- **Scope pause/resume** — `scope:pause()` freezes all timers; `frame` still fires with `dt = 0`. No backlog on resume.
- **Time-scale** — `scope:setTimeScale(scale)` for slow motion / fast-forward. Affects `after`, `every`, `tick` — not `frame`.
- **`maxCatchup`** — optional cap on tick fires per frame via config: `scope:tick(60, fn, { maxCatchup = 4 })`. Discards excess accumulation after a hitch.
- **Error isolation** — callback errors are caught with `pcall` and never propagate to other tasks or scopes.
- **`onError` handler** — configurable per scope: `chrono.scope({ onError = function(err, name) ... end })`. Errors are silently swallowed when no handler is set.
- **Profiler** — `chrono.profile()` returns per-task `count`, `avgMs`, `maxMs`, `p99Ms`, `totalMs`. Ring-buffer backed (128 samples) for bounded memory.
- **`chrono.reset_profiler()`** — clears all profiler data.
- **`chrono.pause_all()` / `chrono.resume_all()`** — freeze or unfreeze every active scope in one call.
- **Trove compatibility** — scopes expose `Destroy()` as an alias for `destroy()`.
- **Nested task safety** — tasks created during callback execution are deferred to the next frame.
- **Self-cancellation** — a task can safely cancel itself or destroy its parent scope mid-callback.

[0.1.0]: https://github.com/iamthebestts/chrono/releases/tag/v0.1.0
