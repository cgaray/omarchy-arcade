.pragma library

.import "Library.js" as Library

function parseScan(raw) {
  return Library.parseLibrary(raw)
}

function rebuild(games, query, system, libraryLimit, continueLimit, savedOnly) {
  var list = games || []
  if (savedOnly) list = list.filter(function (game) { return game.resumeAt > 0 })
  var wanted = String(system || "")
  if (wanted) {
    var systems = Library.systemsOf(list)
    var present = false
    for (var i = 0; i < systems.length; i++) {
      if (systems[i].system === wanted) { present = true; break }
    }
    if (!present) wanted = ""
  }

  return {
    systemFilter: wanted,
    continueRows: (!query && continueLimit > 0) ? Library.resumableIn(list, wanted, continueLimit) : [],
    libraryRows: Library.filterGames(list, query, libraryLimit, wanted)
  }
}

function launchRequest(game, settings, resume, launcherPath) {
  if (!game) return []
  var config = settings || {}
  var args = [launcherPath, "--core", game.core, "--rom", game.rom]
  if (resume && game.resumeSlot) args.push("--slot", game.resumeSlot)
  if (config.silenceNotifications === false) args.push("--keep-notifications")
  if (config.stayAwake === false) args.push("--allow-idle")
  return args
}

function fingerprintChanged(previous, next) {
  var current = String(next || "").trim()
  return current.length > 0 && String(previous || "") !== "" && current !== String(previous)
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    parseScan: parseScan,
    rebuild: rebuild,
    launchRequest: launchRequest,
    fingerprintChanged: fingerprintChanged
  }
}
