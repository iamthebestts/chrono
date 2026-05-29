--!strict

local RunService: any = nil

-- Constants

local PROFILER_BUFFER_SIZE = 128

-- Internal types

type HandleType = "after" | "every" | "frame" | "tick"

type HandleData = {
	_type: HandleType,
	_fn: (...any) -> ...any,
	_scopeData: ScopeData,
	_isPaused: boolean,
	_isCancelled: boolean,
	_name: string,
	_interval: number,
	_accumulated: number,
	_creationOrder: number,
	_firstRun: boolean,
	_maxCatchup: number,
}

type ScopeData = {
	_isPaused: boolean,
	_isDestroyed: boolean,
	_timeScale: number,
	_elapsedTime: number,
	_tickHandles: { HandleInternal },
	_frameHandles: { HandleInternal },
	_timerHandles: { HandleInternal },
	_pendingTick: { HandleInternal },
	_pendingFrame: { HandleInternal },
	_pendingTimer: { HandleInternal },
	_isProcessing: boolean,
	_onError: ((err: string, name: string) -> ())?,
}

type HandleInternal = typeof(setmetatable({} :: { _data: HandleData }, {}))
type ScopeInternal = typeof(setmetatable({} :: { _data: ScopeData }, {}))

type ProfileSamplesData = {
	name: string,
	count: number,
	totalMs: number,
	maxMs: number,
	samples: { number },
	_head: number,
	_size: number,
}

-- Module state

local allScopes: { ScopeInternal } = {}
local profilerData: { [string]: ProfileSamplesData } = {}
local nextCreationOrder = 0
local heartbeatConnection: RBXScriptConnection? = nil
local manualMode = false

-- Profiler helpers

local function recordSample(name: string, durationMs: number)
	local entry = profilerData[name]
	if not entry then
		entry = {
			name = name,
			count = 0,
			totalMs = 0,
			maxMs = 0,
			samples = table.create(PROFILER_BUFFER_SIZE, 0),
			_head = 0,
			_size = 0,
		}
		profilerData[name] = entry
	end

	entry.count += 1
	entry.totalMs += durationMs
	if durationMs > entry.maxMs then
		entry.maxMs = durationMs
	end

	local head = entry._head % PROFILER_BUFFER_SIZE + 1
	entry.samples[head] = durationMs
	entry._head = head
	if entry._size < PROFILER_BUFFER_SIZE then
		entry._size += 1
	end
end

local function computeP99(entry: ProfileSamplesData): number
	local n = entry._size
	if n == 0 then
		return 0
	end
	local valid = table.create(n)
	for i = 1, n do
		valid[i] = entry.samples[i]
	end
	table.sort(valid)
	local idx = math.ceil(n * 0.99)
	return valid[idx]
end

-- Callback invocation with error isolation

local function invokeCallback(hData: HandleData, ...: any)
	local startTime = os.clock()
	local ok, err = pcall(hData._fn, ...)
	local elapsed = (os.clock() - startTime) * 1000
	recordSample(hData._name, elapsed)
	if not ok then
		local onError = hData._scopeData._onError
		if onError then
			onError(tostring(err), hData._name)
		end
	end
end

-- Handle

--[=[
	@class Handle

	A reference to a single scheduled task, returned by Scope scheduling methods.

	Use a Handle to cancel, pause, resume, or reconfigure a task after scheduling.
	A Handle becomes invalid when `:cancel()` is called or when the parent Scope
	is destroyed. Calling any method on an invalid Handle throws an error.

	```lua
	local handle = scope:every(5, function()
		print("tick")
	end)

	handle:pause()
	handle:setInterval(10)
	handle:resume()
	handle:cancel()
	```
]=]
local HandleMethods = {}
local HandleMeta = { __index = HandleMethods }

local function assertHandleAlive(data: HandleData)
	if data._scopeData._isDestroyed then
		error("[chrono] Parent scope is destroyed", 3)
	end
	if data._isCancelled then
		error("[chrono] Handle is cancelled", 3)
	end
end

