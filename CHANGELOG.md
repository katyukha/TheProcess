# Changelog

## Unreleased

### Added

- `Process.setUser` and `Process.withUser` got extra option `userHomeDir`.
  When set, `HOME` of the process points at home directory of the user the
  process runs as, instead of being inherited from the caller.

---

## Release v0.1.1

### Added

- `isProcessRunning(Pid)` overload — accepts a `std.process.Pid` directly, delegating to
  the `int` overload via `pid.processID`.

---

## Release v0.1.0

### Breaking

- `with*` and `in*` configuration methods (`withArgs`, `withEnv`, `inWorkDir`, `withConfig`,
  `withFlag`, `withStderrPassThrough`, `withNewEnv`, `withUID`, `withGID`, `withUser`) now
  return a **new `Process` by value** instead of mutating the current instance.
  Previously they were plain aliases for the corresponding `set*` methods.
  Use `set*` / `add*` methods when in-place mutation is intended.
- `set*` methods (`setArgs`, `setWorkDir`, `setEnv`, `setNewEnv`, `setConfig`, `setFlag`,
  `setStderrPassThrough`, `setUID`, `setGID`, `setUser`) now return `void` instead of
  `ref this`. Chaining `set*` calls is no longer possible; use `with*` / `in*` methods
  for chained configuration instead.
- `addArgs` now returns `void` instead of `ref this`. Replace uses of `addArgs` inside
  chains with `withArgs` (which now appends rather than replaces).
- `withArgs` semantics changed: it now **appends** the provided arguments to a copy of
  the process instead of replacing the argument list. To replace args on a stored variable,
  call `setArgs` directly.

### Added

- `~` / `~=` operator overloads for `Process`: `p ~ "arg"` or `p ~ ["a", "b"]` returns a
  new `Process` with arguments appended (non-mutating); `p ~= "arg"` appends in place.
- `isProcessRunning(int pid)` — cross-platform check whether a process with the given PID
  is currently running. Uses `kill(pid, 0)` on Posix and `GetExitCodeProcess` on Windows.
- `SystemUser` struct (Posix only) — D-friendly representation of a passwd entry, with fields
  `name`, `uid`, `gid`, `homeDir`, and `shell`.
- `getSystemUser(string) → Nullable!SystemUser` (Posix only) — look up a system user by name
  via `getpwnam_r`; returns null if the user does not exist, throws on unexpected errors.
- `getCurrentUser() → SystemUser` (Posix only) — returns the `SystemUser` for the current
  effective user (uses `getpwuid_r(geteuid())`).
- `isCurrentUser(string) → bool` (Posix only) — returns true if the named user's uid matches
  the current effective UID; useful for deciding whether a user switch is necessary.
- `systemUserExists(string) → bool` (Posix only) — convenience wrapper over `getSystemUser`.

### Fixed

- `tearDownProcess` (which restores UID/GID after spawning a process as a different user) was
  not called when `execute`, `spawn`, or `pipe` threw an exception, leaving the parent process
  with permanently changed credentials. Fixed with `scope(exit)`.
- `execv` was passing the GID value as the effective-UID argument to `setreuid`, silently
  setting the wrong identity. Second argument is now correctly `_uid.get`.
- `resolveProgram` now skips entries in `PATH` that exist but are not executable (Posix only).
- `_original_uid`, `_original_gid`, and `preExecFunction` were not cleared after
  `tearDownProcess` ran, causing stale state that could incorrectly mutate the parent
  process credentials on a subsequent call to `execute`/`spawn`/`pipe` on the same instance.
- `setUser` / `withUser`: the internal `getpwnam_r` call used a signed `long` buffer length
  (should be `size_t`) and reported errors using the global `errno` instead of the return
  value of `getpwnam_r`. Both fixed by delegating to the new `getSystemUser`.

---

## Release v0.0.10

### Added

- Process.withUser now has extra param `userWorkDir` - if set to True, then command will be executed within user's home directory.

---

## Release v0.0.9

### Fixed

- Better handle case when system user does not exists in `.withUser` implementation.

---

## Release v0.0.7

### Fixed

- Fix `execv` method. Change uid and gid if needed before running process using execv.

---

## Release v0.0.6

### Added
- Added new method `copy` that could be used to copy process configuration before running.
  This could be useful, for cases when we need to run same program multiple time
  with similar configuration.

---

## Release v0.0.5

### Added
- Added new method `setNewEnv` (aliased `withNewEnv`) that configures `Process` to start in fresh environment (do not inherit parent environment variables).

### Fixed
- Correctly handle environment variables in `execv` method (take into account process config).

---

## Release v0.0.2

- Added new method `execv` that allows to replace current process by executing
  command/program described by Process instance.
