# The Process

This lib is designed to be able to easily run external process with complex configuration.
It uses builder pattern to configure process (args, env, workdir, etc),
thus it allows to easily use complex logic to prepare arguments and env for external process.

---

![Current status](https://img.shields.io/badge/Current%20Status-Alpha-purple)

---

[![Github Actions](https://github.com/katyukha/thepath/actions/workflows/tests.yml/badge.svg)](https://github.com/katyukha/thepath/actions/workflows/tests.yml?branch=master)
[![codecov](https://codecov.io/gh/katyukha/thepath/branch/master/graph/badge.svg?token=IUXBCNSHNQ)](https://codecov.io/gh/katyukha/thepath)
[![DUB](https://img.shields.io/dub/v/thepath)](https://code.dlang.org/packages/thepath)
![DUB](https://img.shields.io/dub/l/thepath)

![Ubuntu](https://img.shields.io/badge/Ubuntu-Latest-green?logo=Ubuntu)
![Windows](https://img.shields.io/badge/Windows-Latest-green?logo=Windows)
![MacOS](https://img.shields.io/badge/MacOS-Latest-green?logo=Apple)

---

## Examples

Simply execute the program:

```d
auto result = Process("my-program")
    .withArgs("arg1", "arg2")
    .withEnv("MY_VAR_1", 42")
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
    .withEnv("MY_VAR_1", 42")
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


## License

This library is licensed under MPL-2.0 license
