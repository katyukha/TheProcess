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
private import std.format: format;

version(Posix) {
    private import core.sys.posix.unistd;
}

private import thepath;

private import theprocess.utils;
private import theprocess.exception: ProcessException;


/** Replace every occurrence of the masked values in the text by `***`.
  *
  * Longer values are replaced first, thus a value that contains another
  * masked value is not half revealed.
  **/
private string maskValues(in string text, in string[] masked) @safe pure {
    import std.algorithm.sorting: sort;
    import std.array: replace;

    string result = text.idup;
    foreach(value; masked.dup.sort!((a, b) => a.length > b.length))
        result = result.replace(value, "***");
    return result;
}


/** Process result, produced by 'execute' method of Process.
  **/
@safe immutable struct ProcessResult {
    /// The program that was invoked to obtain this result.
    private string _program;

    /// The arguments passed to the program to obtain this result.
    private string[] _args;

    /// The values that must not appear in messages built from this result.
    private string[] _masked;

    /// exit code of the process
    int status;

    /// text output of the process
    string output;

    // Do not allow to create records without params
    @disable this();

    private pure this(
            in string program,
            immutable string[] args,
            immutable string[] masked,
            in int status,
            in string output) nothrow {
        this._program = program.idup;
        this._args = args;
        this._masked = masked;
        this.status = status;
        this.output = output.idup;
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
      *         to message on failure. The values masked on the process
      *         (see $(LREF Process.setMasked)) are replaced by `***` in the
      *         attached output.
      *     expected = expected exit-code, if differ, then
      *         exception will be thrown.
      **/
    auto ref ensureStatus(E : Throwable = ProcessException)(
            in string msg, in bool add_output, in int expected=0) const {
        enforce!E(
            isOk(expected),
            !add_output ? msg : msg ~ "\nOutput: " ~ maskValues(output, _masked));
        return this;
    }

    /// ditto
    auto ref ensureStatus(E : Throwable = ProcessException)(
            in string msg, in int expected=0) const {
        return ensureStatus!E(
            msg,
            false,
            expected);
    }

    /// ditto
    auto ref ensureStatus(E : Throwable = ProcessException)(in bool add_output, in int expected=0) const {
        return ensureStatus!E(
            maskValues(
                "Program %s with args %s failed! Expected exit-code %s, got %s.".format(
                    _program, _args, expected, status),
                _masked),
            add_output,
            expected);
    }

    /// ditto
    auto ref ensureStatus(E : Throwable = ProcessException)(in int expected=0) const {
        return ensureStatus!E(false, expected);
    }

    /// ditto
    alias ensureOk = ensureStatus;

}


/** This struct is used to prepare configuration for process and run it.
  *
  * The following methods of running a process are supported:
  *
  * - execute: run process and catch its output and exit code.
  * - spawn: spawn the process in background, and optionally pipe its output.
  * - pipe: spawn the process and attach configurable pipes to catch output.
  *
  * The configuration of a process can be done like so:
  *
  * 1. Create the `Process` instance specifying the program to run.
  * 2. Apply your desired configuration (args, env, workDir)
  *    via calls to one of the corresponding methods.
  * 3. Run one of `execute`, `spawn` or `pipe` methods, that will actually
  *    start the process.
  *
  * Configuration methods come in two families with distinct semantics:
  *
  * - `set*` / `add*` methods mutate the current instance in place and return
  *   `void`, making them suitable for conditional modification of an
  *   already-stored `Process` variable.
  * - `with*` / `in*` methods return a new `Process` by value, leaving the
  *   original unchanged, making them safe to use in chained expressions.
  *   Most `set*` / `add*` method has a `with*` counterpart:
  *   `addArgs` ↔ `withArgs`,
  *   `setWorkDir` ↔ `inWorkDir`, `setEnv` ↔ `withEnv`, etc.
  *
  * Examples:
  * ---
  * // It is possible to run process in following way:
  * auto result = Process("my-program")
  *         .withArgs("--verbose", "--help")
  *         .withEnv("MY_ENV_VAR", "MY_VALUE")
  *         .inWorkDir("my/working/directory")
  *         .execute()
  *         .ensureStatus!MyException("My error message on failure");
  * writeln(result.output);
  * ---
  * ---
  * // Also, in Posix system it is possible to run command as different user:
  * auto result = Process("my-program")
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
    private string[] _masked;
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
        _program = program.idup;
    }

    /// ditto
    this(in Path program) {
        _program = program.toAbsolute.toString;
    }

    /** Copy the process configuration. Could be useful when needed to run
      * command multipe times with slightly different configuration.
      * Returns new instance of process.
      **/
    Process copy() const {
        Process res = Process(this._program);

        res._config = this._config;

        if (this._args)
            res.setArgs(this._args);
        if (this._env)
            res.setEnv(this._env);
        if (this._workdir)
            res.setWorkDir(this._workdir);
        if (this._masked)
            res.setMasked(this._masked);

        version(Posix) {
            res._uid = this._uid;
            res._gid = this._gid;
            res._original_uid = this._original_uid;
            res._original_gid = this._original_gid;
        }
        return res;
    }

    /// Ensure that copy, setArgs, addArgs, and withArgs work correctly
    unittest {
        import unit_threaded.assertions;

        auto p = Process("some-test-program").withArgs("arg1", "arg2");
        p._args.should == ["arg1", "arg2"];

        // setArgs mutates in place (void return)
        p.setArgs("arg3", "arg4");
        p._args.should == ["arg3", "arg4"];

        // addArgs mutates in place (void return)
        p.addArgs("arg4b");
        p._args.should == ["arg3", "arg4", "arg4b"];

        // withArgs returns a new Process with args appended, without modifying the original
        auto p2 = p.withArgs("arg5", "arg6");
        p2._args.should == ["arg3", "arg4", "arg4b", "arg5", "arg6"];
        p._args.should == ["arg3", "arg4", "arg4b"];

        // withArgs on a fresh process works as expected (append to empty = set)
        auto p3 = Process("other-program").withArgs("arg7");
        p3._args.should == ["arg7"];
    }

    /** Return string representation of process to be started.
      *
      * The masked values (see $(LREF Process.setMasked)) are replaced
      * by `***`.
      **/
    string toString() const {
        return maskValues(
            "Program: %s, args: %s, env: %s, workdir: %s".format(
                _program, _args.join(" "), _env, _workdir),
            _masked);
    }

    /** Set arguments for the process
      *
      * Note, replaces currently configured args for the process with provided args
      *
      * Params:
      *     args = array of arguments to run program with
      **/
    void setArgs(in string[] args...) {
        _args = args.dup;
    }

    /** Return a new Process with the provided arguments appended,
      * leaving the original unchanged.
      *
      * This is the non-mutating counterpart of addArgs.
      * Can be called multiple times to progressively build up arguments.
      **/
    Process withArgs(in string[] args...) const {
        auto result = this.copy();
        result.addArgs(args);
        return result;
    }

    /** Add arguments to the process.
      *
      * This could be used if you do not know all the arguments for program
      * to run at single point, and you need to add it conditionally.
      *
      * Params:
      *     args = array of arguments to add
      *
      * Examples:
      * ---
      * auto program = Process("my-program")
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
    void addArgs(in string[] args...) {
        _args ~= args;
    }

    /** Append a single argument, returning a new Process (non-mutating).
      * Equivalent to withArgs.
      *
      * Examples:
      * ---
      * auto git = Process("git").withArgs("--git-dir", myPath);
      * (git ~ "clone" ~ url).execute.ensureOk;
      * ---
      **/
    Process opBinary(string op)(in string arg) const if (op == "~") {
        return this.withArgs(arg);
    }

    /** Append multiple arguments, returning a new Process (non-mutating).
      * Equivalent to withArgs.
      *
      * Examples:
      * ---
      * auto git = Process("git").withArgs("--git-dir", myPath);
      * (git ~ ["clone", url]).execute.ensureOk;
      * ---
      **/
    Process opBinary(string op)(in string[] args) const if (op == "~") {
        return this.withArgs(args);
    }

    /** Append a single argument in place (mutating).
      * Equivalent to addArgs.
      **/
    void opOpAssign(string op)(in string arg) if (op == "~") {
        this.addArgs(arg);
    }

    /** Append multiple arguments in place (mutating).
      * Equivalent to addArgs.
      **/
    void opOpAssign(string op)(in string[] args) if (op == "~") {
        this.addArgs(args);
    }

    /// Ensure that ~ and ~= work correctly
    unittest {
        import unit_threaded.assertions;

        auto p = Process("git").withArgs("--git-dir", "/my/path");

        // ~ with single string returns new Process, original unchanged
        auto p2 = p ~ "clone";
        p2._args.should == ["--git-dir", "/my/path", "clone"];
        p._args.should == ["--git-dir", "/my/path"];

        // ~ with string[] returns new Process, original unchanged
        auto p3 = p ~ ["clone", "https://example.com"];
        p3._args.should == ["--git-dir", "/my/path", "clone", "https://example.com"];
        p._args.should == ["--git-dir", "/my/path"];

        // ~ chains correctly
        auto p4 = p ~ "clone" ~ "https://example.com";
        p4._args.should == ["--git-dir", "/my/path", "clone", "https://example.com"];
        p._args.should == ["--git-dir", "/my/path"];

        // ~= with single string mutates in place
        auto p5 = p.copy();
        p5 ~= "status";
        p5._args.should == ["--git-dir", "/my/path", "status"];

        // ~= with string[] mutates in place
        auto p6 = p.copy();
        p6 ~= ["log", "--oneline"];
        p6._args.should == ["--git-dir", "/my/path", "log", "--oneline"];
    }

    /** Set work directory for the process to be started
      *
      * Params:
      *     workdir = working directory path to run process in
      **/
    void setWorkDir(in string workdir) {
        _workdir = workdir.idup;
    }

    /// ditto
    void setWorkDir(in Path workdir) {
        _workdir = workdir.toString.idup;
    }

    /** Return a new Process with the working directory set to the provided
      * path, leaving the original unchanged.
      **/
    Process inWorkDir(in string workdir) const {
        auto result = this.copy();
        result.setWorkDir(workdir);
        return result;
    }

    /// ditto
    Process inWorkDir(in Path workdir) const {
        auto result = this.copy();
        result.setWorkDir(workdir);
        return result;
    }

    /** Set environemnt for the process to be started.
      * Could be called multiple times to update environment.
      *
      * Params:
      *     env = associative array to update environment to run process with.
      **/
    void setEnv(in string[string] env) {
        foreach(i; env.byKeyValue)
            _env[i.key] = i.value;
    }

    /** Set environment variable (specified by key) to provided value
      *
      * Params:
      *     key = environment variable name
      *     value = environment variable value
      **/
    void setEnv(in string key, in string value) {
        _env[key.idup] = value.idup;
    }

    /** Return a new Process with the environment updated with the provided
      * key-value pairs, leaving the original unchanged.
      **/
    Process withEnv(in string[string] env) const {
        auto result = this.copy();
        result.setEnv(env);
        return result;
    }

    /// ditto
    Process withEnv(in string key, in string value) const {
        auto result = this.copy();
        result.setEnv(key, value);
        return result;
    }

    /** Mask the provided values in every text rendered for this process.
      *
      * Use it for secrets passed to the process (passwords, tokens), to keep
      * them out of logs. Each occurrence of a masked value is replaced
      * by `***` in:
      *
      * - the result of `toString`,
      * - the messages of exceptions thrown by this process,
      * - the default message of `ProcessResult.ensureStatus`,
      * - the output attached to the message of `ProcessResult.ensureStatus`.
      *
      * Only the value is replaced, not the whole argument that contains it,
      * thus the context stays readable: `https://user:***@host/repo`.
      *
      * `ProcessResult.output` is not masked: it is the data produced by the
      * program, and it is up to the caller to mask it when logging.
      *
      * Could be called multiple times to mask more values.
      * Empty values are ignored.
      *
      * Params:
      *     values = values to mask
      *
      * Examples:
      * ---
      * Process("git")
      *     .withArgs("clone", "https://user:%s@host/repo".format(password))
      *     .withMasked(password)
      *     .execute
      *     .ensureOk(true);
      * ---
      **/
    void setMasked(in string[] values...) {
        _masked ~= values;
    }

    /** Return a new Process with the provided values masked,
      * leaving the original unchanged.
      *
      * See $(LREF Process.setMasked) for details.
      **/
    Process withMasked(in string[] values...) const {
        auto result = this.copy();
        result.setMasked(values);
        return result;
    }

    /** Set environment variable (specified by key) to provided value,
      * and mask this value (see $(LREF Process.setMasked)).
      *
      * Params:
      *     key = environment variable name
      *     value = environment variable value, that must be kept out of logs
      **/
    void setSecretEnv(in string key, in string value) {
        setEnv(key, value);
        setMasked(value);
    }

    /** Return a new Process with the environment variable set to the
      * provided value and this value masked, leaving the original unchanged.
      **/
    Process withSecretEnv(in string key, in string value) const {
        auto result = this.copy();
        result.setSecretEnv(key, value);
        return result;
    }

    /// Ensure that masked values do not appear in text representation
    unittest {
        import unit_threaded.assertions;

        auto p = Process("git")
            .withArgs("clone", "https://user:s3cret@host/repo")
            .withMasked("s3cret")
            .withSecretEnv("GIT_TOKEN", "t0ken");

        p.toString.should ==
            `Program: git, args: clone https://user:***@host/repo, ` ~
            `env: ["GIT_TOKEN":"***"], workdir: `;

        // The process itself still gets the real values
        p._args.should == ["clone", "https://user:s3cret@host/repo"];
        p._env.should == ["GIT_TOKEN": "t0ken"];

        // Masks survive derivation of new process
        (p ~ "--depth=1").toString.should ==
            `Program: git, args: clone https://user:***@host/repo --depth=1, ` ~
            `env: ["GIT_TOKEN":"***"], workdir: `;

        // A value that contains another masked value is masked as a whole,
        // whatever the order the values were masked in.
        Process("prog")
            .withArgs("pass-and-more", "pass")
            .withMasked("pass", "pass-and-more")
            .toString.should == "Program: prog, args: *** ***, env: [], workdir: ";
    }

    /** Run process with new environment
      * (do not inherit environment variables from parent process)
      **/
    void setNewEnv() {
        _config.flags |= std.process.Config.Flags.newEnv;
    }

    /** Return a new Process configured to start with a fresh environment
      * (not inheriting parent environment variables), leaving the original
      * unchanged.
      **/
    Process withNewEnv() const {
        auto result = this.copy();
        result.setNewEnv();
        return result;
    }

    /** Set process configuration
      **/
    void setConfig(in std.process.Config config) {
        _config.flags = config.flags;
    }

    /** Return a new Process with the process configuration set to the
      * provided value, leaving the original unchanged.
      **/
    Process withConfig(in std.process.Config config) const {
        auto result = this.copy();
        result.setConfig(config);
        return result;
    }

    /** Set configuration flag for process to be started
      **/
    void setFlag(in std.process.Config.Flags flag) {
        _config.flags |= flag;
    }

    /// ditto
    void setFlag(in std.process.Config flags) {
        _config |= flags;
    }

    /** Return a new Process with the given configuration flag set,
      * leaving the original unchanged.
      **/
    Process withFlag(in std.process.Config.Flags flag) const {
        auto result = this.copy();
        result.setFlag(flag);
        return result;
    }

    /// ditto
    Process withFlag(in std.process.Config flags) const {
        auto result = this.copy();
        result.setFlag(flags);
        return result;
    }

    /** Apply Config.stderrPassThrough flag.
      * With this flag, stderr will not be captured,
      * but instead directly passed to console or terminal.
      **/
    void setStderrPassThrough() {
        setFlag(std.process.Config.stderrPassThrough);
    }

    /** Return a new Process with Config.stderrPassThrough set,
      * leaving the original unchanged.
      **/
    Process withStderrPassThrough() const {
        return withFlag(std.process.Config.stderrPassThrough);
    }

    /** Set UID to run process with
      *
      * Params:
      *     uid = UID (id of system user) to run process with
      *
      * Returns:
      *     reference to this (process instance)
      *
      **/
    version(Posix) void setUID(in uid_t uid) {
        _uid = uid;
    }

    /** Return a new Process configured to run with the given UID,
      * leaving the original unchanged.
      **/
    version(Posix) Process withUID(in uid_t uid) const {
        auto result = this.copy();
        result.setUID(uid);
        return result;
    }

    /** Set GID to run process with
      *
      * Params:
      *     gid = GID (id of system group) to run process with
      *
      * Returns:
      *     reference to this (process instance)
      *
      **/
    version(Posix) void setGID(in gid_t gid) {
        _gid = gid;
    }

    /** Return a new Process configured to run with the given GID,
      * leaving the original unchanged.
      **/
    version(Posix) Process withGID(in gid_t gid) const {
        auto result = this.copy();
        result.setGID(gid);
        return result;
    }

    /** Run process as specified user
      *
      * If this method applied, then the UID and GID to run process with
      * will be taked from record in passwd database
      *
      * Note, that only UID and GID are changed by default: the environment
      * of the process still describes the caller. In particular `HOME`,
      * `USER` and `LOGNAME` are inherited as is, thus the process runs as
      * one user, but its environment points at another one. This is what
      * other process libraries do too, but it is rarely what is needed when
      * privileges are dropped to a service user, because everything that
      * writes to the home directory will try to write to home directory of
      * the caller. Pass `userHomeDir` to point `HOME` at home directory of
      * the user the process runs as.
      *
      * The home directory is taken from the passwd database as is, the same
      * way `su` and `sudo -H` do it. It is not checked for existence: note
      * that `adduser --system` uses `/nonexistent` as home directory by
      * default, thus it is up to the caller to ensure that home directory of
      * the user is usable.
      *
      * In the same way, programs that take the name of the user from the
      * environment (for example `getpass.getuser` in Python) see the caller
      * instead of the user the process runs as. Pass `userLoginEnv` to set
      * `USER` and `LOGNAME` to the name of that user. `SHELL` is left as is:
      * the login shell of a service user is usually `nologin`, and it would
      * break the programs that run `$SHELL`.
      *
      * `HOME`, `USER` and `LOGNAME` are applied in the same way as any other
      * environment variable, thus an explicit `setEnv` applied later wins.
      *
      * Params:
      *     username = login of user to run process as
      *     userWorkDir = if set, run the process in home directory of that
      *         user, instead of the working directory of the caller.
      *     userHomeDir = if set, point `HOME` of the process at home
      *         directory of that user, instead of inheriting `HOME` of the
      *         caller.
      *     userLoginEnv = if set, set `USER` and `LOGNAME` of the process
      *         to the name of that user, instead of inheriting them from
      *         the caller.
      **/
    version(Posix) void setUser(
            in string username,
            in bool userWorkDir=false,
            in bool userHomeDir=false,
            in bool userLoginEnv=false) @trusted {
        auto user = getSystemUser(username);
        if (user.isNull)
            throw new ProcessException("User %s does not exist".format(username));

        _uid = user.get.uid;
        _gid = user.get.gid;

        if (userWorkDir)
            _workdir = user.get.homeDir;

        if (userHomeDir)
            _env["HOME"] = user.get.homeDir;

        if (userLoginEnv) {
            _env["USER"] = user.get.name;
            _env["LOGNAME"] = user.get.name;
        }
    }

    /** Return a new Process configured to run as the given user,
      * leaving the original unchanged.
      *
      * See $(LREF Process.setUser) for the meaning of the parameters.
      **/
    version(Posix) Process withUser(
            in string username,
            in bool userWorkDir=false,
            in bool userHomeDir=false,
            in bool userLoginEnv=false) @trusted const {
        auto result = this.copy();
        result.setUser(username, userWorkDir, userHomeDir, userLoginEnv);
        return result;
    }

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

            // TODO: It seems that in latest releases better preexec function was implemented
            //       Check it, may be it have sense to use it.
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
            // Restore original uid/gid after process started, then clear
            // the saved values so re-running this Process is safe.
            if (!_original_gid.isNull) {
                errnoEnforce(
                    setregid(_original_gid.get, -1) == 0,
                    "Cannot restore real GID to %s after process started: %s".format(
                        _original_gid, this.toString));
                _original_gid.nullify();
            }
            if (!_original_uid.isNull) {
                errnoEnforce(
                    setreuid(_original_uid.get, -1) == 0,
                    "Cannot restore real UID to %s after process started: %s".format(
                        _original_uid, this.toString));
                _original_uid.nullify();
            }
            _config.preExecFunction = null;
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
        scope(exit) tearDownProcess();
        auto res = std.process.execute(
            [_program] ~ _args,
            _env,
            _config,
            max_output,
            _workdir);
        return ProcessResult(
            _program, _args.idup, _masked.idup, res.status, res.output);
    }

    /// Spawn process
    auto spawn(File stdin=std.stdio.stdin,
               File stdout=std.stdio.stdout,
               File stderr=std.stdio.stderr) {
        setUpProcess();
        scope(exit) tearDownProcess();
        auto res = std.process.spawnProcess(
            [_program] ~ _args,
            stdin,
            stdout,
            stderr,
            _env,
            _config,
            _workdir);
        return res;
    }

    /// Pipe process
    auto pipe(in Redirect redirect=Redirect.all) {
        setUpProcess();
        scope(exit) tearDownProcess();
        auto res = std.process.pipeProcess(
            [_program] ~ _args,
            redirect,
            _env,
            _config,
            _workdir);
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

        if (!_gid.isNull && _gid.get != getgid) {
            // Change rgid and egid if needed
            errnoEnforce(
                setregid(_gid.get, _gid.get) == 0,
                "Cannot set real GID to %s before starting process: %s".format(
                    _gid, this.toString));
        }
        if (!_uid.isNull && _uid.get != getuid) {
            // Change ruid and euid if needed
            errnoEnforce(
                setreuid(_uid.get, _uid.get) == 0,
                "Cannot set real UID to %s before starting process: %s".format(
                    _uid, this.toString));
        }

        // Change working directory, when needed before executing the program
        if (_workdir)
            std.file.chdir(_workdir);

        // Prepare environment variable for process
        string[string] env;
        if (_config.flags & std.process.Config.Flags.newEnv)
            env = _env;
        else {
            // If we do not need new environment, then merge parent process
            // environment with environment configured for process execution.
            env = std.process.environment.toAA;
            foreach(i; _env.byKeyValue)
                env[i.key] = i.value;
        }

        /* We call `execvpe` function, thus we have to provide environment
         * variables in format suitable for this function
         * (array of strings in format `key=value`).
         * If there is no environment required, then we just need to provide
         * empty string.
         **/
        string[] env_arr = env.byKeyValue.map!(
            (i) => "%s=%s".format(i.key, i.value)
        ).array;
        enforce!ProcessException(
            std.process.execvpe(_program, [_program] ~ _args, env_arr) != -1,
            "Cannot exec program %s".format(this.toString));
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

    /* Do similar trick as in Phobos for portable newline output
     *
     * To avoid printing the newline characters, we use the echo|set trick on
     * Windows, and printf on POSIX (neither echo -n nor echo \c are portable).
     */
    version(Posix) {
        import std.conv: octal;
        auto script_path = temp_root.join("test-script.sh");
        script_path.writeFile(
            "#!" ~ nativeShell ~ newline ~
            `printf "Test out: $1 $2, $MY_PARAM_1 $MY_PARAM_2"` ~ newline);
        // Add permission to run this script
        script_path.setAttributes(octal!755);
    } else version(Windows) {
        auto script_path = temp_root.join("test-script.cmd");
        script_path.writeFile(
            `@echo off` ~ newline ~
            `echo|set /p DUMMY="Test out: %1 %2, %MY_PARAM_1% %MY_PARAM_2%"` ~ newline);
    }

    // Test the case when process executes fine
    auto result = Process(script_path)
        .withArgs("Hello")
        .withArgs("World")
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

    // Ensure that status is ok, if not ok, then raise error
    result.ensureOk(42).shouldThrow!ProcessException;

    // Optionally allow to print command output on failure with custom error message or with standard one.
    result.ensureOk("Custom error message", 42).shouldThrowWithMessage!ProcessException(
        "Custom error message");
    result.ensureOk("Error message", true, 42).shouldThrowWithMessage!ProcessException(
        "Error message\nOutput: %s".format("Test out: Hello World, the Void"));
    result.ensureOk(true, 42).shouldThrowWithMessage!ProcessException(
        "Program %s with args %s failed! Expected exit-code %s, got %s.\nOutput: %s".format(
            result._program, result._args, 42, 0, "Test out: Hello World, the Void"));
}

