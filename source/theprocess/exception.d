module theprocess.exception;

private import std.exception;


/// Exception to be raise by Process struct
class ProcessException : Exception
{
    mixin basicExceptionCtors;
}



