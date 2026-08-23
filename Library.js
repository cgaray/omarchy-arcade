// Pure library helpers for the Arcade overlay.
//
// Everything here is plain ES5-compatible JavaScript with no QML or Quickshell
// imports, so the same file loads under `.import` in Arcade.qml and under
// node in tests/library-test.js. Keep it that way: the moment this file needs
// a QML type, it stops being testable outside a running shell.

.pragma library

// Normalize one scanner game record into the row shape every view reads.
// Entries with nowhere to run are dropped here, at the edge, rather than
// leaking into filters and shelves downstream.
//
// Rows live in the shell for its whole uptime, so normalization interns
// low-cardinality strings -- system names, core paths, empty art -- through
// a per-builder pool. The engine keeps no dedup across JSON.parse, so an
// un-interned library stored its dozen distinct system names once per game;
// sharing them is most of what a row costs beyond the title and ROM path.
function normalizeGame(g, pool) {
  if (!g || !g.rom || !g.core) return null

  var rom = String(g.rom)
  var interned = function (v) {
    var s = String(v == null ? "" : v)
    return pool[s] || (pool[s] = s)
  }

  var system = interned(g.system)
  var core = interned(g.core)
  var row = {
    title: prettyTitle(g.title),
    system: system,
    sysKey: interned(shortSystem(system)),
    core: core,
    coreName: interned(g.coreName),
    rom: rom,
    art: interned(g.art),
    resumeSlot: interned(g.resumeSlot),
    resumeArt: interned(g.resumeArt),
    resumeAt: Number(g.resumeAt || 0),
    addedAt: Number(g.addedAt || 0),
    lastPlayed: Number(g.lastPlayed || 0),
    playSeconds: Number(g.playSeconds || 0),
    playCount: Number(g.playCount || 0)
  }
  // `key` was always the ROM path restated; views identify rows by `rom`.
  if (g.key && String(g.key) !== rom) row.key = String(g.key)
  return row
}

function normalizeExtensions(list) {
  var exts = Array.isArray(list) ? list : []
  var out = []
  for (var k = 0; k < exts.length; k++) {
    var e = exts[k]
    if (!e || !e.ext) continue
    out.push({
      ext: String(e.ext),
      candidates: Array.isArray(e.candidates) ? e.candidates : [],
      chosen: String(e.chosen || ""),
      resolved: String(e.resolved || "")
    })
  }
  return out
}

// Ceilings keeping a large or malformed library from exhausting the
// long-lived shell. Streaming removed the whole-document text buffer, but
// the parsed rows stay resident -- that is what browsing needs -- so the
// builder bounds what it will retain: no single record above maxRecordBytes,
// and nothing beyond maxTotalBytes of stream in total (roughly 150k games;
// every real library sits far below). The scanner caps its own fields too,
// which bounds each emitted line at the source. Override point exists for
// tests.
var SCAN_LIMITS = {
  maxRecordBytes: 64 * 1024,
  maxTotalBytes: 64 * 1024 * 1024
}

