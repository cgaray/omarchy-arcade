// Pure library helpers for the Arcade overlay.
//
// Everything here is plain ES5-compatible JavaScript with no QML or Quickshell
// imports, so the same file loads under `.import` in Arcade.qml and under
// node in tests/library-test.js. Keep it that way: the moment this file needs
// a QML type, it stops being testable outside a running shell.

.pragma library

// Parse the JSON that omarchy-arcade-scan writes to stdout. A scanner that
// crashed or printed a warning is indistinguishable from one that found no
// games unless we tell them apart here, so a parse failure returns an explicit
// `error` rather than an innocent empty library.
function parseLibrary(raw) {
  var text = String(raw || "").trim()
  if (!text.length)
    return { games: [], meta: {}, error: "scanner produced no output" }

  var parsed
  try {
    parsed = JSON.parse(text)
  } catch (e) {
    return { games: [], meta: {}, error: "scanner output was not JSON" }
  }

  var games = Array.isArray(parsed.games) ? parsed.games : []
  var normalized = []
  for (var i = 0; i < games.length; i++) {
    var g = games[i]
    if (!g || !g.rom || !g.core) continue
    normalized.push({
      key: String(g.key || g.rom),
      title: String(g.title || ""),
      system: String(g.system || ""),
      core: String(g.core),
      coreName: String(g.coreName || ""),
      rom: String(g.rom),
      art: String(g.art || ""),
      resumeSlot: String(g.resumeSlot || ""),
      resumeArt: String(g.resumeArt || ""),
      resumeAt: Number(g.resumeAt || 0),
      lastPlayed: Number(g.lastPlayed || 0)
    })
  }

  return { games: normalized, meta: parsed.meta || {}, error: "" }
}

// Subsequence match, the same shape of matching the Omarchy menu uses: every
// character of the query must appear in order, but not adjacently, so "smw"
// finds "Super Mario World".
function subsequenceScore(haystack, needle) {
  if (!needle.length) return 0
  var hi = 0
  var ni = 0
  var score = 0
  var streak = 0
  while (hi < haystack.length && ni < needle.length) {
    if (haystack.charAt(hi) === needle.charAt(ni)) {
      // A run of consecutive hits is worth more than the same characters
      // scattered across the string, which is what keeps "mario" ranking
      // "Mario Kart" above "Mystery Aquarium Rio".
      streak += 1
      score += streak
      if (hi === 0 || haystack.charAt(hi - 1) === " ") score += 4
      ni += 1
    } else {
      streak = 0
    }
    hi += 1
  }
  return ni === needle.length ? score : -1
}

// Rank matches, then fall back to the caller's incoming order (which the
// scanner already sorted by title) so an empty query is stable rather than
// reshuffling every rescan.
function filterGames(games, query, limit) {
  var list = games || []
  var max = limit || 500
  var q = String(query || "").trim().toLowerCase()

  if (!q.length) return list.slice(0, max)

  var scored = []
  for (var i = 0; i < list.length; i++) {
    var g = list[i]
    var title = String(g.title || "").toLowerCase()
    var score = subsequenceScore(title, q)
    if (score < 0) {
      // Only fall back to the system name when the title missed entirely,
      // and penalise it, so typing "snes" lists the SNES shelf without
      // burying a game actually called "Snes Test Cart".
      var sys = String(g.system || "").toLowerCase()
      var sysScore = subsequenceScore(sys, q)
      if (sysScore < 0) continue
      score = sysScore - 1000
    }
    scored.push({ game: g, score: score, order: i })
  }

  scored.sort(function (a, b) {
    if (b.score !== a.score) return b.score - a.score
    return a.order - b.order
  })

  var out = []
  for (var j = 0; j < scored.length && j < max; j++) out.push(scored[j].game)
  return out
}

