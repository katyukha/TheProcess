/** Module that defines the main `Process` struct and associated components.
  **/
module theprocess.process;

private import std.format;
private import std.process;
private import std.file;
private import std.stdio;
private import std.exception;
private import std.string: join;
private import std.typecons;

version(Posix) {
    private import core.sys.posix.unistd;
    private import core.sys.posix.pwd;
}

private import thepath;

private import theprocess.utils;
private import theprocess.exception: ProcessException;


/** Process result, produced by 'execute' method of Process.
  **/
@safe immutable struct ProcessResult {
    /// The program that was invoked to obtain this result.
    private string _program;

    /// The arguments passed to the program to obtain this result.
    private string[] _args;

    /// exit code of the process
    int status;

    /// text output of the process
    string output;

    // Do not allow to create records without params
    @disable this();

    private pure this(
            in string program,
            immutable string[] args,
            in int status,
            in string output) nothrow {
        this._program = program;
        this._args = args;
        this.status = status;
        this.output = output;
    }

    /** Check if status is Ok.
      *
      * Params:
      *     expected = expected exit code. Default: 0
      *
      * Returns:
      *     True it exit status is equal to expected result, otherwise False.
      **/
    bool isOk(in int expected=0) const { return this.status == expected; }

    /** Check if status is not Ok.
      *
      * Params:
      *     expected = expected successfule exit code. Default: 0
      *
      * Returns:
      *     True it exit status is NOT equal to expected result, otherwise False.
      **/
    bool isNotOk(in int expected=0) const { return !isOk(expected); }

    /** Ensure that program exited with expected exit code.
      *
      * Params:
      *     msg = message to throw in exception in case of check failure
      *     add_output = if set to True, then output of command will be attached
      *         to message on failure.
      *     expected = expected exit-code, if differ, then
      *         exception will be thrown.
      **/
    auto ref ensureStatus(E : Throwable = ProcessException)(
            in string msg, in bool add_output, in int expected=0) const {
        enforce!E(
            isOk(expected),
            add_output ? msg : msg ~ "\nOutput: " ~ output);
        return this;
    }

    /// ditto
    auto ref ensureStatus(E : Throwable = ProcessException)(
            in string msg, in int expected=0) const {
        return ensureStatus(
            msg,
            true,
            expected);
    }

    /// ditto
    auto ref ensureStatus(E : Throwable = ProcessException)(in int expected=0) const {
        return ensureStatus(
            "Program %s with args %s failed! Expected exit-code %s, got %s.".format(
                _program, _args, expected, status),
            expected);
    }

    /// ditto
    alias ensureOk = ensureStatus;

}


/** This struct is used to prepare configuration for process and run it.
  *
  * The following methods of running a process are supported:
  * - execute: run process and catch its output and exit code.
  * - spawn: spawn the process in background, and optionally pipe its output.
  * - pipe: spawn the process and attach configurable pipes to catch output.
  *
  * The configuration of a process can be done like so:
  * 1. Create the `Process` instance specifying the program to run.
  * 2. Apply your desired configuration (args, env, workDir)
  *    via calls to one of the corresponding methods.
  * 3. Run one of `execute`, `spawn` or `pipe` methods, that will actually
  *    start the process.
  *
  * Configuration methods are usually prefixed with `set` word, but they
  * may also have semantic aliases. For example, the method `setArgs` also has
  * an alias `withArgs`, and the method `setWorkDir` has an alias `inWorkDir`.
  * Additionally, configuration methods always
  * return the reference to current instance of the Process being configured.
  *
  * Examples:
  * ---
  * // It is possible to run process in following way:
  * auto result = Process('my-program')
  *         .withArgs("--verbose", "--help")
  *         .withEnv("MY_ENV_VAR", "MY_VALUE")
  *         .inWorkDir("my/working/directory")
  *         .execute()
  *         .ensureStatus!MyException("My error message on failure");
  * writeln(result.output);
  * ---
  * // Also, in Posix system it is possible to run command as different user:
  * auto result = Process('my-program')
  *         .withUser("bob")
  *         .execute()
  *         .ensureStatus!MyException("My error message on failure");
  * writeln(result.output);
  * ---
  **/
@safe struct Process {
    private string _program;
    private string[] _args;
    private string[string] _env=null;
    private string _workdir=null;
    private std.process.Config _config=std.process.Config.none;

    /* TODO: May be it have sense to add somekind of lock
     *       to wrap execution of process in multithreaded mode.
     *       It seems that this is needed on Posix systems,
     *       especially in case when running process with different
     *       uid/git, that requires temporary change of uid/gid of current
     *       process, but uid and gid are attributes of process, not thread.
     */

