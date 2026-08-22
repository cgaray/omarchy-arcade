.pragma library

.import "Library.js" as Library

// The application layer both QML surfaces talk to. Views render what this
// file returns and never import Library.js themselves -- one seam, tested
// here, instead of view-model knowledge spread across two object trees.

function parseScan(raw) {
  return Library.parseLibrary(raw)
}

function rebuild(games, query, system, libraryLimit, continueLimit, savedOnly, sortMode) {
  var list = games || []
  var resumableTotal = 0
  var i
  for (i = 0; i < list.length; i++) {
    if (list[i].resumeAt > 0 && list[i].resumeSlot !== "") resumableTotal++
  }

  if (savedOnly) list = list.filter(function (game) { return game.resumeAt > 0 })
  var wanted = String(system || "")
  if (wanted) {
    var systems = Library.systemsOf(list)
    var present = false
    for (var s = 0; s < systems.length; s++) {
      if (systems[s].system === wanted) { present = true; break }
    }
    if (!present) wanted = ""
  }

  var rows = Library.filterGames(list, query, libraryLimit, wanted)
  var mode = String(sortMode || "")
  if (mode) {
    rows.sort(function (a, b) {
      if (mode === "added" && b.addedAt !== a.addedAt) return b.addedAt - a.addedAt
      if (mode === "save" && b.resumeAt !== a.resumeAt) return b.resumeAt - a.resumeAt
      if (mode === "played" && b.lastPlayed !== a.lastPlayed) return b.lastPlayed - a.lastPlayed
      var ta = String(a.title || "").toLowerCase()
      var tb = String(b.title || "").toLowerCase()
      return ta < tb ? -1 : (ta > tb ? 1 : 0)
    })
  // Without an explicit desktop sort, browsing reads best grouped by system.
  // Searching keeps relevance ranking instead.
  } else if (!String(query || "").trim()) {
    rows.sort(function (a, b) {
      var ka = a.sysKey || Library.systemKey(a)
      var kb = b.sysKey || Library.systemKey(b)
      if (ka !== kb) return ka < kb ? -1 : 1
      var ta = String(a.title || "").toLowerCase()
      var tb = String(b.title || "").toLowerCase()
      return ta < tb ? -1 : (ta > tb ? 1 : 0)
    })
  }

  return {
    systemFilter: wanted,
    continueRows: (!query && continueLimit > 0) ? Library.resumableIn(list, wanted, continueLimit) : [],
    libraryRows: rows,
    systems: Library.systemsOf(list),
    resumableTotal: resumableTotal
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

// Display formatting, routed through this seam so views keep a single import.
function formatAgo(epochSeconds, nowSeconds) {
  return Library.formatAgo(epochSeconds, nowSeconds)
}

function systemAndCore(game) {
  return Library.systemAndCore(game)
}

function playSummary(game, nowSeconds) {
  return Library.playSummary(game, nowSeconds)
}

function choosableExtensions(extensions) {
  return Library.choosableExtensions(extensions)
}

function undecidedExtensions(extensions) {
  return Library.undecidedExtensions(extensions)
}

function highlightTitle(raw, query, accent) {
  return Library.highlightTitle(raw, query, accent)
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    parseScan: parseScan,
    rebuild: rebuild,
    launchRequest: launchRequest,
    fingerprintChanged: fingerprintChanged,
    formatAgo: formatAgo,
    systemAndCore: systemAndCore,
    playSummary: playSummary,
    choosableExtensions: choosableExtensions,
    undecidedExtensions: undecidedExtensions,
    highlightTitle: highlightTitle
  }
}
