--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local JestGlobals = require(ReplicatedStorage.Packages.Dev.JestGlobals)

local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect
local beforeEach = JestGlobals.beforeEach

local chrono = require(script.Parent.Parent) :: any

-- Setup

beforeEach(function()
	chrono._reset()
	chrono._setManualMode(true)
end)

-- chrono.scope

describe("chrono.scope", function()
	it("creates a scope with default values", function()
		local scope = chrono.scope()
		expect(scope.timeScale).toBe(1.0)
		expect(scope.isPaused).toBe(false)
		expect(scope.isDestroyed).toBe(false)
		expect(scope.elapsedTime).toBe(0)
	end)

	it("accepts custom timeScale", function()
		local scope = chrono.scope({ timeScale = 0.5 })
		expect(scope.timeScale).toBe(0.5)
	end)

	it("multiple scopes are independent", function()
		local a = chrono.scope()
		local b = chrono.scope()
		a:pause()
		expect(a.isPaused).toBe(true)
		expect(b.isPaused).toBe(false)
	end)
end)

-- scope:after

describe("scope:after", function()
	it("fires callback after delay", function()
		local scope = chrono.scope()
		local fired = false
		scope:after(1, function()
			fired = true
		end)

		chrono._step(0.5)
		expect(fired).toBe(false)

		chrono._step(0.6)
		expect(fired).toBe(true)
	end)

	it("fires exactly once", function()
		local scope = chrono.scope()
		local count = 0
		scope:after(0.5, function()
			count += 1
		end)

		chrono._step(1)
		chrono._step(1)
		chrono._step(1)
		expect(count).toBe(1)
	end)

	it("delay <= 0 fires on next step", function()
		local scope = chrono.scope()
		local fired = false
		scope:after(0, function()
			fired = true
		end)

		chrono._step(0.016)
		expect(fired).toBe(true)
	end)

	it("negative delay fires on next step", function()
		local scope = chrono.scope()
		local fired = false
		scope:after(-5, function()
			fired = true
		end)

		chrono._step(0.016)
		expect(fired).toBe(true)
	end)

	it("does not fire while scope is paused", function()
		local scope = chrono.scope()
		local fired = false
		scope:after(0.5, function()
			fired = true
		end)

		scope:pause()
		chrono._step(1)
		expect(fired).toBe(false)

		scope:resume()
		chrono._step(0.5)
		expect(fired).toBe(true)
	end)

	it("is affected by timeScale", function()
		local scope = chrono.scope({ timeScale = 2 })
		local fired = false
		scope:after(1, function()
			fired = true
		end)

		chrono._step(0.4)
		expect(fired).toBe(false)

		chrono._step(0.2)
		expect(fired).toBe(true)
	end)

	it("passes config name to profiler", function()
		local scope = chrono.scope()
		scope:after(0, function() end, { name = "my_after" })
		chrono._step(0.016)

		local prof = chrono.profile()
		expect(prof["my_after"]).never.toBeNil()
		expect(prof["my_after"].count).toBe(1)
	end)

	it("returns a handle", function()
		local scope = chrono.scope()
		local handle = scope:after(1, function() end)
		expect(handle).never.toBeNil()
		expect(typeof(handle.cancel)).toBe("function")
	end)
end)

-- scope:every

