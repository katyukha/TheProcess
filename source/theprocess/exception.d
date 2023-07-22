/** Module that defines exceptions that may be thrown when dealing with
  * processes spawned by this library.
  **/
module theprocess.exception;

private import std.exception;


/// Exception to be raise by Process struct
class ProcessException : Exception
{
    mixin basicExceptionCtors;
}



