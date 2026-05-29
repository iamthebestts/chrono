--!strict

export type ScopeConfig = { timeScale: number?, onError: ((err: string, name: string) -> ())? }

export type HandleConfig = { name: string?, maxCatchup: number?, fireImmediately: boolean? }

export type Handle = {
	cancel: (self: Handle) -> (),
	pause: (self: Handle) -> (),
	resume: (self: Handle) -> (),
	setInterval: (self: Handle, interval: number) -> (),
	isPaused: (self: Handle) -> boolean,
	isCancelled: (self: Handle) -> boolean,
}

export type Scope = {
	after: (self: Scope, delay: number, fn: () -> (), config: HandleConfig?) -> Handle,
	every: (self: Scope, interval: number, fn: () -> (), config: HandleConfig?) -> Handle,
	frame: (self: Scope, fn: (dt: number) -> (), config: HandleConfig?) -> Handle,
	tick: (self: Scope, hz: number, fn: (dt: number) -> (), config: HandleConfig?) -> Handle,
	pause: (self: Scope) -> (),
	resume: (self: Scope) -> (),
	setTimeScale: (self: Scope, scale: number) -> (),
	destroy: (self: Scope) -> (),
	Destroy: (self: Scope) -> (),
	timeScale: number,
	isPaused: boolean,
	isDestroyed: boolean,
	elapsedTime: number,
}

export type ProfileEntry = {
	name: string,
	count: number,
	avgMs: number,
	maxMs: number,
	p99Ms: number,
	totalMs: number,
}

return {}