--[=[
	@within Handle

	Removes this task from the schedule permanently. The Handle becomes invalid
	immediately and cannot be paused, resumed, or cancelled again.

	@error "Handle is already cancelled" -- Thrown if called on an already-cancelled Handle.
	@error "Parent scope is destroyed" -- Thrown if the parent Scope was destroyed.
]=]
function HandleMethods.cancel(self: HandleInternal)
	local data = self._data
	if data._scopeData._isDestroyed then
		error("[chrono] Parent scope is destroyed", 2)
	end
	if data._isCancelled then
		error("[chrono] Handle is already cancelled", 2)
	end
	data._isCancelled = true
end

--[=[
	@within Handle

	Pauses execution of this individual task. The task will not fire while paused,
	regardless of the parent Scope's own pause state.

	Calling `pause()` on an already-paused Handle is a no-op.

	@error "Handle is cancelled" -- Thrown if the Handle is invalid.
	@error "Parent scope is destroyed" -- Thrown if the parent Scope was destroyed.
]=]
function HandleMethods.pause(self: HandleInternal)
	assertHandleAlive(self._data)
	self._data._isPaused = true
end

--[=[
	@within Handle

	Resumes execution of this task after `handle:pause()`. If the parent Scope is
	also paused, the task will not fire until the Scope is resumed as well.

	@error "Handle is cancelled" -- Thrown if the Handle is invalid.
	@error "Parent scope is destroyed" -- Thrown if the parent Scope was destroyed.
]=]
function HandleMethods.resume(self: HandleInternal)
	assertHandleAlive(self._data)
	self._data._isPaused = false
end

--[=[
	@within Handle

	Changes the execution interval for `every` or `tick` tasks. The accumulated
	time resets, so the next execution happens `interval` seconds from this call.

	:::caution
	Only valid for Handles created with `scope:every()` or `scope:tick()`. Calling
	this on an `after` or `frame` Handle throws an error.
	:::

	@param interval number -- New interval in seconds.
	@error "setInterval is only valid for 'every' and 'tick' handles" -- Thrown for incompatible handle types.
	@error "Handle is cancelled" -- Thrown if the Handle is invalid.
	@error "Parent scope is destroyed" -- Thrown if the parent Scope was destroyed.
]=]
function HandleMethods.setInterval(self: HandleInternal, interval: number)
	local data = self._data
	assertHandleAlive(data)
	if data._type ~= "every" and data._type ~= "tick" then
		error("[chrono] setInterval is only valid for 'every' and 'tick' handles", 2)
	end
	data._interval = interval
	data._accumulated = 0
end

--[=[
	@within Handle

	Returns whether this individual task is paused. Does **not** account for the
	parent Scope's pause state — only reflects whether `handle:pause()` was called.

	@return boolean
]=]
function HandleMethods.isPaused(self: HandleInternal): boolean
	return self._data._isPaused
end

--[=[
	@within Handle

	Returns whether this task has been cancelled.

	@return boolean
	@error "Parent scope is destroyed" -- Thrown if the parent Scope was destroyed.
]=]
function HandleMethods.isCancelled(self: HandleInternal): boolean
	local data = self._data
	if data._scopeData._isDestroyed then
		error("[chrono] Parent scope is destroyed", 2)
	end
	return data._isCancelled
end

-- Scope

--[=[
	@class Scope

	A container for scheduled work. All tasks within a Scope share the same
	lifecycle: pausing, resuming, or destroying the Scope affects every task
	registered to it.

	Created via `chrono.scope()`.

	```lua
	local scope = chrono.scope({ timeScale = 0.5 })

	scope:tick(60, function(dt)
		player.position += player.velocity * dt
	end)

	scope:after(10, function()
		scope:destroy() -- cleans up all tasks at once
	end)
	```
]=]

--[=[
	@prop timeScale number
	@within Scope
	@readonly

	The current time multiplier for this Scope. Affects how fast `after`, `every`,
	and `tick` tasks advance. Defaults to `1.0`. Modify via `setTimeScale()`.
]=]

--[=[
	@prop isPaused boolean
	@within Scope
	@readonly

	Whether this Scope is currently paused.
]=]

--[=[
	@prop isDestroyed boolean
	@within Scope
	@readonly

	Whether this Scope has been permanently destroyed. A destroyed Scope cannot
	be used and all its child Handles are invalid.
]=]

