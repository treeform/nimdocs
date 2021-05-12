import times, osproc, mimetypes, asynchttpserver, asyncdispatch, print, strutils, strformat, os, strtabs

var
  gitPullTime: float64
  gitPullRateLimit = 60.0 # seconds
  gitCloneTime: float64
  gitCloneRateLimit = 5.0 # seconds

var server = newAsyncHttpServer()
proc cb(req: Request) {.async.} =

  # Handle static files.
  if req.url.path == "/":
    await req.respond(Http200, "TODO: index", newHttpHeaders())
    return
  if req.url.path == "/favicon.ico":
    await req.respond(Http200, "TODO: icon", newHttpHeaders())
    return

  # Handle github urls.
  let
    parts = req.url.path.strip(chars={'/'}).split('/')
    author = parts[0]
    repo = parts[1]
    gitUrl = &"https://github.com/{author}/{repo}"

  # Only allow registered authors.
  if author notin @["treeform", "guzba", "nim-lang"]:
    await req.respond(Http404, &"<h1>404: https://github.com/{author}/* not allowed</h1>", newHttpHeaders({
      "Content-Type": "text/html"
    }))
    return

  var needsDocs = false
  var output = ""

  proc showLog() {.async.} =
    print 500
    echo output
    await req.respond(Http500, output, newHttpHeaders())

  discard existsOrCreateDir("repos" / author)

  if existsDir("repos" / author / repo):
    if gitPullTime + gitPullRateLimit < epochTime():
      gitPullTime = epochTime()
      let gitUpdate = &"git pull"
      print gitUpdate
      let res = execCmdEx(gitUpdate, workingDir = "repos" / author / repo)
      output.add res[0]
      print res
      if res[1] != 0:
        await showLog()
        return
      if res[0] notin ["Already up-to-date.\n", "Already up to date.\n"]:
        needsDocs = true
    else:
      output.add "Rate limiting git pull"

  else:
    if gitCloneTime + gitCloneRateLimit < epochTime():
      gitCloneTime = epochTime()
      let gitClone = &"git clone {gitUrl} repos/{author}/{repo}"
      print gitClone
      let res = execCmdEx(gitClone, env = {"GIT_TERMINAL_PROMPT": "0"}.newStringTable)
      output.add res[0]
      if res[1] != 0:
        await showLog()
        return
      needsDocs = true
    else:
      output.add "Rate limiting git clone"

  if not existsDir("repos" / author / repo):
    await showLog()
    return

  if needsDocs:
    block:
      let nimbleDevelop = &"nimble develop -y"
      print nimbleDevelop
      let res = execCmdEx(nimbleDevelop, workingDir = "repos" / author / repo)
      if res[1] != 0:
        output.add res[0]
        await showLog()
        return

    block:
      let nimbeDoc = &"nim doc --index:on --project --out:docs --hints:off --git.url:{gitUrl} --git.commit:master src/{repo}.nim "
      print nimbeDoc
      let res = execCmdEx(nimbeDoc, workingDir = "repos" / author / repo)
      if res[1] != 0:
        output.add res[0]
        await showLog()
        return

  var filePath = ""
  print parts.len, parts
  if parts.len > 2:
    filePath = join(parts[2..^1], "/")
  else:
    let html = &"""<meta http-equiv="refresh" content="0; url=/{author}/{repo}/{repo}.html" />"""
    await req.respond(Http200, html, newHttpHeaders({
      "Content-Type": "text/html"
    }))
    return

  filePath = "repos" / author / repo / "docs" / filePath

  print filePath

  var m = newMimetypes()

  if existsFile(filePath):
    let data = readFile(filePath)
    await req.respond(Http200, data, newHttpHeaders({
      "Content-Type": m.getMimetype(filePath.splitFile.ext)
    }))
  else:
    await req.respond(Http404, "<h1>404: not found</h1>", newHttpHeaders({
      "Content-Type": "text/html"
    }))


when isMainModule:
  waitFor server.serve(Port(80), cb)