/// Test simple execution of the script with user (use current user)
version(Posix) @safe unittest {
    import std.string;
    import std.ascii : newline;

    import unit_threaded.assertions;

    auto temp_root = createTempPath();
    scope(exit) temp_root.remove();

    import std.conv: octal;
    auto script_path = temp_root.join("test-script.sh");
    script_path.writeFile(
        "#!" ~ nativeShell ~ newline ~
        `echo "Test out: $1 $2"` ~ newline);
    // Add permission to run this script
    script_path.setAttributes(octal!755);

    auto username = Process("whoami").execute.ensureOk(true).output.strip;

    // Test the case when process executes fine
    auto result = Process(script_path)
        .withArgs("Hello", "World", "test")
        .withUser(username)
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


/// Test simple execution of the script within user's home directory
version(Posix) @safe unittest {
    import std.string;
    import std.ascii : newline;

    import unit_threaded.assertions;

    // Change current working dir to /tmp
    Path.tempDir.chdir;

    auto current_user = Process("whoami").execute.ensureOk(true).output.strip;
    auto workdir = Process("pwd")
        .withUser(current_user)
        .execute
        .ensureOk(true)
        .output.strip;

    Path(workdir).realPath.should == Path.tempDir.realPath;

    workdir = Process("pwd")
        .withUser(current_user, true)
        .execute
        .ensureOk(true)
        .output.strip;

    Path(workdir).realPath.should == Path("~").realPath;
}


/// Test that HOME of the process could be set to home dir of the user
version(Posix) @safe unittest {
    import std.string;

    import unit_threaded.assertions;

    auto user = getCurrentUser();

    auto homeOf(in Process process) {
        return process
            .withArgs("-c", "echo $HOME")
            .execute
            .ensureOk(true)
            .output.strip;
    }

    // By default HOME of the caller is kept as is,
    // even if process runs as different user.
    homeOf(
        Process("sh")
            .withEnv("HOME", "/some/other/home")
            .withUser(user.name)
    ).should == "/some/other/home";

    // With userHomeDir, HOME points at home dir of the user.
    homeOf(
        Process("sh")
            .withEnv("HOME", "/some/other/home")
            .withUser(user.name, userHomeDir: true)
    ).should == user.homeDir;

    // HOME set explicitly after setting the user wins.
    homeOf(
        Process("sh")
            .withUser(user.name, userHomeDir: true)
            .withEnv("HOME", "/some/other/home")
    ).should == "/some/other/home";
}


/// Test that USER and LOGNAME of the process could be set to name of the user
version(Posix) @safe unittest {
    import std.string;

    import unit_threaded.assertions;

    auto user = getCurrentUser();

    auto loginOf(in Process process) {
        return process
            .withArgs("-c", "echo $USER:$LOGNAME")
            .execute
            .ensureOk(true)
            .output.strip;
    }

    auto caller = Process("sh")
        .withEnv("USER", "some-user")
        .withEnv("LOGNAME", "some-logname");

    // By default USER and LOGNAME of the caller are kept as is,
    // even if process runs as different user.
    loginOf(caller.withUser(user.name)).should == "some-user:some-logname";

    // With userLoginEnv, they name the user the process runs as.
    loginOf(caller.withUser(user.name, userLoginEnv: true))
        .should == user.name ~ ":" ~ user.name;
}


/// Test that masked values are kept out of the messages of failed process
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
            `printf "Test out: $1, $MY_TOKEN"` ~ newline);
        // Add permission to run this script
        script_path.setAttributes(octal!755);
    } else version(Windows) {
        auto script_path = temp_root.join("test-script.cmd");
        script_path.writeFile(
            `@echo off` ~ newline ~
            `echo|set /p DUMMY="Test out: %1, %MY_TOKEN%"` ~ newline);
    }

    auto result = Process(script_path)
        .withArgs("s3cret")
        .withMasked("s3cret")
        .withSecretEnv("MY_TOKEN", "t0ken")
        .execute;

    // The output itself is not masked
    result.output.chomp.should == "Test out: s3cret, t0ken";

    // Default message: both the args and the attached output are masked
    result.ensureOk(true, 42).shouldThrowWithMessage!ProcessException(
        "Program %s with args %s failed! Expected exit-code %s, got %s.\nOutput: %s".format(
            result._program, ["***"], 42, 0, "Test out: ***, ***"));

    // Custom message: the attached output is masked
    result.ensureOk("Error message", true, 42).shouldThrowWithMessage!ProcessException(
        "Error message\nOutput: Test out: ***, ***");
}