// Streaming counterpart to omarchy-arcade-scan's tagged NDJSON output. Feed
// lines to addLine as they arrive -- the caller never holds the library as
// text, only structured rows -- and finish() returns what the views read,
// including an explicit error when the stream never became a library.
function createScanBuilder(limits) {
  var maxRecord = (limits && limits.maxRecordBytes) || SCAN_LIMITS.maxRecordBytes
  var maxTotal = (limits && limits.maxTotalBytes) || SCAN_LIMITS.maxTotalBytes
  // Prototype-free, so a string value can never collide with an inherited
  // property name during interning.
  var pool = Object.create(null)

  return {
    games: [],
    extensions: [],
    meta: {},
    error: "",
    _lines: 0,
    _bytes: 0,
    _stopped: false,
    _sawHeader: false,
    _sawTrailer: false,

    addLine: function (raw) {
      var line = String(raw == null ? "" : raw).trim()
      if (!line.length) return
      this._lines += 1
      this._bytes += line.length

      // A record nobody should ever produce is skipped rather than kept:
      // one malformed line costs its own entry, not the library.
      if (line.length > maxRecord) {
        this.error = this.error || "a scanner record exceeded the size limit"
        return
      }
      // Past the total ceiling the stream stops contributing rows but keeps
      // being consumed, so the trailer still arrives and finish() can report
      // the real cause rather than a mere "incomplete".
      if (this._bytes > maxTotal)
        this._stopped = true

      var msg
      try {
        msg = JSON.parse(line)
      } catch (e) {
        this.error = this.error || "scanner output was not JSON"
        return
      }
      if (!msg || typeof msg !== "object" || typeof msg.t !== "string") {
        this.error = this.error || "scanner output was not JSON"
        return
      }
      // Unrecognised tags are ignored rather than fatal: the protocol grows
      // forward, and an older reader skips what it does not know.
      if (msg.t === "header") {
        this._sawHeader = true
      } else if (msg.t === "game") {
        if (this._stopped) return
        var row = normalizeGame(msg.g, pool)
        if (row) this.games.push(row)
      } else if (msg.t === "trailer") {
        this._sawTrailer = true
        if (!this._stopped) {
          this.extensions = normalizeExtensions(msg.extensions)
          this.meta = msg.meta && typeof msg.meta === "object" ? msg.meta : {}
        }
      }
    },

    finish: function () {
      if (this._lines === 0)
        return { games: [], extensions: [], meta: {}, error: "scanner produced no output" }
      if (this._stopped)
        return { games: this.games, extensions: this.extensions, meta: this.meta,
                 error: this.error || "library exceeded the size limit" }
      if (!this._sawHeader || !this._sawTrailer)
        return { games: [], extensions: [], meta: {}, error: "scanner output was incomplete" }
      return { games: this.games, extensions: this.extensions, meta: this.meta, error: this.error }
    }
  }
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
// The key a game is grouped and filtered under. Two sources name the same
// system differently -- a playlist says "Nintendo - Super Nintendo
// Entertainment System" while a core's .info says "Super Nintendo
// Entertainment System" -- so grouping on the raw string produced one tab per
// spelling, both reading "SNES". Group on the shortened name instead, which
// is what the user sees anyway.
function systemKey(game) {
  if (!game) return "Unknown"
  return shortSystem(game.system) || "Unknown"
}

// The systems present in a library, each with its count, for the filter row.
// Sorted by name so the row does not reorder itself as games come and go.
function systemsOf(games) {
  var list = games || []
  var counts = {}
  for (var i = 0; i < list.length; i++) {
    var key = systemKey(list[i])
    counts[key] = (counts[key] || 0) + 1
  }

  var out = []
  for (var name in counts) {
    out.push({ system: name, label: name, count: counts[name] })
  }
  out.sort(function (a, b) { return a.label.localeCompare(b.label) })
  return out
}

function filterGames(games, query, limit, system) {
  var all = games || []
  var max = limit || 500
  var q = String(query || "").trim().toLowerCase()

  // The system filter is applied first and independently of the query, so
  // searching inside a system stays inside it.
  var wanted = String(system || "")
  var list = all
  if (wanted) {
    list = []
    for (var s = 0; s < all.length; s++) {
      if (systemKey(all[s]) === wanted) list.push(all[s])
    }
  }

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

// ROM headers store the game name in capitals ("THE LEGEND OF ZELDA"), which
// is how it looked on a 1990 title screen and not how it should look in a
// list. Only all-caps input is touched -- a title with any lowercase in it was
// written by a person and is left exactly as they wrote it.
var TITLE_MINOR_WORDS = {
  a: 1, an: 1, and: 1, as: 1, at: 1, but: 1, by: 1, for: 1, in: 1, nor: 1,
  of: 1, on: 1, or: 1, the: 1, to: 1, vs: 1
}

function prettyTitle(raw) {
  var text = String(raw || "")
  if (!text.length) return ""
  if (/[a-z]/.test(text)) return text

  // Split on spaces but capitalise across hyphens too, so "F-ZERO" becomes
  // "F-Zero" rather than "F-zero".
  var words = text.toLowerCase().split(/\s+/)
  var out = []
  for (var i = 0; i < words.length; i++) {
    var w = words[i]
    if (!w.length) continue
    if (i > 0 && TITLE_MINOR_WORDS[w]) { out.push(w); continue }
    out.push(w.replace(/(^|-)([a-z0-9])/g, function (m, sep, ch) {
      return sep + ch.toUpperCase()
    }))
  }
  return out.join(" ")
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

// Extensions with a decision still to make: more than one installed core
// claims them and the user has not said which. An extension only one core can
// open is not a choice, and showing it as one is noise.
function undecidedExtensions(extensions) {
  var list = extensions || []
  var out = []
  for (var i = 0; i < list.length; i++) {
    if (list[i].candidates.length > 1 && !list[i].chosen) out.push(list[i])
  }
  return out
}

// Every extension worth showing a picker for -- including ones already
// decided, so a choice can be changed or reverted.
function choosableExtensions(extensions) {
  var list = extensions || []
  var out = []
  for (var i = 0; i < list.length; i++) {
    if (list[i].candidates.length > 1) out.push(list[i])
  }
  return out
}

// Playtime, at the resolution someone actually cares about: minutes below an
// hour, whole hours above it. "1h 5m" rather than "1:05:32".
function formatDuration(seconds) {
  var total = Math.max(0, Math.floor(Number(seconds || 0)))
  if (total < 60) return total + "s"
  var minutes = Math.floor(total / 60)
  if (minutes < 60) return minutes + "m"
  var hours = Math.floor(minutes / 60)
  var rest = minutes % 60
  return rest ? (hours + "h " + rest + "m") : (hours + "h")
}

// The line under an expanded row: what has happened with this game, or an
// honest admission that nothing has.
function playSummary(game, nowSeconds) {
  if (!game) return ""
  if (!game.playCount) return "Never played"

  var bits = [formatDuration(game.playSeconds)]
  bits.push(game.playCount === 1 ? "1 session" : (game.playCount + " sessions"))
  var ago = formatAgo(game.lastPlayed, nowSeconds)
  if (ago) bits.push("last " + ago)
  return bits.join(" · ")
}

// The Continue shelf for a given system, or for the whole library when no
// system is selected. Separate from resumableGames so the composition the
// panel needs is a tested function rather than a QML binding.
function resumableIn(games, system, limit) {
  var pool = system ? filterGames(games, "", 100000, system) : (games || [])
  return resumableGames(pool, limit)
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

// HTML for a title with the search match accented. Greedy left-to-right --
// the same pass subsequenceScore runs -- so what lights up is exactly what
// matched. Output is escaped HTML; an empty or fully-unmatched query returns
// the plain escaped title, which renders identically to PlainText.
function highlightTitle(raw, query, accent) {
  var text = String(raw || "")
  if (!text.length) return ""
  var q = String(query || "").trim().toLowerCase()

  function esc(c) {
    return c === "&" ? "&amp;" : c === "<" ? "&lt;" : c === ">" ? "&gt;" : c
  }

  var marks = []
  if (q.length) {
    var lower = text.toLowerCase()
    var ni = 0
    for (var i = 0; i < lower.length && ni < q.length; i++) {
      if (lower.charAt(i) === q.charAt(ni)) { marks[i] = 1; ni++ }
    }
    if (ni < q.length) marks = []
  }

  var out = ""
  var j = 0
  while (j < text.length) {
    if (marks[j]) {
      var run = ""
      while (j < text.length && marks[j]) { run += esc(text.charAt(j)); j++ }
      out += '<b><font color="' + accent + '">' + run + "</font></b>"
    } else {
      out += esc(text.charAt(j))
      j++
    }
  }
  return out
}

// Node (tests) reaches the same functions the QML `.import` reaches.
if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    createScanBuilder: createScanBuilder,
    prettyTitle: prettyTitle,
    shortSystem: shortSystem,
    systemAndCore: systemAndCore,
    systemKey: systemKey,
    systemsOf: systemsOf,
    undecidedExtensions: undecidedExtensions,
    choosableExtensions: choosableExtensions,
    subsequenceScore: subsequenceScore,
    filterGames: filterGames,
    resumableGames: resumableGames,
    resumableIn: resumableIn,
    formatAgo: formatAgo,
    formatDuration: formatDuration,
    playSummary: playSummary,
    highlightTitle: highlightTitle
  }
}