describe("scope:every", function()
	it("fires immediately on first step", function()
		local scope = chrono.scope()
		local count = 0
		scope:every(5, function()
			count += 1
		end)

		chrono._step(0.016)
		expect(count).toBe(1)
	end)

	it("fires repeatedly at interval", function()
		local scope = chrono.scope()
		local count = 0
		scope:every(1, function()
			count += 1
		end)

		chrono._step(0.016) -- first run (immediate)
		expect(count).toBe(1)

		chrono._step(1)
		expect(count).toBe(2)

		chrono._step(1)
		expect(count).toBe(3)
	end)

	it("does not fire while scope is paused", function()
		local scope = chrono.scope()
		local count = 0
		scope:every(1, function()
			count += 1
		end)

		chrono._step(0.016) -- first run
		expect(count).toBe(1)

		scope:pause()
		chrono._step(2)
		expect(count).toBe(1)

		scope:resume()
		chrono._step(0.016) -- resumes, no backlog
		expect(count).toBe(1) -- not enough time accumulated

		chrono._step(1)
		expect(count).toBe(2)
	end)

	it("handle setInterval changes subsequent interval", function()
		local scope = chrono.scope()
		local count = 0
		local handle = scope:every(1, function()
			count += 1
		end)

		chrono._step(0.016) -- first run
		expect(count).toBe(1)

		handle:setInterval(2)

		chrono._step(1)
		expect(count).toBe(1) -- not enough time for new interval

		chrono._step(1.1)
		expect(count).toBe(2) -- now 2+ seconds passed since setInterval
	end)

	it("is affected by timeScale", function()
		local scope = chrono.scope({ timeScale = 2 })
		local count = 0
		scope:every(2, function()
			count += 1
		end)

		chrono._step(0.016) -- first run (immediate)
		expect(count).toBe(1)

		chrono._step(1) -- 1 wall-clock second = 2 scaled seconds
		expect(count).toBe(2)
	end)
end)

-- scope:frame

describe("scope:frame", function()
	it("fires every step with dt", function()
		local scope = chrono.scope()
		local receivedDt = -1
		scope:frame(function(dt)
			receivedDt = dt
		end)

		chrono._step(0.016)
		expect(receivedDt).toBeCloseTo(0.016, 5)
	end)

	it("fires with dt=0 when scope is paused", function()
		local scope = chrono.scope()
		local receivedDt = -1
		scope:frame(function(dt)
			receivedDt = dt
		end)

		scope:pause()
		chrono._step(0.5)
		expect(receivedDt).toBe(0)
	end)

	it("does NOT fire when handle is paused", function()
		local scope = chrono.scope()
		local count = 0
		local handle = scope:frame(function(_dt)
			count += 1
		end)

		chrono._step(0.016)
		expect(count).toBe(1)

		handle:pause()
		chrono._step(0.016)
		expect(count).toBe(1)

		handle:resume()
		chrono._step(0.016)
		expect(count).toBe(2)
	end)

	it("is NOT affected by timeScale (gets wall-clock dt)", function()
		local scope = chrono.scope({ timeScale = 3 })
		local receivedDt = -1
		scope:frame(function(dt)
			receivedDt = dt
		end)

		chrono._step(0.5)
		expect(receivedDt).toBeCloseTo(0.5, 5)
	end)

	it("multiple frame tasks run in creation order", function()
		local scope = chrono.scope()
		local order: { number } = {}

		scope:frame(function(_)
			table.insert(order, 1)
		end)
		scope:frame(function(_)
			table.insert(order, 2)
		end)
		scope:frame(function(_)
			table.insert(order, 3)
		end)

		chrono._step(0.016)
		expect(order[1]).toBe(1)
		expect(order[2]).toBe(2)
		expect(order[3]).toBe(3)
	end)
end)

-- scope:tick

