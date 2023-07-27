# The Process

This lib is designed to be able to easily run external process with complex configuration.
It uses builder pattern to configure process (args, env, workdir, etc),
thus it allows to easily use complex logic to prepare arguments and env for external process.

Current stage: ***Alpha***

## Examples

Just few real examples at the moment:

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
    runner.setFlag(Config.detached);
    runner.addArgs("--logfile=%s".format(_project.odoo.logfile));
}

auto pid = runner.spawn();

if (!detach)
    std.process.wait(pid);
```


## License

This library is licensed under MPL-2.0 license
