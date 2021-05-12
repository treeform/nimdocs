import times, osproc, mimetypes, asynchttpserver, asyncdispatch, print, strutils, strformat, os

var checkAgain: float64

var server = newAsyncHttpServer()
proc cb(req: Request) {.async.} =

  if req.url.path == "/":
    await req.respond(Http200, "TODO: index", newHttpHeaders())
    return

  if req.url.path == "/favicon.ico":
    await req.respond(Http200, "TODO: icon", newHttpHeaders())
    return

  let
    parts = req.url.path.strip(chars={'/'}).split('/')
    author = parts[0]
    repo = parts[1]
    gitUrl = &"https://github.com/{author}/{repo}"

  if author notin @["treeform", "guzba", "nim-lang"]:
    await req.respond(Http404, &"<h1>404: https://github.com/{author}/* not allowed</h1>", newHttpHeaders({
      "Content-Type": "text/html"
    }))
    return

  discard existsOrCreateDir("repos" / author)

  proc genDocs() =
    let nimbleDevelop = &"nimble develop -y"
    print nimbleDevelop
    print execCmdEx(nimbleDevelop, workingDir = "repos" / author / repo)

    let nimbeDoc = &"nim doc --index:on --project --out:docs --hints:off --git.url:{gitUrl} --git.commit:master src/{repo}.nim "
    print nimbeDoc
    print execCmdEx(nimbeDoc, workingDir = "repos" / author / repo)

  if checkAgain + 10.0 < epochTime():
    checkAgain = epochTime()
    if existsDir("repos" / author / repo):
      let gitUpdate = &"git pull"
      print gitUpdate
      let output = execCmdEx(gitUpdate, workingDir = "repos" / author / repo)
      if output[0] != "Already up-to-date.\n":
        genDocs()

    else:
      let gitClone = &"git clone {gitUrl} repos/{author}/{repo}"
      print gitClone
      print execCmdEx(gitClone)

      genDocs()

  if not existsDir("repos" / author / repo):
    await req.respond(Http200, "generating...", newHttpHeaders())
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
  waitFor server.serve(Port(8080), cb)