describe("scope:tick", function()
	it("fires at fixed frequency", function()
		local scope = chrono.scope()
		local count = 0
		scope:tick(60, function(_dt)
			count += 1
		end)

		chrono._step(1 / 60)
		expect(count).toBe(1)
	end)

	it("fires multiple times per frame if needed", function()
		local scope = chrono.scope()
		local count = 0
		scope:tick(60, function(_dt)
			count += 1
		end)

		chrono._step(2 / 60)
		expect(count).toBe(2)
	end)

	it("receives fixed dt (1/hz)", function()
		local scope = chrono.scope()
		local receivedDt = -1
		scope:tick(60, function(dt)
			receivedDt = dt
		end)

		chrono._step(0.1)
		expect(receivedDt).toBeCloseTo(1 / 60, 5)
	end)

	it("does not fire while scope is paused (no backlog on resume)", function()
		local scope = chrono.scope()
		local count = 0
		scope:tick(60, function(_dt)
			count += 1
		end)

		chrono._step(1 / 60)
		expect(count).toBe(1)

		scope:pause()
		chrono._step(1) -- would be 60 ticks if not paused
		expect(count).toBe(1)

		scope:resume()
		chrono._step(1 / 60)
		expect(count).toBe(2) -- no backlog
	end)

	it("is affected by timeScale", function()
		local scope = chrono.scope({ timeScale = 2 })
		local count = 0
		scope:tick(60, function(_dt)
			count += 1
		end)

		chrono._step(1 / 60)
		expect(count).toBe(2) -- 2x speed means double ticks
	end)

	it("tick runs before frame in execution order", function()
		local scope = chrono.scope()
		local order: { string } = {}

		scope:frame(function(_)
			table.insert(order, "frame")
		end)
		scope:tick(60, function(_)
			table.insert(order, "tick")
		end)

		chrono._step(1 / 60)
		expect(order[1]).toBe("tick")
		expect(order[2]).toBe("frame")
	end)

	it("setInterval changes tick frequency", function()
		local scope = chrono.scope()
		local count = 0
		local handle = scope:tick(60, function(_dt)
			count += 1
		end)

		chrono._step(1 / 60) -- 1 tick
		expect(count).toBe(1)

		handle:setInterval(1 / 30) -- change to 30hz
		chrono._step(1 / 30)
		expect(count).toBe(2)
	end)
end)

-- scope:pause / resume

describe("scope:pause / resume", function()
	it("pause freezes all timers", function()
		local scope = chrono.scope()
		local afterFired = false
		local everyCount = 0

		scope:after(1, function()
			afterFired = true
		end)
		scope:every(1, function()
			everyCount += 1
		end)

		chrono._step(0.016) -- every first run
		scope:pause()
		chrono._step(5)

		expect(afterFired).toBe(false)
		expect(everyCount).toBe(1) -- only the first run
	end)

	it("resume continues from where it paused (no backlog)", function()
		local scope = chrono.scope()
		local fired = false
		scope:after(1, function()
			fired = true
		end)

		chrono._step(0.5)
		scope:pause()
		chrono._step(10) -- lots of paused time
		scope:resume()

		chrono._step(0.4)
		expect(fired).toBe(false) -- still 0.1 seconds short

		chrono._step(0.2)
		expect(fired).toBe(true)
	end)

	it("resume on non-paused scope is a no-op", function()
		local scope = chrono.scope()
		local ok = pcall(function()
			scope:resume()
		end)
		expect(ok).toBe(true)
	end)

	it("pause is idempotent", function()
		local scope = chrono.scope()
		scope:pause()
		scope:pause()
		expect(scope.isPaused).toBe(true)
	end)

	it("elapsedTime does not advance while paused", function()
		local scope = chrono.scope()
		chrono._step(1)
		local before = scope.elapsedTime
		scope:pause()
		chrono._step(5)
		expect(scope.elapsedTime).toBe(before)
	end)
end)

-- scope:setTimeScale

