# The Process

This lib is designed to be able to easily run external process with complex configuration.
It uses builder pattern to configure process (args, env, workdir, etc),
thus it allows to easily use complex logic to prepare arguments and env for external process.

---

![Current status](https://img.shields.io/badge/Current%20Status-Alpha-purple)

---

[![Github Actions](https://github.com/katyukha/theprocess/actions/workflows/tests.yml/badge.svg)](https://github.com/katyukha/theprocess/actions/workflows/tests.yml?branch=master)
[![codecov](https://codecov.io/gh/katyukha/theprocess/branch/master/graph/badge.svg?token=IUXBCNSHNQ)](https://codecov.io/gh/katyukha/theprocess)
[![DUB](https://img.shields.io/dub/v/theprocess)](https://code.dlang.org/packages/theprocess)
![DUB](https://img.shields.io/dub/l/theprocess)

![Ubuntu](https://img.shields.io/badge/Ubuntu-Latest-green?logo=Ubuntu)
![Windows](https://img.shields.io/badge/Windows-Latest-green?logo=Windows)
![MacOS](https://img.shields.io/badge/MacOS-Latest-green?logo=Apple)

---

## Configuration methods

Process configuration methods come in two families:

- **`set*` / `add*`** — mutate the current instance in place and return `void`.
  Use these when you have a stored `Process` variable that you want to modify conditionally.

```d
auto runner = Process("my-program").withArgs("--base-arg");
if (condition)
    runner.addArgs("--extra-arg");  // mutates runner in place
runner.execute;
```

- **`with*` / `in*`** — return a **new** `Process` by value, leaving the original unchanged.
  Safe to use in chained expressions or when deriving variants from a shared base.

```d
// Each call returns a fresh Process; the original is never modified
auto result = Process("my-program")
    .withArgs("--verbose")
    .inWorkDir("/my/work/dir")
    .execute;
```

## Examples

Simply execute the program:

```d
auto result = Process("my-program")
    .withArgs("arg1", "arg2")
    .withEnv("MY_VAR_1", "42")
    .inWorkDir("/my/work/dir")
    .execute
    .ensureOk;  //check exit code

writefln("Result status: %s",  result.status);  // print exit code
writefln("Result output: %s", result.output);   // print output
```

Run process in background

```d
auto pid = Process("my-program")
    .withArgs("arg1", "arg2")
    .withEnv("MY_VAR_1", "42")
    .inWorkDir("/my/work/dir")
    .spawn;

// Do some other work

auto exit_code = pid.wait();
writefln("Process completed. Exit-code: %s", exit_code);
```

Just few real examples from projects that use this lib:

```d
// Simply run git add command
Process("git")
    .withArgs(["add", this.dst_info.path])
    .inWorkDir(this.config.package_dir)
    .execute
    .ensureStatus;


// Run Odoo server with different args depending on configuration
auto runner = Process(venv_path.join("bin", "run-in-venv"))
    .inWorkDir(_project.project_root.toString)
    .withEnv(getServerEnv);

if (_project.odoo.server_user)
    runner.setUser(_project.odoo.server_user);

if (coverage.enable) {
    // Run server with coverage mode
    runner.addArgs(
        _project.venv.path.join("bin", "coverage").toString,
        "run",
        "--parallel-mode",
        "--omit=*/__openerp__.py,*/__manifest__.py",
        // TODO: Add --data-file option. possibly store it in CoverageOptions
    );
    if (coverage.source.length > 0)
        runner.addArgs(
            "--source=%s".format(
                coverage.source.map!(p => p.toString).join(",")),
        );
    if (coverage.include.length > 0)
        runner.addArgs(
            "--include=%s".format(
                coverage.include.map!(
                    p => p.toString ~ "/*").join(",")),
        );
}

runner.addArgs(scriptPath.toString);
runner.addArgs(options);

if (detach) {
    // If we want to run the server in background
    runner.setFlag(Config.detached);
    runner.addArgs("--logfile=%s".format(_project.odoo.logfile));
}

auto pid = runner.spawn();

if (!detach)
    std.process.wait(pid);
```


## Running as a different user (Posix)

On Posix systems a `Process` can be run as a different user by name or by explicit uid/gid:

```d
// Run as a named user
Process("my-program")
    .withUser("deploy")
    .execute
    .ensureOk;

// Also switch the working directory to the user's home directory
Process("my-program")
    .withUser("deploy", true)
    .execute
    .ensureOk;

// Or set uid/gid directly
Process("my-program")
    .withUID(1001)
    .withGID(1001)
    .execute
    .ensureOk;
```

## Utilities

### Checking whether a process is running

```d
import theprocess: isProcessRunning;

if (isProcessRunning(pid.processID))
    writeln("still running");
```

Works on Posix (via `kill(pid, 0)`) and Windows (via `GetExitCodeProcess`).

### Resolving a program from PATH

```d
import theprocess: resolveProgram;

auto path = resolveProgram("git");
if (!path.isNull)
    writeln("git is at: ", path.get);
```

### System user utilities (Posix)

```d
import theprocess: SystemUser, getSystemUser, getCurrentUser,
                   isCurrentUser, systemUserExists;

// Look up a user by name — returns null if not found
Nullable!SystemUser user = getSystemUser("deploy");
if (!user.isNull)
    writeln(user.get.uid, " ", user.get.homeDir);

// Get the current effective user
SystemUser me = getCurrentUser();

// Decide whether a user switch is needed
if (!isCurrentUser("deploy"))
    Process("myapp").withUser("deploy").spawn();

// Simple existence check
if (systemUserExists("postgres"))
    writeln("postgres user is present");
```

## License

This library is licensed under MPL-2.0 license
