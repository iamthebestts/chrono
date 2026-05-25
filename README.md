# chrono

![status](https://img.shields.io/badge/status-scaffold-lightgrey)
[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)

> **This is the initial scaffolding commit.** No working implementation exists yet — only tooling, project structure, and the design intent below. The first feature commits come next.

Unified time scheduler for Luau — tasks, intervals, scopes, profiling.

---

## Why

Roblox gives you `task.delay`, `task.wait`, and `RunService.Heartbeat`. They work, but every non-trivial codebase ends up rebuilding the same things on top: cancellation, scopes, pause, profiling. `chrono` will be that layer, written once.

---

## Planned API

The shape below is the design target — not what runs today.

```lua
local chrono = require(path.to.chrono)

local scope = chrono.scope()

scope:every(5, function()
    print("every 5 seconds")
end)

scope:after(2, function()
    print("once, in 2 seconds")
end)

-- later
scope:destroy() -- cancels everything above
```

---

## Planned features

- `after`, `every`, `frame`, `tick` — one mental model for all time-based work
- scopes that cancel everything they own in a single call
- per-scope pause and time-scale (bullet time, slow motion, freeze on pause menu)
- fixed-rate `tick` independent of frame rate
- built-in profiler — find which task is eating your frame budget
- integrates with Trove, Promise, Signal — not a replacement for any of them

---

## Status

Scaffold only. There is no installable release. The first tagged version will be `0.1.0` once the core scheduler lands.

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for the toolchain and workflow already wired up in this repo.

---

## License

Released under the [MIT License](LICENSE).
