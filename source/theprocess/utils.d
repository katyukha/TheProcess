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


