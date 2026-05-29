<div align="center">

# chrono

**Unified time scheduler for Luau on Roblox.**

One API for delays, intervals, fixed-rate ticks, and per-frame callbacks — with scoped lifecycle, pause, time-scale, and a built-in profiler.

![version](https://img.shields.io/badge/version-0.1.0-blue)
[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![CI](https://github.com/iamthebestts/chrono/actions/workflows/ci.yml/badge.svg)](https://github.com/iamthebestts/chrono/actions/workflows/ci.yml)

<br/>

[<img src=".github/assets/link-wally.svg" height="32" alt="Install with Wally" />](https://wally.run/package/iamthebestts/chrono)
&nbsp;&nbsp;
[<img src=".github/assets/link-creator-store.svg" height="32" alt="Get on Creator Store" />](https://create.roblox.com/store)

<br/>

[Documentation](https://iamthebestts.github.io/chrono) ·
[API Reference](https://iamthebestts.github.io/chrono/api/Chrono) ·
[Changelog](https://iamthebestts.github.io/chrono/changelog)

</div>

---

## Why

Roblox gives you `task.delay`, `task.wait`, and `RunService.Heartbeat`. They work, but every non-trivial codebase ends up rebuilding the same things on top: cancellation tokens, scope-based cleanup, pause/resume, time-scaling for slow motion, profiling hot callbacks. **chrono** is that layer, written once.

```lua
local chrono = require(path.to.chrono)

local scope = chrono.scope()

scope:every(5, function()
    print("every 5 seconds")
end)

scope:after(2, function()
    print("once, in 2 seconds")
end)

scope:frame(function(dt)
    camera.CFrame *= CFrame.Angles(0, dt, 0)
end)

-- later: one call cleans up everything
scope:destroy()
```

---

## Features

| Feature | Description |
|---|---|
| **Scoped lifecycle** | All tasks belong to a scope. Destroy the scope and every task inside is cancelled instantly. |
| **`after` / `every`** | One-shot delays and repeating intervals. `every` fires immediately by default (`fireImmediately = false` to skip). |
| **`frame`** | Per-frame callbacks via `RunService.Heartbeat` with wall-clock `dt`. |
| **`tick`** | Fixed-rate simulation loop (e.g. 60 Hz physics) — fires multiple times per frame to catch up. |
| **Pause & resume** | Scope-level and handle-level pause. `frame` still fires with `dt = 0` while scope is paused. |
| **Time-scale** | `scope:setTimeScale(0.5)` for slow motion, `2` for fast-forward. Affects `after`, `every`, `tick` — not `frame`. |
| **maxCatchup** | Cap how many times `tick` fires per frame after a hitch: `scope:tick(60, fn, { maxCatchup = 4 })`. |
| **Error isolation** | A crashing callback never kills other tasks. Optional `onError` handler per scope. |
| **Profiler** | `chrono.profile()` returns per-task count, avg/max/p99 execution time. Ring-buffer backed. |
| **Global controls** | `chrono.pause_all()` / `chrono.resume_all()` — freeze every scope in one call (e.g. pause menu). |
| **Trove compatible** | Scopes expose `Destroy()` so Trove can clean them up automatically. |

---

## Installation

### Wally

Add to your `wally.toml`:

```toml
[dependencies]
chrono = "iamthebestts/chrono@0.1.0"
```

Then run `wally install`.

### pesde

Add to your `pesde.toml`:

```toml
[dependencies]
chrono = { name = "iamthebestts/chrono", version = "^0.1.0" }
```

Then run `pesde install`.

### Roblox model

Grab the `.rbxm` from [Releases](https://github.com/iamthebestts/chrono/releases) or the [Creator Store](https://create.roblox.com/store) and drop it into `ReplicatedStorage`.

---

## Quick start

```lua
local chrono = require(ReplicatedStorage.Packages.chrono)

-- 1. Create a scope
local scope = chrono.scope()

-- 2. Run something once after a delay
scope:after(3, function()
    print("3 seconds later!")
end)

-- 3. Run something every N seconds (fires immediately, then repeats)
local handle = scope:every(5, function()
    print("heartbeat every 5s")
end)

-- 4. Run every frame
scope:frame(function(dt)
    part.Position += Vector3.new(0, speed * dt, 0)
end)

-- 5. Fixed-rate physics at 60 Hz
scope:tick(60, function(dt)
    player.Position += player.Velocity * dt
end)

-- 6. Pause / resume
scope:pause()   -- freezes all timers; frame fires with dt=0
scope:resume()  -- picks up where it left off, no backlog

-- 7. Slow motion
scope:setTimeScale(0.5)

-- 8. Cancel a single task
handle:cancel()

-- 9. Destroy the scope — cancels everything
scope:destroy()
```

---

## API

> Full documentation at **[iamthebestts.github.io/chrono](https://iamthebestts.github.io/chrono)**

### Module

| Method | Description |
|---|---|
| `chrono.scope(config?)` | Create a new scope. Config: `{ timeScale: number?, onError: ((err, name) -> ())? }` |
| `chrono.profile()` | Returns profiling data for all named tasks. |
| `chrono.reset_profiler()` | Clears all profiler data. |
| `chrono.pause_all()` | Pauses every active scope. |
| `chrono.resume_all()` | Resumes every active scope. |

### Scope

| Method | Description |
|---|---|
| `scope:after(delay, fn, config?)` | Schedule `fn` once after `delay` seconds. Returns a `Handle`. |
| `scope:every(interval, fn, config?)` | Schedule `fn` every `interval` seconds. Fires immediately by default (`fireImmediately = false` to skip). Returns a `Handle`. |
| `scope:frame(fn, config?)` | Schedule `fn` every frame with `dt`. Returns a `Handle`. |
| `scope:tick(hz, fn, config?)` | Schedule `fn` at fixed `hz` rate. Config accepts `maxCatchup`. Returns a `Handle`. |
| `scope:pause()` | Freeze all tasks. `frame` still fires with `dt = 0`. |
| `scope:resume()` | Unfreeze all tasks. No backlog. |
| `scope:setTimeScale(scale)` | Multiply time for `after`/`every`/`tick`. Negative values are clamped to `0`. Does **not** affect `frame`. |
| `scope:destroy()` | Permanently cancel all tasks. Trove-compatible via `Destroy()`. |

| Property | Type | Description |
|---|---|---|
| `scope.timeScale` | `number` | Current time multiplier (read-only). |
| `scope.isPaused` | `boolean` | Whether the scope is paused (read-only). |
| `scope.isDestroyed` | `boolean` | Whether the scope has been destroyed (read-only). |
| `scope.elapsedTime` | `number` | Accumulated scaled time (read-only). |

### Handle

| Method | Description |
|---|---|
| `handle:cancel()` | Remove task from schedule. Handle becomes invalid. |
| `handle:pause()` | Freeze this task individually. Cumulative with scope pause. |
| `handle:resume()` | Unfreeze this task. |
| `handle:setInterval(interval)` | Change interval (`every`/`tick` only). Resets accumulator. |
| `handle:isPaused()` | Returns handle-level pause state (not scope). |
| `handle:isCancelled()` | Returns whether the handle has been cancelled. |

### Config

All scheduling methods accept an optional config table:

```lua
scope:after(1, fn, { name = "respawn_timer" })
scope:tick(60, fn, { name = "physics", maxCatchup = 4 })
```

| Field | Applies to | Description |
|---|---|---|
| `name` | all | Label for the profiler. Default: `"<anonymous>"`. |
| `maxCatchup` | `tick` | Max fires per frame during catch-up. Default: unlimited. |
| `fireImmediately` | `every` | Fire once on registration before the first interval. Default: `true`. |

---

## Profiler

```lua
local data = chrono.profile()

for name, entry in data do
    print(name, "avg:", entry.avgMs, "max:", entry.maxMs, "p99:", entry.p99Ms)
end

-- entry shape:
-- {
--     name: string,
--     count: number,
--     avgMs: number,
--     maxMs: number,
--     p99Ms: number,
--     totalMs: number,
-- }

chrono.reset_profiler() -- clear all data
```

---

## Integration

### With Trove

```lua
local trove = Trove.new()
local scope = chrono.scope()

trove:Add(scope) -- Trove calls scope:Destroy() on cleanup
```

### With Signals

```lua
local scope = chrono.scope()

scope:every(5, function()
    mySignal:Fire("tick")
end)
```

### Alongside RunService

chrono uses a single `RunService.Heartbeat` connection internally. Your own connections work independently — no conflicts.

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for setup, conventions, and workflow.

---

## License

Released under the [MIT License](LICENSE).
