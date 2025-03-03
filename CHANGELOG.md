# Changelog

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