    version(Posix) {
        /* On posix we have ability to run process with different user,
         * thus we have to keep desired uid/gid to run process with and
         * original uid/git to revert uid/gid change after process completed.
         */
        private Nullable!uid_t _uid;
        private Nullable!gid_t _gid;
        private Nullable!uid_t _original_uid;
        private Nullable!gid_t _original_gid;
    }

    /** Create new Process instance to run specified program.
      *
      * Params:
      *     program = name of program to run or path of program to run
      **/
    this(in string program) {
        _program = program;
    }

    /// ditto
    this(in Path program) {
        _program = program.toAbsolute.toString;
    }

    /** Return string representation of process to be started
      **/
    string toString() const {
        return "Program: %s, args: %s, env: %s, workdir: %s".format(
            _program, _args.join(" "), _env, _workdir);
    }

    /** Set arguments for the process
      *
      * Params:
      *     args = array of arguments to run program with
      *
      * Returns:
      *     reference to this (process instance)
      **/
    auto ref setArgs(in string[] args...) {
        _args = args.dup;
        return this;
    }

    /// ditto
    alias withArgs = setArgs;

    /** Add arguments to the process.
      *
      * This could be used if you do not know all the arguments for program
      * to run at single point, and you need to add it conditionally.
      *
      * Params:
      *     args = array of arguments to run program with
      *
      * Returns:
      *     reference to this (process instance)
      *
      * Examples:
      * ---
      * auto program = Process('my-program')
      *     .withArgs("--some-option");
      *
      * if (some condition)
      *     program.addArgs("--some-other-opt", "--verbose");
      *
      * auto result = program
      *     .execute()
      *     .ensureStatus!MyException("My error message on failure");
      * writeln(result.output);
      * ---
      **/
    auto ref addArgs(in string[] args...) {
        _args ~= args;
        return this;
    }

    /** Set work directory for the process to be started
      *
      * Params:
      *     workdir = working directory path to run process in
      *
      * Returns:
      *     reference to this (process instance)
      *
      **/
    auto ref setWorkDir(in string workdir) {
        _workdir = workdir;
        return this;
    }

    /// ditto
    auto ref setWorkDir(in Path workdir) {
        _workdir = workdir.toString;
        return this;
    }

    /// ditto
    alias inWorkDir = setWorkDir;

    /** Set environemnt for the process to be started
      *
      * Params:
      *     env = associative array to update environment to run process with.
      *
      * Returns:
      *     reference to this (process instance)
      *
      **/
    auto ref setEnv(in string[string] env) {
        foreach(i; env.byKeyValue)
            _env[i.key] = i.value;
        return this;
    }

    /** Set environment variable (specified by key) to provided value
      *
      * Params:
      *     key = environment variable name
      *     value = environment variable value
      *
      * Returns:
      *     reference to this (process instance)
      *
      **/
    auto ref setEnv(in string key, in string value) {
        _env[key] = value;
        return this;
    }

    /// ditto
    alias withEnv = setEnv;

    /** Set process configuration
      **/
    auto ref setConfig(in std.process.Config config) {
        _config = config;
        return this;
    }

    /// ditto
    alias withConfig = setConfig;

    /** Set configuration flag for process to be started
      **/
    auto ref setFlag(in std.process.Config.Flags flag) {
        _config.flags |= flag;
        return this;
    }

    /// ditto
    auto ref setFlag(in std.process.Config flags) {
        _config |= flags;
        return this;
    }

    /// ditto
    alias withFlag = setFlag;

    /** Set UID to run process with
      *
      * Params:
      *     uid = UID (id of system user) to run process with
      *
      * Returns:
      *     reference to this (process instance)
      *
      **/
    version(Posix) auto ref setUID(in uid_t uid) {
        _uid = uid;
        return this;
    }

    /// ditto
    version(Posix) alias withUID = setUID;

    /** Set GID to run process with
      *
      * Params:
      *     gid = GID (id of system group) to run process with
      *
      * Returns:
      *     reference to this (process instance)
      *
      **/
    version(Posix) auto ref setGID(in gid_t gid) {
        _gid = gid;
        return this;
    }

    /// ditto
    version(Posix) alias withGID = setGID;

    /** Run process as specified user
      *
      * If this method applied, then the UID and GID to run process with
      * will be taked from record in passwd database
      *
      * Params:
      *     username = login of user to run process as
      *
      * Returns:
      *     reference to this (process instance)
      *
      **/
    version(Posix) auto ref setUser(in string username) @trusted {
        import std.string: toStringz;

        /* pw info has following fields:
         *     - pw_name,
         *     - pw_passwd,
         *     - pw_uid,
         *     - pw_gid,
         *     - pw_gecos,
         *     - pw_dir,
         *     - pw_shell,
         */
        auto pw = getpwnam(username.toStringz);
        errnoEnforce(
            pw !is null,
            "Cannot get info about user %s".format(username));
        setUID(pw.pw_uid);
        setGID(pw.pw_gid);
        // TODO: add ability to automatically set user's home directory
        //       if needed
        return this;
    }

