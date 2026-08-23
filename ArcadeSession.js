.pragma library

.import "Library.js" as Library

// The application layer both QML surfaces talk to. Views render what this
// file returns and never import Library.js themselves -- one seam, tested
// here, instead of view-model knowledge spread across two object trees.

// Scanner output arrives as tagged NDJSON; views feed lines into a builder
// and read the finished library off finish(), never holding the stream.
function createScanBuilder() {
  return Library.createScanBuilder()
}

function rebuild(games, query, system, libraryLimit, continueLimit, savedOnly, sortMode) {
  var list = games || []
  var resumableTotal = 0
  var i
  for (i = 0; i < list.length; i++) {
    if (list[i].resumeAt > 0 && list[i].resumeSlot !== "") resumableTotal++
  }

  if (savedOnly) list = list.filter(function (game) { return game.resumeAt > 0 })
  // Computed once: the presence check below and the returned chip row read
  // the same table.
  var systems = Library.systemsOf(list)
  var wanted = String(system || "")
  if (wanted) {
    var present = false
    for (var s = 0; s < systems.length; s++) {
      if (systems[s].system === wanted) { present = true; break }
    }
    if (!present) wanted = ""
  }

  // The count the headers should promise: everything the current filters
  // select, before the display cap trims what is actually rendered.
  // filterGames tallies both paths -- scored matches under a query, the
  // narrowed pool while browsing.
  var tally = {}
  var rows = Library.filterGames(list, query, libraryLimit, wanted, tally)
  var totalMatches = tally.matches
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
    totalMatches: totalMatches,
    systems: systems,
    resumableTotal: resumableTotal
  }
}

function launchRequest(game, resume, launcherPath, slot) {
  if (!game) return []
  var args = [launcherPath, "--core", game.core, "--rom", game.rom]
  // An explicitly chosen slot wins even over "start fresh" -- picking a
  // state from the inspector IS the resume gesture. Otherwise the old
  // contract holds: resume the newest state when asked, fresh when not.
  var useSlot = slot || (resume && game.resumeSlot) || ""
  if (useSlot) args.push("--slot", useSlot)
  return args
}

// Index of the active system in the filter row, All being 0.
function systemIndex(systems, system) {
  if (!system) return 0
  for (var i = 0; i < systems.length; i++)
    if (systems[i].system === system) return i + 1
  return 0
}

// The system `slot` steps along the filter row, All included: slot 0 is All,
// slot n is systems[n-1], and anything past the end is not a jump at all.
function systemAtSlot(systems, slot) {
  if (!slot) return ""
  return systems[slot - 1] ? systems[slot - 1].system : null
}

// Where cycling lands after delta steps around the filter row, All included.
// A single-system (or empty) library has nowhere to cycle, so the current
// filter comes back unchanged.
function nextSystem(systems, current, delta) {
  var count = systems.length + 1
  if (count <= 1) return current
  var at = (systemIndex(systems, current) + delta + count) % count
  return at === 0 ? "" : systems[at - 1].system
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
    createScanBuilder: createScanBuilder,
    rebuild: rebuild,
    launchRequest: launchRequest,
    systemIndex: systemIndex,
    systemAtSlot: systemAtSlot,
    nextSystem: nextSystem,
    fingerprintChanged: fingerprintChanged,
    formatAgo: formatAgo,
    systemAndCore: systemAndCore,
    playSummary: playSummary,
    choosableExtensions: choosableExtensions,
    undecidedExtensions: undecidedExtensions,
    highlightTitle: highlightTitle
  }
}
