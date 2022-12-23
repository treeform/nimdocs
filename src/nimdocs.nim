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

import mummy, mummy/routers, nimdocs/internal, std/locks, std/mimetypes, std/os,
    std/strformat, std/strutils, std/tables, std/times, webby

const
  reposDir = "repos"
  nimblesDir = "nimbles"
  repoPullRateLimit = 60.0 # Seconds
  allowedAuthorsList = @[
    "treeform",
    "guzba",
    "nim-lang",
    "beef331"
  ]

var
  lastPulledLock, nimbleLock: Lock
  lastPulled: Table[string, float64]
  mimeDb = newMimetypes()

initLock(lastPulledLock)
initLock(nimbleLock)

proc indexHandler(request: Request) =
  var headers: HttpHeaders
  headers["Location"] = "/treeform/nimdocs/nimdocs.html"
  request.respond(302, headers)

proc notFoundHandler(request: Request) =
  var headers: HttpHeaders
  headers["Content-Type"] = "text/html"
  request.respond(404, headers, "<h1>Not Found</h1>")

proc repoHandler(request: Request) =
  let
    url = parseUrl(request.uri)
    author = url.paths[0]
    repo = url.paths[1]
    githubUrl = &"https://github.com/{author}/{repo}"

  # Only allowed authors.
  if author notin allowedAuthorsList:
    var headers: HttpHeaders
    headers["Content-Type"] = "text/html"
    request.respond(404, headers, &"<h1>404 Not Found</h1>")
    return

  if url.paths.len == 2 or (url.paths.len == 3 and url.paths[2] == ""):
    var headers: HttpHeaders
    headers["Location"] = &"/{author}/{repo}/{repo}.html"
    request.respond(302, headers)
    return

  let
    repoDir = reposDir / author / repo
    nimbleDir = getCurrentDir() / nimblesDir / author / repo

  var needsPull, changed: bool

  {.gcsafe.}:
    withLock lastPulledLock:
      let lastPullDelta = epochTime() - lastPulled.getOrDefault(repoDir, 0)
      if lastPullDelta > repoPullRateLimit:
        needsPull = true
        lastPulled[repoDir] = epochTime()

  if needsPull:
    if dirExists(repoDir):
      # Run in this order to handle force-pushes
      let hash1 = runGitCmd("git rev-parse HEAD", workingDir = repoDir)
      discard runGitCmd("git fetch", workingDir = repoDir)
      discard runGitCmd("git reset --hard origin", workingDir = repoDir)
      let hash2 = runGitCmd("git rev-parse HEAD", workingDir = repoDir)
      if hash1 != hash2:
        changed = true
    else:
      discard runGitCmd(&"git clone --depth 1 {githubUrl} {repoDir}")
      changed = true

  if changed:
    withLock nimbleLock:
      try:
        createDir(getHomeDir() / ".config" / "nimble")
        writeFile(getHomeDir() / ".config/nimble/nimble.ini", &"nimbleDir = r\"{nimbleDir}\"\n")
        discard runNimCmd("nimble develop -y", workingDir = repoDir)
      finally:
        removeFile(getHomeDir() / ".config/nimble/nimble.ini")

    let branch =
      runGitCmd("git rev-parse --abbrev-ref HEAD", workingDir = repoDir).strip()
    discard runNimCmd(
      &"nim doc --clearNimblePath --NimblePath:\"{nimbleDir}/pkgs\" " &
      "--project --out:docs --hints:off " &
      &"--git.url:{githubUrl} --git.commit:{branch} src/{repo}.nim",
      workingDir = repoDir
    )

  for path in url.paths:
    if ".." in path:
      notFoundHandler(request)
      return

  let filePath = repoDir / "docs" / join(url.paths[2 .. ^1], "/")
  if fileExists(filePath):
    var headers: HttpHeaders
    {.gcsafe.}:
      headers["Content-Type"] = mimeDb.getMimetype(filePath.splitFile.ext)
    request.respond(200, headers, readFile(filePath))
  else:
    notFoundHandler(request)

var router: Router
router.get("/", indexHandler)
router.get("/*/**", repoHandler)
router.notFoundHandler = notFoundHandler

when isMainModule:
  # Make sure the repos directory exists
  createDir(reposDir)
  createDir(nimblesDir)

  let server = newServer(router)
  server.serve(Port(1180), "0.0.0.0")