--[=[
	@prop elapsedTime number
	@within Scope
	@readonly

	Total time elapsed in this Scope in seconds, scaled by `timeScale`. Does not
	advance while the Scope is paused.
]=]
local ScopeMethods = {}
local ScopeMeta = {}

ScopeMeta.__index = function(self: any, key: string): any
	if key == "timeScale" then
		return self._data._timeScale
	end
	if key == "isPaused" then
		return self._data._isPaused
	end
	if key == "isDestroyed" then
		return self._data._isDestroyed
	end
	if key == "elapsedTime" then
		return self._data._elapsedTime
	end
	return (ScopeMethods :: any)[key]
end

local function assertScopeAlive(data: ScopeData)
	if data._isDestroyed then
		error("[chrono] Scope is destroyed", 3)
	end
end

local function createHandle(
	scopeData: ScopeData,
	handleType: HandleType,
	fn: (...any) -> ...any,
	config: { name: string?, maxCatchup: number? }?,
	interval: number
): HandleInternal
	nextCreationOrder += 1

	local data: HandleData = {
		_type = handleType,
		_fn = fn,
		_scopeData = scopeData,
		_isPaused = false,
		_isCancelled = false,
		_name = if config and config.name then config.name else "<anonymous>",
		_interval = interval,
		_accumulated = 0,
		_creationOrder = nextCreationOrder,
		_firstRun = handleType == "every",
		_maxCatchup = if config and config.maxCatchup then config.maxCatchup else math.huge,
	}

	local handle = setmetatable({ _data = data }, HandleMeta) :: any
	table.freeze(handle)

	local targetList: { HandleInternal }
	if handleType == "tick" then
		targetList = if scopeData._isProcessing then scopeData._pendingTick else scopeData._tickHandles
	elseif handleType == "frame" then
		targetList = if scopeData._isProcessing then scopeData._pendingFrame else scopeData._frameHandles
	else
		targetList = if scopeData._isProcessing then scopeData._pendingTimer else scopeData._timerHandles
	end
	table.insert(targetList, handle)

	return handle
end

--[=[
	@within Scope

	Schedules a function to execute once after `delay` seconds. The Handle is
	automatically cancelled after the function runs.

	@param delay number -- Delay in seconds. Values ≤ 0 execute on the next frame.
	@param fn () -> () -- The function to execute.
	@param config {name: string?}? -- Optional configuration table.
	@return Handle
]=]
function ScopeMethods.after(
	self: ScopeInternal,
	delay: number,
	fn: () -> (),
	config: { name: string?, maxCatchup: number? }?
): HandleInternal
	assertScopeAlive(self._data)
	if delay < 0 then
		delay = 0
	end
	return createHandle(self._data, "after", fn :: any, config, delay)
end

--[=[
	@within Scope

	Schedules a function to execute immediately and then repeatedly every `interval`
	seconds. Respects the Scope's `timeScale`.

	@param interval number -- Time between executions in seconds.
	@param fn () -> () -- The function to execute.
	@param config {name: string?}? -- Optional configuration table.
	@return Handle
]=]
function ScopeMethods.every(
	self: ScopeInternal,
	interval: number,
	fn: () -> (),
	config: { name: string?, maxCatchup: number? }?
): HandleInternal
	assertScopeAlive(self._data)
	return createHandle(self._data, "every", fn :: any, config, interval)
end

--[=[
	@within Scope

	Schedules a function to execute every frame via `RunService.Heartbeat`. Unlike
	other task types, `frame` tasks always fire even when the Scope is paused —
	they receive `dt = 0` instead of the real frame delta.

	Tasks run in order of creation, after all `tick` tasks for the frame.

	@param fn (dt: number) -> () -- Called each frame. `dt` is the frame delta in seconds, or `0` when the Scope is paused.
	@param config {name: string?}? -- Optional configuration table.
	@return Handle
]=]
function ScopeMethods.frame(
	self: ScopeInternal,
	fn: (dt: number) -> (),
	config: { name: string?, maxCatchup: number? }?
): HandleInternal
	assertScopeAlive(self._data)
	return createHandle(self._data, "frame", fn :: any, config, 0)