// The Continue shelf. A game earns a place only by having a save state on
// disk -- "recently launched" is not the same promise, and offering Continue
// on a game with nothing to continue from is worse than not offering it.
// `resumeAt` is the gate rather than `resumeSlot`, because slot "0" and slot
// "auto" are both perfectly good slots and only a zero timestamp means the
// scanner found no state.
function resumableGames(games, limit) {
  var list = games || []
  var out = []
  for (var i = 0; i < list.length; i++) {
    if (list[i].resumeAt > 0 && list[i].resumeSlot !== "") out.push(list[i])
  }
  out.sort(function (a, b) { return b.resumeAt - a.resumeAt })
  return out.slice(0, limit || 12)
}

// RetroArch playlist names are database names -- "Nintendo - Super Nintendo
// Entertainment System" -- which are far too long for a bar popup row and
// elide to "Nintendo - Sup...", the least informative half. Shorten to the
// name people actually use, and fall back to dropping the manufacturer
// prefix for systems not in the table.
var SHORT_SYSTEMS = {
  "super nintendo entertainment system": "SNES",
  "nintendo entertainment system": "NES",
  "family computer disk system": "Famicom Disk",
  "game boy advance": "GBA",
  "game boy color": "GBC",
  "game boy": "Game Boy",
  "nintendo 64": "N64",
  "nintendo ds": "NDS",
  "nintendo - nintendo 3ds": "3DS",
  "gamecube": "GameCube",
  "mega drive - genesis": "Genesis",
  "master system - mark iii": "Master System",
  "game gear": "Game Gear",
  "sg-1000": "SG-1000",
  "playstation": "PS1",
  "playstation portable": "PSP",
  "pc engine - turbografx 16": "PC Engine",
  "pc engine supergrafx": "SuperGrafx",
  "dreamcast": "Dreamcast",
  "saturn": "Saturn",
  "neo geo": "Neo Geo",
  "atari 2600": "Atari 2600",
  "commodore 64": "C64",
  "amiga": "Amiga"
}

function shortSystem(system) {
  var raw = String(system || "").trim()
  if (!raw.length) return ""

  // Playlist names arrive as "<maker> - <system>", but some systems have a
  // hyphen of their own ("Mega Drive - Genesis"), so try the full string
  // against the table before splitting anything off.
  var full = raw.toLowerCase()
  if (SHORT_SYSTEMS[full]) return SHORT_SYSTEMS[full]

  var dash = raw.indexOf(" - ")
  if (dash > 0) {
    var tail = raw.slice(dash + 3)
    var key = tail.toLowerCase()
    if (SHORT_SYSTEMS[key]) return SHORT_SYSTEMS[key]
    return tail
  }

  return raw
}

// What runs this ROM, for display. The system alone is not the answer -- two
// SNES games in the same library can end up on different cores, and the core
// is what actually gets launched -- so show both when they differ in
// substance, and never repeat one as the other.
function systemAndCore(game) {
  if (!game) return ""
  var system = shortSystem(game.system)
  var core = String(game.coreName || "")
  if (!system) return core
  if (!core) return system
  if (system.toLowerCase() === core.toLowerCase()) return system
  return system + " · " + core
}

function formatAgo(epochSeconds, nowSeconds) {
  var then = Number(epochSeconds || 0)
  if (then <= 0) return ""
  var delta = Math.max(0, Math.floor(Number(nowSeconds || 0) - then))

  if (delta < 90) return "just now"
  if (delta < 3600) return Math.round(delta / 60) + "m ago"
  if (delta < 86400) return Math.round(delta / 3600) + "h ago"
  if (delta < 604800) return Math.round(delta / 86400) + "d ago"
  return Math.round(delta / 604800) + "w ago"
}

// Node (tests) reaches the same functions the QML `.import` reaches.
if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    parseLibrary: parseLibrary,
    shortSystem: shortSystem,
    systemAndCore: systemAndCore,
    subsequenceScore: subsequenceScore,
    filterGames: filterGames,
    resumableGames: resumableGames,
    formatAgo: formatAgo
  }
}