describe("scope:setTimeScale", function()
	it("multiplies time advancement", function()
		local scope = chrono.scope()
		scope:setTimeScale(2)
		chrono._step(1)
		expect(scope.elapsedTime).toBeCloseTo(2, 5)
	end)

	it("half speed slows everything down", function()
		local scope = chrono.scope()
		scope:setTimeScale(0.5)
		local fired = false
		scope:after(1, function()
			fired = true
		end)

		chrono._step(1)
		expect(fired).toBe(false) -- only 0.5 scaled seconds passed

		chrono._step(1)
		expect(fired).toBe(true) -- now 1.0 scaled seconds
	end)

	it("scale=0 freezes time like pause (but different semantics)", function()
		local scope = chrono.scope()
		scope:setTimeScale(0)

		chrono._step(1)
		expect(scope.elapsedTime).toBe(0)
	end)

	it("does NOT affect frame dt (frame gets wall-clock)", function()
		local scope = chrono.scope()
		scope:setTimeScale(5)
		local receivedDt = -1
		scope:frame(function(dt)
			receivedDt = dt
		end)

		chrono._step(0.5)
		expect(receivedDt).toBeCloseTo(0.5, 5)
	end)

	it("affects tick rate", function()
		local scope = chrono.scope()
		scope:setTimeScale(3)
		local count = 0
		scope:tick(60, function(_)
			count += 1
		end)

		chrono._step(1 / 60)
		expect(count).toBe(3) -- 3x speed, 3 ticks per frame
	end)

	it("can be changed at any time", function()
		local scope = chrono.scope()
		scope:setTimeScale(1)
		expect(scope.timeScale).toBe(1)

		scope:setTimeScale(2.5)
		expect(scope.timeScale).toBe(2.5)
	end)
end)

-- scope:destroy

describe("scope:destroy", function()
	it("marks scope as destroyed", function()
		local scope = chrono.scope()
		scope:destroy()
		expect(scope.isDestroyed).toBe(true)
	end)

	it("cancels all child handles", function()
		local scope = chrono.scope()
		local count = 0
		scope:every(1, function()
			count += 1
		end)
		scope:frame(function(_)
			count += 1
		end)

		chrono._step(0.016)
		local beforeDestroy = count
		scope:destroy()
		chrono._step(1)
		expect(count).toBe(beforeDestroy)
	end)

	it("throws on subsequent method calls", function()
		local scope = chrono.scope()
		scope:destroy()

		expect(function()
			scope:after(1, function() end)
		end).toThrow()
		expect(function()
			scope:pause()
		end).toThrow()
		expect(function()
			scope:resume()
		end).toThrow()
		expect(function()
			scope:setTimeScale(1)
		end).toThrow()
		expect(function()
			scope:destroy()
		end).toThrow()
	end)

	it("is Trove-compatible via Destroy alias", function()
		local scope = chrono.scope()
		scope:Destroy()
		expect(scope.isDestroyed).toBe(true)
	end)

	it("child handle methods throw after scope destroy", function()
		local scope = chrono.scope()
		local handle = scope:every(1, function() end)
		scope:destroy()

		expect(function()
			handle:cancel()
		end).toThrow()
		expect(function()
			handle:pause()
		end).toThrow()
		expect(function()
			handle:isCancelled()
		end).toThrow()
	end)
end)

-- handle:cancel

describe("handle:cancel", function()
	it("prevents task from running", function()
		local scope = chrono.scope()
		local fired = false
		local handle = scope:after(1, function()
			fired = true
		end)
		handle:cancel()

		chrono._step(2)
		expect(fired).toBe(false)
	end)

	it("throws if already cancelled", function()
		local scope = chrono.scope()
		local handle = scope:after(1, function() end)
		handle:cancel()

		expect(function()
			handle:cancel()
		end).toThrow()
	end)

	it("self-cancellation inside callback is safe", function()
		local scope = chrono.scope()
		local handle: any
		local count = 0
		handle = scope:every(1, function()
			count += 1
			handle:cancel()
		end)

		chrono._step(0.016) -- first run, self-cancel
		chrono._step(1)
		expect(count).toBe(1)
	end)
end)

-- handle:pause / resume