end

--[=[
	@within Scope

	Schedules a function to execute at a fixed frequency, independent of frame rate.
	If the frame rate drops below `hz`, the function fires multiple times per frame
	to compensate. Respects the Scope's `timeScale`.

	Tasks run in order of creation, before all `frame` tasks for the frame.

	@param hz number -- Target executions per second (e.g. `60` for 60 hz).
	@param fn (dt: number) -> () -- Called with a fixed delta of `1/hz` on each tick.
	@param config {name: string?, maxCatchup: number?}? -- Optional configuration. `maxCatchup` caps how many times the task can fire in a single frame, preventing hitches after freezes (default: unlimited).
	@return Handle
]=]
function ScopeMethods.tick(
	self: ScopeInternal,
	hz: number,
	fn: (dt: number) -> (),
	config: { name: string?, maxCatchup: number? }?
): HandleInternal
	assertScopeAlive(self._data)
	return createHandle(self._data, "tick", fn :: any, config, 1 / hz)
end

--[=[
	@within Scope

	Pauses all tasks in this Scope. Timers do not advance while paused. `frame`
	tasks still fire each frame but receive `dt = 0`.

	Calling `pause()` on an already-paused Scope is a no-op.
]=]
function ScopeMethods.pause(self: ScopeInternal)
	assertScopeAlive(self._data)
	self._data._isPaused = true
end

--[=[
	@within Scope

	Resumes all tasks in this Scope after a pause. No time is backfilled — timers
	continue from where they were when the Scope was paused.

	@error "Scope is destroyed" -- Thrown if the Scope was destroyed.
]=]
function ScopeMethods.resume(self: ScopeInternal)
	assertScopeAlive(self._data)
	self._data._isPaused = false
end

--[=[
	@within Scope

	Sets the time multiplier for this Scope. Affects how fast `after`, `every`, and
	`tick` tasks advance. `frame` tasks always receive wall-clock `dt` regardless.

	| `scale` | Effect |
	| ------- | ------ |
	| `1.0`   | Normal speed (default) |
	| `0.5`   | Half speed — slow motion |
	| `2.0`   | Double speed — fast-forward |
	| `0`     | Freezes time (distinct from `pause()`) |

	@param scale number -- Time multiplier. Negative values have undefined behavior.
]=]
function ScopeMethods.setTimeScale(self: ScopeInternal, scale: number)
	assertScopeAlive(self._data)
	self._data._timeScale = scale
end