    ///
    version(Posix) alias withUser = setUser;

    /// Called before running process to run pre-exec hooks;
    private void setUpProcess() {
        version(Posix) {
            /* We set real user and real group here,
             * keeping original effective user and effective group
             * (usually original user/group is root, when such logic used)
             * Later in preExecFunction, we can update effective user
             * for child process to be same as real user.
             * This is needed, because bash, changes effective user to real
             * user when effective user is different from real.
             * Thus, we have to set both real user and effective user
             * for child process.
             *
             * We can accomplish this in two steps:
             *     - Change real uid/gid here for current process
             *     - Change effective uid/gid to match real uid/gid
             *       in preexec fuction.
             * Because preexec function is executed in child process,
             * that will be replaced by specified command proces, it works.
             *
             * Also, note, that first we have to change group ID, because
             * when we change user id first, it may not be possible to change
             * group.
             */

             /*
              * TODO: May be it have sense to change effective user/group
              *       instead of real user, and update real user in
              *       child process.
              */
            if (!_gid.isNull && _gid.get != getgid) {
                _original_gid = getgid().nullable;
                errnoEnforce(
                    setregid(_gid.get, -1) == 0,
                    "Cannot set real GID to %s before starting process: %s".format(
                        _gid, this.toString));
            }
            if (!_uid.isNull && _uid.get != getuid) {
                _original_uid = getuid().nullable;
                errnoEnforce(
                    setreuid(_uid.get, -1) == 0,
                    "Cannot set real UID to %s before starting process: %s".format(
                        _uid, this.toString));
            }

            if (!_original_uid.isNull || !_original_gid.isNull)
                _config.preExecFunction = () @trusted nothrow @nogc {
                    /* Because we cannot pass any parameters here,
                     * we just need to make real user/group equal to
                     * effective user/group for child proces.
                     * This is needed, because bash could change effective user
                     * when it is different from real user.
                     *
                     * We change here effective user/group equal
                     * to real user/group because we have changed
                     * real user/group in parent process
                     * before running this function.
                     *
                     * Also, note, that this function will be executed
                     * in child process, just before calling execve.
                     */
                    if (setegid(getgid) != 0)
                        return false;
                    if (seteuid(getuid) != 0)
                        return false;
                    return true;
                };

        }
    }

    /// Called after process started to run post-exec hooks;
    private void tearDownProcess() {
        version(Posix) {
            // Restore original uid/gid after process started.
            if (!_original_gid.isNull)
                errnoEnforce(
                    setregid(_original_gid.get, -1) == 0,
                    "Cannot restore real GID to %s after process started: %s".format(
                        _original_gid, this.toString));
            if (!_original_uid.isNull)
                errnoEnforce(
                    setreuid(_original_uid.get, -1) == 0,
                    "Cannot restore real UID to %s after process started: %s".format(
                        _original_uid, this.toString));
        }
    }

    /** Execute the configured process and capture output.
      *
      * Params:
      *     max_output = max size of output to capture.
      *
      * Returns:
      *     ProcessResult instance that contains output and exit-code
      *     of program
      *
      **/
    auto execute(in size_t max_output=size_t.max) {
        setUpProcess();
        auto res = std.process.execute(
            [_program] ~ _args,
            _env,
            _config,
            max_output,
            _workdir);
        tearDownProcess();
        return ProcessResult(_program, _args.idup, res.status, res.output);
    }

    /// Spawn process
    auto spawn(File stdin=std.stdio.stdin,
               File stdout=std.stdio.stdout,
               File stderr=std.stdio.stderr) {
        setUpProcess();
        auto res = std.process.spawnProcess(
            [_program] ~ _args,
            stdin,
            stdout,
            stderr,
            _env,
            _config,
            _workdir);
        tearDownProcess();
        return res;
    }

    /// Pipe process
    auto pipe(in Redirect redirect=Redirect.all) {
        setUpProcess();
        auto res = std.process.pipeProcess(
            [_program] ~ _args,
            redirect,
            _env,
            _config,
            _workdir);
        tearDownProcess();
        return res;
    }

