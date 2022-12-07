## .. image:: https://raw.githubusercontent.com/treeform/nimdocs/master/docs/nimdocsBanner.png
##
## Nim Docs - generate docs for any GitHub Nim project.
##
## I got tried of building Nim docs for all of my many projects.
## I created this site that auto generates the docs for me based on the URL.
## Going to https://nimdocs.com/treeform/pixie will just clone the
## https://github.com/treeform/pixie repo and generate the docs.
##
## If you want to be included in the allowed authors list, open a pull request.
##
## Features:
## ---------
##
## * Check if the docs are up to date with GitHub.
## * Clone new repositories automatically.
## * Add source links back to github.com.
## * Generates docs for all files in the repo.

import mimetypes, os, osproc, strformat, strtabs, strutils, times, mummy

const allowedAuthorsList = @[
  "treeform",
  "guzba",
  "nim-lang",
  "beef331"
]

var
  gitPullTime: float64
  gitPullRateLimit = 60.0 # seconds
  gitCloneTime: float64
  gitCloneRateLimit = 5.0 # seconds

proc handler(request: Request) =

  # Handle static files.
  if request.uri == "/":
    let html = &"""<meta http-equiv="refresh" content="0; url=/treeform/nimdocs/nimdocs.html" />"""
    var headers: HttpHeaders
    headers["Content-Type"] = "text/html"
    request.respond(200, headers, html)
    return

  # Handle github urls.
  let
    parts = request.uri.strip(chars = {'/'}).split('/')

  if parts.len < 2:
    var headers: HttpHeaders
    headers["Content-Type"] = "text/html"
    request.respond(
      404,
      headers,
      "<h1>404: not found. /user/repo Required.</h1>",
    )
    return

  let
    author = parts[0]
    repo = parts[1]
    gitUrl = &"https://github.com/{author}/{repo}"

  # Only allow registered authors.
  if author notin allowedAuthorsList:
    var headers: HttpHeaders
    headers["Content-Type"] = "text/html"
    request.respond(
      404,
      headers,
      &"<h1>404: https://github.com/{author}/* not allowed</h1>"
    )
    return

  var needsDocs = false
  var output = ""

  proc showLog() =
    echo 500
    echo output
    var headers: HttpHeaders
    headers["Content-Type"] = "text/plain"
    request.respond(500, headers, output)

  discard existsOrCreateDir("repos" / author)

  if dirExists("repos" / author / repo):
    if gitPullTime + gitPullRateLimit < epochTime():
      gitPullTime = epochTime()
      let gitUpdate = &"git pull"
      echo gitUpdate
      let res = execCmdEx(gitUpdate, workingDir = "repos" / author / repo)
      output.add res[0]
      echo res
      if res[1] != 0:
        showLog()
        return
      if "changed" in res[0]:
        needsDocs = true
    else:
      output.add "Rate limiting git pull"

  else:
    if gitCloneTime + gitCloneRateLimit < epochTime():
      gitCloneTime = epochTime()
      let gitClone = &"git clone {gitUrl} repos/{author}/{repo}"
      echo gitClone
      let res = execCmdEx(
        gitClone,
        env = {
          "GIT_TERMINAL_PROMPT": "0"
        }.newStringTable
      )
      output.add res[0]
      if res[1] != 0:
        showLog()
        return
      needsDocs = true
    else:
      output.add "Rate limiting git clone"

  if not dirExists("repos" / author / repo):
    showLog()
    return

  if needsDocs:
    block:
      let nimbleDevelop = &"nimble develop -y"
      echo nimbleDevelop
      let res = execCmdEx(nimbleDevelop, workingDir = "repos" / author / repo)
      if res[1] != 0:
        output.add res[0]
        showLog()
        return

    block:
      let nimbeDoc = &"nim doc --index:on --project --out:docs --hints:off --git.url:{gitUrl} --git.commit:master src/{repo}.nim "
      echo nimbeDoc
      let res = execCmdEx(nimbeDoc, workingDir = "repos" / author / repo)
      if res[1] != 0:
        output.add res[0]
        showLog()
        return

  var filePath = ""
  echo parts.len, " ", parts
  if parts.len > 2:
    filePath = join(parts[2..^1], "/")
  else:
    let html = &"""<meta http-equiv="refresh" content="0; url=/{author}/{repo}/{repo}.html" />"""
    var headers: HttpHeaders
    headers["Content-Type"] = "text/html"
    request.respond(200, headers, html)
    return

  filePath = "repos" / author / repo / "docs" / filePath

  echo filePath

  var m = newMimetypes()

  if fileExists(filePath):
    let data = readFile(filePath)
    var headers: HttpHeaders
    headers["Content-Type"] = m.getMimetype(filePath.splitFile.ext)
    request.respond(200, headers, data)
  else:
    var headers: HttpHeaders
    headers["Content-Type"] = "text/html"
    request.respond(404, headers, "<h1>404: not found</h1>")

# Make sure the repos directory exists
createDir("repos")

let server = newServer(handler)
server.serve(Port(1180))
