import std/osproc, std/strtabs

proc runGitCmd*(cmd: string, workingDir = ""): string =
  let (output, exitCode) = execCmdEx(
    cmd,
    workingDir = workingDir,
    env = {
      "GIT_TERMINAL_PROMPT": "0"
    }.newStringTable()
  )
  if exitCode != 0:
    raise newException(CatchableError, "Git error: " & output)
  output

proc runNimCmd*(cmd, workingDir: string): string =
  let (output, exitCode) = execCmdEx(
    cmd,
    workingDir = workingDir
  )
  if exitCode != 0:
    raise newException(CatchableError, "Cmd error: " & output)
  output
