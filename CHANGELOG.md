# Changelog

## Release v0.0.11

### Breaking

- `with*` and `in*` configuration methods (`withArgs`, `withEnv`, `inWorkDir`, `withConfig`,
  `withFlag`, `withStderrPassThrough`, `withNewEnv`, `withUID`, `withGID`, `withUser`) now
  return a **new `Process` by value** instead of mutating the current instance.
  Previously they were plain aliases for the corresponding `set*` methods.
  Use `set*` / `add*` methods when in-place mutation is intended.

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
