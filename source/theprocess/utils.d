/** Various utilities related to processes
  **/
module theprocess.utils;

private import std.format;
private import std.process;
private import std.file;
private import std.stdio;
private import std.exception;
private import std.string: join;
private import std.typecons;


private import thepath;


/** Resolve program name according to system path
  *
  * Params:
  *     program = name of program to find
  * Returns:
  *     Nullable!Path to program.
  **/
@safe Nullable!Path resolveProgram(in string program) {
    import std.path: pathSeparator;
    import std.array: split;
    foreach(sys_path; environment["PATH"].split(pathSeparator)) {
        auto sys_program_path = Path(sys_path).join(program);
        if (!sys_program_path.exists)
            continue;

        // TODO: check with lstat if link is not broken
        version(Posix) {
            import core.sys.posix.sys.stat: S_IXUSR, S_IXGRP, S_IXOTH;
            if (!(sys_program_path.getAttributes() & (S_IXUSR | S_IXGRP | S_IXOTH)))
                continue;
        }

        return sys_program_path.nullable;
    }
    return Nullable!Path.init;
}


///
version(Posix) unittest {
    import unit_threaded.assertions;

    resolveProgram("sh").isNull.shouldBeFalse;

    version(OSX)
        resolveProgram("sh").get.toString.shouldEqual("/bin/sh");
    else
        resolveProgram("sh").get.toString.shouldEqual("/usr/bin/sh");

    resolveProgram("unexisting_program").isNull.shouldBeTrue;
}


/** Check whether a process with the given PID is currently running.
  *
  * On Posix this uses kill(pid, 0): no signal is sent, but the kernel
  * validates whether the target process exists and the caller has permission
  * to signal it.  ESRCH ("no such process") is the only errno value that
  * conclusively means the process is gone.
  *
  * On Windows this opens a query handle via OpenProcess and reads the exit
  * code with GetExitCodeProcess.  If the handle cannot be opened the
  * function returns false (process absent or inaccessible).
  *
  * Params:
  *     pid = OS-level process identifier.  Obtain it from
  *           std.process.Pid.processID or any other source.
  *
  * Returns:
  *     true if the process appears to be running, false otherwise.
  **/
@trusted bool isProcessRunning(int pid) nothrow {
    version(Posix) {
        import core.sys.posix.signal : kill;
        import core.stdc.errno : errno, ESRCH;

        if (kill(pid, 0) == 0) return true;
        return errno != ESRCH;
    } else version(Windows) {
        import core.sys.windows.winbase : OpenProcess, CloseHandle, GetExitCodeProcess;
        import core.sys.windows.winnt : PROCESS_QUERY_INFORMATION, STILL_ACTIVE;
        import core.sys.windows.basetsd : DWORD;

        auto handle = OpenProcess(PROCESS_QUERY_INFORMATION, false, cast(DWORD) pid);
        if (handle is null) return false;
        scope(exit) CloseHandle(handle);
        DWORD code;
        if (!GetExitCodeProcess(handle, &code)) return false;
        return code == STILL_ACTIVE;
    } else {
        static assert(false, "isProcessRunning is not implemented for this platform");
    }
}


/// isProcessRunning returns true for a live process and false after it exits
unittest {
    import unit_threaded.assertions;
    import std.process : spawnProcess, kill, wait;

    version(Posix) {
        auto pid = spawnProcess(["sleep", "10"]);
    } else version(Windows) {
        auto pid = spawnProcess(["cmd", "/c", "timeout", "/t", "10", "/nobreak"]);
    }
    int rawPid = pid.processID;

    isProcessRunning(rawPid).shouldBeTrue;

    pid.kill();
    pid.wait();

    isProcessRunning(rawPid).shouldBeFalse;
}


