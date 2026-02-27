/** Module that provides components to easily run other programs.
  **/
module theprocess;

public import theprocess.process: Process, ProcessResult;
public import theprocess.utils: resolveProgram, isProcessRunning;
public import theprocess.exception: ProcessException;