    /** Replace current process by executing program as configured by
      * Process instance.
      *
      * Under the hood, this method will call $(REF execvpe, std, process) or
      * $(REF execvp, std, process).
      **/
    version(Posix) void execv() @system {
        import std.algorithm;
        import std.array;

        if (_workdir)
            // Change working directory, when needed before executing the program
            std.file.chdir(_workdir);

        if (!_env) {
            /* Run the program, and in case when it could not be started for
             * some reason, throw exception.
             *
             * For more info, see docs: https://dlang.org/library/std/process/execv.html
             */
            enforce!ProcessException(
                std.process.execvp(_program, [_program] ~ _args) != -1,
                "Cannot exec program %s".format(this));

            /* This will not be executed in any way, because on success
             * the current process will be replaced and on failure exception will be thrown.
             * but add it here to make code look consistent.
             */
            return;
        }

        /* In case when we have environment specified, we have to
         * call `execvpe` function, and thus we have to convert environment
         * variables to format suitable for this function
         * (array of strings in format `key=value`
         */
        string[] env_arr = _env.byKeyValue.map!(
            (i) => "%s=%s".format(i.key, i.value)
        ).array;
        enforce!ProcessException(
            std.process.execvpe(_program, [_program] ~ _args, env_arr) != -1,
            "Cannot exec program %s".format(this));
    }
}


// Test simple api
@safe unittest {
    import unit_threaded.assertions;

    auto process = Process("my-program")
        .withArgs("--verbose", "--help")
        .withEnv("MY_VAR", "42")
        .inWorkDir("/my/path");
    process._program.should == "my-program";
    process._args.should == ["--verbose", "--help"];
    process._env.should == ["MY_VAR": "42"];
    process._workdir.should == "/my/path";
    process.toString.should ==
        "Program: %s, args: %s, env: %s, workdir: %s".format(
            process._program, process._args.join(" "),
            process._env, process._workdir);

    // Change some params of the process
    process.setWorkDir(Path("/some/other/path"));
    process.setEnv([
        "MY_VAR_2": "72",
    ]);
    process.addArgs("arg2", "arg3");

    // Check that changes took effect
    process._program.should == "my-program";
    process._args.should == ["--verbose", "--help", "arg2", "arg3"];
    process._env.should == ["MY_VAR": "42", "MY_VAR_2": "72"];
    process._workdir.should == "/some/other/path";
    process.toString.should ==
        "Program: %s, args: %s, env: %s, workdir: %s".format(
            process._program, process._args.join(" "),
            process._env, process._workdir);
}

/// Test simple execution of the script
@safe unittest {
    import std.string;
    import std.ascii : newline;

    import unit_threaded.assertions;

    auto temp_root = createTempPath();
    scope(exit) temp_root.remove();

    version(Posix) {
        import std.conv: octal;
        auto script_path = temp_root.join("test-script.sh");
        script_path.writeFile(
            "#!" ~ nativeShell ~ newline ~
            `echo "Test out: $1 $2"` ~ newline);
        // Add permission to run this script
        script_path.setAttributes(octal!755);
    } else version(Windows) {
        auto script_path = temp_root.join("test-script.cmd");
        script_path.writeFile(
            "@echo off" ~ newline ~
            "echo Test out: %1 %2" ~ newline);
    }

    // Test the case when process executes fine
    auto result = Process(script_path)
        .withArgs("Hello", "World", "test")
        .execute
        .ensureOk;
    result.status.should == 0;
    result.output.chomp.should == "Test out: Hello World";
    result.isOk.shouldBeTrue;
    result.isNotOk.shouldBeFalse;
    // When we expect different successful exit-code
    result.isOk(42).shouldBeFalse;
    result.isNotOk(42).shouldBeTrue;
    result.ensureOk(42).shouldThrow!ProcessException;
}

/// Test simple execution of the script that handles environment variables
@safe unittest {
    import std.string;
    import std.ascii : newline;

    import unit_threaded.assertions;

    auto temp_root = createTempPath();
    scope(exit) temp_root.remove();

    version(Posix) {
        import std.conv: octal;
        auto script_path = temp_root.join("test-script.sh");
        script_path.writeFile(
            "#!" ~ nativeShell ~ newline ~
            `echo "Test out: $1 $2, $MY_PARAM_1 $MY_PARAM_2"` ~ newline);
        // Add permission to run this script
        script_path.setAttributes(octal!755);
    } else version(Windows) {
        auto script_path = temp_root.join("test-script.cmd");
        script_path.writeFile(
            "@echo off" ~ newline ~
            "echo Test out: %1 %2, %MY_PARAM_1% %MY_PARAM_2%" ~ newline);
    }

    // Test the case when process executes fine
    auto result = Process(script_path)
        .withArgs("Hello")
        .addArgs("World")
        .withEnv("MY_PARAM_1", "the")
        .withEnv("MY_PARAM_2", "Void")
        .execute
        .ensureOk;
    result.status.should == 0;
    result.output.chomp.should == "Test out: Hello World, the Void";
    result.isOk.shouldBeTrue;
    result.isNotOk.shouldBeFalse;
    // When we expect different successful exit-code
    result.isOk(42).shouldBeFalse;
    result.isNotOk(42).shouldBeTrue;
    result.ensureOk(42).shouldThrow!ProcessException;
}