--[=[
	@within Scope

	Permanently destroys this Scope and cancels all its tasks. All child Handles
	become invalid. This operation cannot be undone.

	:::note
	Also available as `scope:Destroy()` for compatibility with [Trove](https://sleitnick.github.io/RbxUtil/api/Trove)
	and similar cleanup utilities.
	:::
]=]
function ScopeMethods.destroy(self: ScopeInternal)
	local data = self._data
	assertScopeAlive(data)
	data._isDestroyed = true

	for _, handle in data._tickHandles do
		handle._data._isCancelled = true
	end
	for _, handle in data._frameHandles do
		handle._data._isCancelled = true
	end
	for _, handle in data._timerHandles do
		handle._data._isCancelled = true
	end
	for _, handle in data._pendingTick do
		handle._data._isCancelled = true
	end
	for _, handle in data._pendingFrame do
		handle._data._isCancelled = true
	end
	for _, handle in data._pendingTimer do
		handle._data._isCancelled = true
	end

	table.clear(data._tickHandles)
	table.clear(data._frameHandles)
	table.clear(data._timerHandles)
	table.clear(data._pendingTick)
	table.clear(data._pendingFrame)
	table.clear(data._pendingTimer)
end

ScopeMethods.Destroy = ScopeMethods.destroy

-- Cleanup helper

local function filterCancelledInPlace(handles: { HandleInternal })
	local write = 1
	for read = 1, #handles do
		if not handles[read]._data._isCancelled then
			handles[write] = handles[read]
			write += 1
		end
	end
	for i = write, #handles do
		handles[i] = nil :: any
	end
end

-- Core step

local function step(dt: number)
	local scopeSnapshot = table.clone(allScopes)

	for _, scope in scopeSnapshot do
		local data = scope._data
		if data._isDestroyed then
			continue
		end

		data._isProcessing = true

		local scopePaused = data._isPaused
		local scaledDt = if scopePaused then 0 else dt * data._timeScale

		if not scopePaused then
			data._elapsedTime += scaledDt
		end

		-- Phase 1: tick handles (fixed-rate, with maxCatchup limit)
		local tickSnapshot = table.clone(data._tickHandles)
		for _, handle in tickSnapshot do
			if data._isDestroyed then
				break
			end
			local hData = handle._data
			if hData._isCancelled or hData._isPaused or scopePaused then
				continue
			end

			hData._accumulated += scaledDt
			local catchupCount = 0
			while hData._accumulated >= hData._interval do
				catchupCount += 1
				if catchupCount > hData._maxCatchup then
					hData._accumulated = 0
					break
				end

				hData._accumulated -= hData._interval
				invokeCallback(hData, hData._interval)

				if data._isDestroyed or hData._isCancelled then
					break
				end
			end
		end

		-- Phase 2: frame handles (once per frame, always fires unless handle-paused)
		if not data._isDestroyed then
			local frameSnapshot = table.clone(data._frameHandles)
			for _, handle in frameSnapshot do
				if data._isDestroyed then
					break
				end
				local hData = handle._data
				if hData._isCancelled or hData._isPaused then
					continue
				end

				local frameDt = if scopePaused then 0 else dt
				invokeCallback(hData, frameDt)
			end
		end

		-- Phase 3: timer handles (after + every)
		if not data._isDestroyed then
			local timerSnapshot = table.clone(data._timerHandles)
			for _, handle in timerSnapshot do
				if data._isDestroyed then
					break
				end
				local hData = handle._data
				if hData._isCancelled or hData._isPaused or scopePaused then
					continue
				end

				if hData._type == "after" then
					hData._accumulated += scaledDt
					if hData._accumulated >= hData._interval then
						invokeCallback(hData)
						hData._isCancelled = true
					end
				elseif hData._type == "every" then
					if hData._firstRun then
						hData._firstRun = false
						invokeCallback(hData)
					else
						hData._accumulated += scaledDt
						while hData._accumulated >= hData._interval do
							hData._accumulated -= hData._interval
							invokeCallback(hData)

							if data._isDestroyed or hData._isCancelled then
								break
							end
						end
					end
				end
			end
		end

		data._isProcessing = false

		-- Flush pending handles added during callbacks
		if not data._isDestroyed then
			for _, handle in data._pendingTick do
				table.insert(data._tickHandles, handle)
			end
			for _, handle in data._pendingFrame do
				table.insert(data._frameHandles, handle)
			end
			for _, handle in data._pendingTimer do
				table.insert(data._timerHandles, handle)
			end
		end
		table.clear(data._pendingTick)
		table.clear(data._pendingFrame)
		table.clear(data._pendingTimer)

		-- Remove cancelled handles (preserves creation order)
		if not data._isDestroyed then
			filterCancelledInPlace(data._tickHandles)
			filterCancelledInPlace(data._frameHandles)
			filterCancelledInPlace(data._timerHandles)
		end
	end

	-- Remove destroyed scopes from global list
	local write = 1
	for read = 1, #allScopes do
		if not allScopes[read]._data._isDestroyed then
			allScopes[write] = allScopes[read]
			write += 1
		end
	end
	for i = write, #allScopes do
		allScopes[i] = nil :: any
	end
end

-- Connection management

local function ensureConnection()
	if heartbeatConnection or manualMode then
		return
	end
	if not RunService then
		RunService = game:GetService("RunService")
	end
	heartbeatConnection = RunService.Heartbeat:Connect(step)
end

-- Public API

--[=[
	@class Chrono

	A scope-based task scheduler for Roblox. Schedule recurring tasks, fixed-rate
	ticks, one-shot delays, and per-frame callbacks — all tied to a `Scope`'s lifecycle.

	All tasks created through a Scope are automatically cleaned up when the Scope
	is destroyed, making chrono safe to use in component-based or OOP architectures
	without manual cleanup bookkeeping.

	```lua
	local chrono = require(path.to.chrono)

	local scope = chrono.scope()

	scope:tick(60, function(dt)
		player.position += player.velocity * dt
	end)

	scope:every(5, function()
		print("every 5 seconds")
	end)

	scope:after(10, function()
		scope:destroy() -- cleans up all tasks at once
	end)
	```
]=]

--[=[
	@within Chrono

	Creates a new independent Scope. Each Scope maintains its own pause state,
	time scale, and elapsed time. Scopes do not interfere with each other.

	@param config {timeScale: number?, onError: ((err: string, name: string) -> ())?}? -- Optional configuration. `timeScale` sets the initial time multiplier (default: `1.0`). `onError` is called when a task callback throws, receiving the error message and the task name.
	@return Scope
]=]
local function createScope(config: { timeScale: number?, onError: ((err: string, name: string) -> ())? }?): any
	ensureConnection()

	local data: ScopeData = {
		_isPaused = false,
		_isDestroyed = false,
		_timeScale = if config and config.timeScale then config.timeScale else 1.0,
		_elapsedTime = 0,
		_tickHandles = {},
		_frameHandles = {},
		_timerHandles = {},
		_pendingTick = {},
		_pendingFrame = {},
		_pendingTimer = {},
		_isProcessing = false,
		_onError = if config then config.onError else nil,
	}

	local scope = setmetatable({ _data = data }, ScopeMeta) :: any
	table.freeze(scope)
	table.insert(allScopes, scope)

	return scope
end

--[=[
	@within Chrono

	Returns profiling data for all tasks that have executed at least once since the
	last `reset_profiler()` call (or since the module was loaded).

	Task names come from the `name` field in each task's config table. Tasks without
	a name are grouped under `<anonymous>`.

	Times are computed over a rolling window of the last 128 samples per task.

	```lua
	local prof = chrono.profile()
	for name, data in pairs(prof) do
		print(name, "avg:", data.avgMs, "p99:", data.p99Ms)
	end
	```

	@return {[string]: {name: string, count: number, avgMs: number, maxMs: number, p99Ms: number, totalMs: number}}
]=]
local function profile(): { [string]: any }
	local result: { [string]: any } = {}

	for name, entry in profilerData do
		result[name] = {
			name = entry.name,
			count = entry.count,
			avgMs = if entry.count > 0 then entry.totalMs / entry.count else 0,
			maxMs = entry.maxMs,
			p99Ms = computeP99(entry),
			totalMs = entry.totalMs,
		}
	end

	return result
end

--[=[
	@within Chrono

	Clears all profiler data accumulated since the last reset or module load.
]=]
local function resetProfiler()
	table.clear(profilerData)
end

-- Module-level pause/resume

--[=[
	@within Chrono

	Pauses all active Scopes at once. Equivalent to calling `scope:pause()` on
	every Scope individually.

	Useful for game-wide pause states such as cutscenes or menus.
]=]
local function pauseAll()
	for _, scope in allScopes do
		local data = scope._data
		if not data._isDestroyed then
			data._isPaused = true
		end
	end
end

--[=[
	@within Chrono

	Resumes all active Scopes at once. Equivalent to calling `scope:resume()` on
	every Scope individually.
]=]
local function resumeAll()
	for _, scope in allScopes do
		local data = scope._data
		if not data._isDestroyed then
			data._isPaused = false
		end
	end
end

-- Testing internals

local function _setManualMode(enabled: boolean)
	manualMode = enabled
	if enabled and heartbeatConnection then
		heartbeatConnection:Disconnect()
		heartbeatConnection = nil
	end
end

local function _reset()
	for _, scope in allScopes do
		if not scope._data._isDestroyed then
			scope._data._isDestroyed = true
		end
	end
	table.clear(allScopes)
	table.clear(profilerData)
	nextCreationOrder = 0
	if heartbeatConnection then
		heartbeatConnection:Disconnect()
		heartbeatConnection = nil
	end
end

-- Module

return {
	scope = createScope,
	profile = profile,
	reset_profiler = resetProfiler,
	pause_all = pauseAll,
	resume_all = resumeAll,
	_step = step,
	_setManualMode = _setManualMode,
	_reset = _reset,
}
