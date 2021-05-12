## # Nim docs - generate a doc for any github nim project.
##
## I got tried of building nim docs for all of my many projects. I create this site that auto generates the docs for me based on the url. Going to https://nimdocs.com/treeform/pixie will just clone the https://github.com/treeform/pixie and generate the docs with index for all files.
##
## ## Features:
##
## * Check if the docs are up to date with git.
## * Clone new repositories if one just goes to them.
## * Add source links back to github.com.
## * Generates docs for all files in the repo.

import asyncdispatch, asynchttpserver, mimetypes, os, osproc, print, strformat,
    strtabs, strutils, times

var
  gitPullTime: float64
  gitPullRateLimit = 60.0 # seconds
  gitCloneTime: float64
  gitCloneRateLimit = 5.0 # seconds

var server = newAsyncHttpServer()
proc cb(req: Request) {.async.} =

  # Handle static files.
  if req.url.path == "/":
    let html = &"""<meta http-equiv="refresh" content="0; url=/treeform/nimdocs/nimdocs.html" />"""
    await req.respond(Http200, html, newHttpHeaders({
      "Content-Type": "text/html"
    }))
    return
  if req.url.path == "/favicon.ico":
    await req.respond(Http200, "TODO: icon", newHttpHeaders())
    return

  # Handle github urls.
  let
    parts = req.url.path.strip(chars = {'/'}).split('/')
    author = parts[0]
    repo = parts[1]
    gitUrl = &"https://github.com/{author}/{repo}"

  # Only allow registered authors.
  if author notin @["treeform", "guzba", "nim-lang"]:
    await req.respond(
      Http404,
      &"<h1>404: https://github.com/{author}/* not allowed</h1>",
      newHttpHeaders({
        "Content-Type": "text/html"
      })
    )
    return

  var needsDocs = false
  var output = ""

  proc showLog() {.async.} =
    print 500
    echo output
    await req.respond(Http500, output, newHttpHeaders())

  discard existsOrCreateDir("repos" / author)

  if dirExists("repos" / author / repo):
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
      if "changed" in res[0]:
        needsDocs = true
    else:
      output.add "Rate limiting git pull"

  else:
    if gitCloneTime + gitCloneRateLimit < epochTime():
      gitCloneTime = epochTime()
      let gitClone = &"git clone {gitUrl} repos/{author}/{repo}"
      print gitClone
      let res = execCmdEx(
        gitClone,
        env = {
          "GIT_TERMINAL_PROMPT": "0"
        }.newStringTable
      )
      output.add res[0]
      if res[1] != 0:
        await showLog()
        return
      needsDocs = true
    else:
      output.add "Rate limiting git clone"

  if not dirExists("repos" / author / repo):
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

  if fileExists(filePath):
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
