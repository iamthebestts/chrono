# Contributing to chrono

`chrono` is a unified time scheduler for Luau on Roblox. Contributions are welcome — please read this guide end-to-end before opening a PR.

---

## Quick start

```powershell
aftman install                # install toolchain pinned in aftman.toml
.\scripts\install.ps1         # wally install + type generation
.\scripts\install-hooks.ps1   # install pre-commit hooks
.\scripts\build.ps1           # verify it builds
.\scripts\tests.ps1           # verify tests pass
```

If all succeed, you're ready to start.

---

## Toolchain

All tooling is pinned via [Aftman](https://github.com/LPGhatguy/aftman). Running `aftman install` provisions the exact versions declared in `aftman.toml`:

| Tool       | Version                  | Purpose                       |
|------------|--------------------------|-------------------------------|
| `lute`     | `0.1.0-nightly.20260408` | Build, analyze, and run tests |
| `rojo`     | `7.5.1`                  | Roblox project sync           |
| `wally`    | `0.3.2`                  | Package manager               |
| `selene`   | `0.29.0`                 | Luau linter                   |
| `stylua`   | `2.0.1`                  | Luau formatter                |
| `luau-lsp` | `1.53.3`                 | Language server for VS Code   |

Do not install these tools globally outside Aftman — version drift between contributors will produce noisy diffs and inconsistent CI behaviour.

---

## Setup

### 1. Install Aftman tools

```sh
aftman install
```

### 2. Install Wally dependencies

```powershell
.\scripts\install.ps1
```

This wraps `wally install` and generates package types so `luau-lsp` resolves them.

### 3. Create `.env`

`build.ps1` and `tests.ps1` load environment variables from a `.env` file at the repo root. Create it with:

```env
ROBLOX_API_KEY=your_key
ROBLOX_PLACE_ID=your_place_id
ROBLOX_UNIVERSE_ID=your_universe_id
```

These are required because `lute tests` round-trips through Roblox Open Cloud to execute the test place.

### 4. Open in VS Code

`luau-lsp` and `stylua` activate automatically from `.vscode/settings.json`. No further configuration is needed.

---

## Scripts

All day-to-day tasks have a PowerShell wrapper in `scripts/`. **Use these instead of calling the underlying tools directly** — they handle `.env` loading and path normalization for you.

| Script                | What it runs                              |
|-----------------------|-------------------------------------------|
| `scripts/install.ps1` | `wally install`                           |
| `scripts/build.ps1`   | Loads `.env`, then `lute build`           |
| `scripts/analyze.ps1` | `lute analyze`                            |
| `scripts/tests.ps1`   | Loads `.env`, then `lute tests`           |

---

## Project structure

```txt
chrono/
├── src/
│   ├── init.luau          ← library entry point
│   ├── jest.config.lua    ← Jest configuration
│   └── __tests__/         ← all test files (*.test.luau)
├── scripts/
│   ├── install.ps1        ← wally install
│   ├── build.ps1          ← lute build (loads .env)
│   ├── analyze.ps1        ← lute analyze
│   ├── tests.ps1          ← lute tests (loads .env)
│   ├── processExecution.luau
│   ├── test.lua
│   └── tests.json
├── .lute/
│   └── tests.luau         ← lute test task definition
├── .github/
│   └── workflows/
│       └── ci.yml         ← CI pipeline (build → analyze → test)
├── .vscode/
│   └── settings.json      ← luau-lsp, stylua, sourcemap config
├── default.project.json   ← Rojo project for the library
├── test.project.json      ← Rojo project for running tests
├── aftman.toml            ← toolchain declarations
├── wally.toml             ← package manifest
├── selene.toml            ← linter config
├── stylua.toml            ← formatter config
└── .luaurc                ← Luau language config (aliases, strict mode)
```

---

## Git hooks

Pre-commit hooks are installed via `.\scripts\install-hooks.ps1`. They run automatically before each commit and validate:

- **stylua** — code formatting
- **selene** — linting rules
- **luau-lsp** — type safety

If any check fails, the commit is blocked. Fix the issues and try again:

```powershell
stylua src/    # auto-format code
selene src     # check lint rules
```

To bypass hooks temporarily (not recommended):

```bash
git commit --no-verify
```

---

## Code style

All Luau files **must** begin with `--!strict`. No exceptions.

**Naming conventions:**

- `PascalCase` — types and interfaces
- `camelCase` — variables, functions, and module fields
- `SCREAMING_SNAKE_CASE` — module-level constants

**Rules:**

- Never use `any` — all types must be explicit
- No `print()` in production code (anywhere in `src/` outside `__tests__/`)
- Modules must return a table or a single typed value — no side effects at `require` time

Format and lint before committing:

```sh
stylua src/
selene src/
```

Both run in CI and will block your PR if they fail.

---

## Running tests

```powershell
.\scripts\tests.ps1
```

This loads your `.env` and runs `lute tests`. Tests live in `src/__tests__/` and follow the `*.test.luau` naming convention, using the Jest-style API (`describe`, `it`/`test`, `expect`).

**Writing tests:**

```luau
--!strict
local chrono = require(script.Parent.Parent) -- path from src/__tests__/

return function()
    describe("chrono.after", function()
        it("invokes the callback once after the given delay", function()
            local fired = 0
            chrono.after(0.05, function()
                fired += 1
            end)

            task.wait(0.1)
            expect(fired).toBe(1)
        end)
    end)
end
```

**Test conventions:**

- One `describe` block per module or public function
- Each `it` block covers exactly one behaviour
- Any new public API must ship with tests in the same PR

---

## Commits

Follow [Conventional Commits](https://www.conventionalcommits.org/). All messages must be in **English**.

| Prefix      | When to use                                      |
|-------------|--------------------------------------------------|
| `feat:`     | New function, method, or API change              |
| `fix:`      | Bug fix                                          |
| `test:`     | Adding or updating tests                         |
| `refactor:` | Internal change with no behaviour difference     |
| `docs:`     | README, CONTRIBUTING, or inline documentation    |
| `chore:`    | Tooling, config, dependencies                    |
| `ci:`       | Changes to `.github/workflows/`                  |

**Examples:**

```txt
feat: add chrono.every for recurring tasks
fix: cancellation token leaking after scheduler.destroy
test: cover chrono.after firing exactly once
chore: bump stylua to 2.0.1
```

Do **not** use scopes (e.g. `feat(core):`) — unnecessary at this project's size.

---

## Pull requests

- **One concern per PR.** Split unrelated changes into separate PRs.
- Branch off `main`, target `main`.
- Suggested naming: `feat/recurring-tasks`, `fix/cancel-leak`, `docs/contributing`.
- Before requesting review, **all** of the following must pass locally:

```powershell
.\scripts\build.ps1    # no build errors
.\scripts\analyze.ps1  # no type errors
.\scripts\tests.ps1    # all tests green
```

- If your PR adds a new public API, update `README.md` to reflect it.
- CI runs the same checks automatically on every push and PR against `main`.