describe("handle:pause / resume", function()
	it("pausing handle prevents execution", function()
		local scope = chrono.scope()
		local count = 0
		local handle = scope:every(1, function()
			count += 1
		end)

		chrono._step(0.016) -- first run
		handle:pause()
		chrono._step(2)
		expect(count).toBe(1)

		handle:resume()
		chrono._step(0.016) -- resumes but needs accumulated time
		chrono._step(1)
		expect(count).toBe(2)
	end)

	it("pause is idempotent (no error)", function()
		local scope = chrono.scope()
		local handle = scope:after(1, function() end)
		handle:pause()
		handle:pause()
		expect(handle:isPaused()).toBe(true)
	end)

	it("handle pause is cumulative with scope pause", function()
		local scope = chrono.scope()
		local count = 0
		local handle = scope:frame(function(_)
			count += 1
		end)

		chrono._step(0.016)
		expect(count).toBe(1)

		scope:pause()
		handle:pause()
		chrono._step(0.016) -- both paused, frame does NOT fire
		expect(count).toBe(1)

		scope:resume()
		chrono._step(0.016) -- scope resumed, but handle still paused
		expect(count).toBe(1)

		handle:resume()
		chrono._step(0.016) -- both unpaused, fires
		expect(count).toBe(2)
	end)

	it("throws on cancelled handle", function()
		local scope = chrono.scope()
		local handle = scope:after(1, function() end)
		handle:cancel()

		expect(function()
			handle:pause()
		end).toThrow()
		expect(function()
			handle:resume()
		end).toThrow()
	end)
end)

-- handle:setInterval

describe("handle:setInterval", function()
	it("changes every interval", function()
		local scope = chrono.scope()
		local count = 0
		local handle = scope:every(1, function()
			count += 1
		end)

		chrono._step(0.016) -- first run
		expect(count).toBe(1)

		handle:setInterval(0.5)
		chrono._step(0.5)
		expect(count).toBe(2)
	end)

	it("throws on after handle", function()
		local scope = chrono.scope()
		local handle = scope:after(1, function() end)

		expect(function()
			handle:setInterval(2)
		end).toThrow()
	end)

	it("throws on frame handle", function()
		local scope = chrono.scope()
		local handle = scope:frame(function(_) end)

		expect(function()
			handle:setInterval(2)
		end).toThrow()
	end)

	it("works on tick handle", function()
		local scope = chrono.scope()
		local count = 0
		local handle = scope:tick(60, function(_)
			count += 1
		end)

		chrono._step(1 / 60)
		expect(count).toBe(1)

		handle:setInterval(1 / 30)
		chrono._step(1 / 30)
		expect(count).toBe(2)
	end)
end)

-- handle:isPaused / isCancelled

describe("handle:isPaused / isCancelled", function()
	it("isPaused returns correct state", function()
		local scope = chrono.scope()
		local handle = scope:after(1, function() end)
		expect(handle:isPaused()).toBe(false)
		handle:pause()
		expect(handle:isPaused()).toBe(true)
		handle:resume()
		expect(handle:isPaused()).toBe(false)
	end)

	it("isPaused does not reflect scope pause", function()
		local scope = chrono.scope()
		local handle = scope:after(1, function() end)
		scope:pause()
		expect(handle:isPaused()).toBe(false) -- only handle pause state
	end)

	it("isCancelled returns correct state", function()
		local scope = chrono.scope()
		local handle = scope:after(1, function() end)
		expect(handle:isCancelled()).toBe(false)
		handle:cancel()
		expect(handle:isCancelled()).toBe(true)
	end)

	it("isCancelled throws when scope is destroyed", function()
		local scope = chrono.scope()
		local handle = scope:after(1, function() end)
		scope:destroy()

		expect(function()
			handle:isCancelled()
		end).toThrow()
	end)
end)

-- Edge cases

describe("edge cases", function()
	it("nested task creation does not fire in same frame", function()
		local scope = chrono.scope()
		local nestedFired = false
		scope:every(1, function()
			scope:after(0, function()
				nestedFired = true
			end)
		end)

		chrono._step(0.016) -- every fires, creates after(0)
		expect(nestedFired).toBe(false) -- should NOT fire in same frame

		chrono._step(0.016)
		expect(nestedFired).toBe(true) -- fires next frame
	end)

	it("destroying scope during task execution stops remaining tasks", function()
		local scope = chrono.scope()
		local order: { string } = {}

		scope:frame(function(_)
			table.insert(order, "first")
			scope:destroy()
		end)
		scope:frame(function(_)
			table.insert(order, "second") -- should NOT run
		end)

		chrono._step(0.016)
		expect(#order).toBe(1)
		expect(order[1]).toBe("first")
	end)

	it("scope destruction during tick stops accumulated fires", function()
		local scope = chrono.scope()
		local count = 0
		scope:tick(60, function(_)
			count += 1
			if count == 1 then
				scope:destroy()
			end
		end)

		chrono._step(0.1) -- would fire 6 times, but scope destroyed after first
		expect(count).toBe(1)
	end)

	it("multiple scopes step independently", function()
		local a = chrono.scope({ timeScale = 1 })
		local b = chrono.scope({ timeScale = 2 })

		chrono._step(1)
		expect(a.elapsedTime).toBeCloseTo(1, 5)
		expect(b.elapsedTime).toBeCloseTo(2, 5)
	end)

	it("after handle auto-cancels after firing", function()
		local scope = chrono.scope()
		local handle = scope:after(0.5, function() end)

		chrono._step(1)
		expect(handle:isCancelled()).toBe(true)
	end)
end)

-- Profiler

describe("chrono.profile", function()
	it("records task execution stats", function()
		local scope = chrono.scope()
		scope:frame(function(_) end, { name = "my_frame" })

		chrono._step(0.016)
		chrono._step(0.016)
		chrono._step(0.016)

		local prof = chrono.profile()
		expect(prof["my_frame"]).never.toBeNil()
		expect(prof["my_frame"].count).toBe(3)
		expect(prof["my_frame"].name).toBe("my_frame")
	end)

	it("only includes tasks that have executed", function()
		local scope = chrono.scope()
		scope:after(100, function() end, { name = "never_fired" })
		chrono._step(0.016)

		local prof = chrono.profile()
		expect(prof["never_fired"]).toBeNil()
	end)

	it("reset_profiler clears all data", function()
		local scope = chrono.scope()
		scope:frame(function(_) end, { name = "to_reset" })
		chrono._step(0.016)

		chrono.reset_profiler()
		local prof = chrono.profile()
		expect(prof["to_reset"]).toBeNil()
	end)

	it("tracks maxMs", function()
		local scope = chrono.scope()
		scope:frame(function(_) end, { name = "max_test" })

		chrono._step(0.016)
		chrono._step(0.016)

		local prof = chrono.profile()
		expect(prof["max_test"].maxMs >= 0).toBe(true)
	end)

	it("computes avgMs", function()
		local scope = chrono.scope()
		scope:frame(function(_) end, { name = "avg_test" })

		chrono._step(0.016)
		chrono._step(0.016)

		local prof = chrono.profile()
		local entry = prof["avg_test"]
		expect(entry.avgMs).toBeCloseTo(entry.totalMs / entry.count, 5)
	end)

	it("ring buffer caps sample storage", function()
		local scope = chrono.scope()
		scope:frame(function(_) end, { name = "ring_buf" })

		for _ = 1, 200 do
			chrono._step(0.016)
		end

		local prof = chrono.profile()
		local entry = prof["ring_buf"]
		expect(entry.count).toBe(200)
		expect(entry.p99Ms >= 0).toBe(true)
	end)
end)

-- Error isolation

describe("error isolation", function()
	it("callback error does not stop other tasks in same scope", function()
		local scope = chrono.scope()
		local secondRan = false

		scope:frame(function(_)
			error("boom")
		end)
		scope:frame(function(_)
			secondRan = true
		end)

		chrono._step(0.016)
		expect(secondRan).toBe(true)
	end)

	it("callback error does not stop other scopes", function()
		local scopeA = chrono.scope()
		local scopeB = chrono.scope()
		local bRan = false

		scopeA:frame(function(_)
			error("crash")
		end)
		scopeB:frame(function(_)
			bRan = true
		end)

		chrono._step(0.016)
		expect(bRan).toBe(true)
	end)

	it("onError handler receives error and handle name", function()
		local capturedErr: string? = nil
		local capturedName: string? = nil

		local scope = chrono.scope({
			onError = function(err, name)
				capturedErr = err
				capturedName = name
			end,
		})

		scope:frame(function(_)
			error("test_error")
		end, { name = "bad_frame" })

		chrono._step(0.016)
		expect(capturedName).toBe("bad_frame")
		expect(capturedErr ~= nil).toBe(true)
		expect(string.find(tostring(capturedErr), "test_error") ~= nil).toBe(true)
	end)

	it("without onError, errors are silently swallowed", function()
		local scope = chrono.scope()
		local count = 0

		scope:every(1, function()
			count += 1
			error("silent")
		end)

		local ok = pcall(function()
			chrono._step(0.016)
			chrono._step(1)
		end)
		expect(ok).toBe(true)
		expect(count).toBe(2)
	end)

	it("after callback error still auto-cancels the handle", function()
		local scope = chrono.scope()
		local handle = scope:after(0.5, function()
			error("fail")
		end)

		chrono._step(1)
		expect(handle:isCancelled()).toBe(true)
	end)

	it("tick callback error does not break the tick loop", function()
		local scope = chrono.scope()
		local count = 0

		scope:tick(60, function(_)
			count += 1
			if count == 1 then
				error("first tick fail")
			end
		end)

		chrono._step(3 / 60) -- should attempt 3 ticks
		expect(count).toBe(3)
	end)
end)

-- maxCatchup

describe("maxCatchup", function()
	it("limits tick fires per frame", function()
		local scope = chrono.scope()
		local count = 0

		scope:tick(60, function(_)
			count += 1
		end, { maxCatchup = 4 })

		chrono._step(1) -- would be 60 ticks, clamped to 4
		expect(count).toBe(4)
	end)

	it("discards accumulated time after hitting limit", function()
		local scope = chrono.scope()
		local count = 0

		scope:tick(60, function(_)
			count += 1
		end, { maxCatchup = 2 })

		chrono._step(1)
		expect(count).toBe(2)

		count = 0
		chrono._step(1 / 60) -- fresh frame, normal tick
		expect(count).toBe(1)
	end)

	it("default is unlimited (math.huge)", function()
		local scope = chrono.scope()
		local count = 0

		scope:tick(1000, function(_)
			count += 1
		end)

		chrono._step(0.01) -- 10 ticks at 1000hz
		expect(count).toBe(10)
	end)

	it("does NOT apply to every loops", function()
		local scope = chrono.scope()
		local count = 0

		scope:every(0.01, function()
			count += 1
		end)

		chrono._step(0.016) -- first run
		chrono._step(0.1) -- should fire ~10 times without limit
		expect(count >= 10).toBe(true)
	end)
end)

-- pause_all / resume_all

describe("chrono.pause_all / resume_all", function()
	it("pauses all active scopes", function()
		local a = chrono.scope()
		local b = chrono.scope()

		chrono.pause_all()
		expect(a.isPaused).toBe(true)
		expect(b.isPaused).toBe(true)
	end)

	it("resumes all active scopes", function()
		local a = chrono.scope()
		local b = chrono.scope()

		chrono.pause_all()
		chrono.resume_all()
		expect(a.isPaused).toBe(false)
		expect(b.isPaused).toBe(false)
	end)

	it("skips destroyed scopes", function()
		local a = chrono.scope()
		local b = chrono.scope()
		a:destroy()

		local ok = pcall(function()
			chrono.pause_all()
		end)
		expect(ok).toBe(true)
		expect(b.isPaused).toBe(true)
	end)

	it("actually freezes task execution", function()
		local scope = chrono.scope()
		local count = 0
		scope:every(1, function()
			count += 1
		end)

		chrono._step(0.016) -- first run
		expect(count).toBe(1)

		chrono.pause_all()
		chrono._step(5)
		expect(count).toBe(1)

		chrono.resume_all()
		chrono._step(1)
		expect(count).toBe(2)
	end)
end)
