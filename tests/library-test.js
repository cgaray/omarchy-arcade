// Unit tests for Library.js.
//
// Library.js is a QML JavaScript resource, so it opens with `.pragma library`
// -- syntax node cannot parse. Strip the QML-only directives and evaluate the
// rest, which keeps the shipped file idiomatic QML instead of contorting it
// into something node happens to accept.

const fs = require("fs")
const path = require("path")
const assert = require("assert")

const source = fs
  .readFileSync(path.join(__dirname, "..", "Library.js"), "utf8")
  .replace(/^\s*\.(pragma|import)\b.*$/gm, "")

// Library.js reassigns `module.exports` wholesale, so read the exports back
// off the module object afterwards rather than trusting the `exports` alias.
const mod = { exports: {} }
new Function("module", "exports", source)(mod, mod.exports)
const Library = mod.exports

let passed = 0
function test(name, fn) {
  try {
    fn()
    passed += 1
  } catch (e) {
    console.error(`FAIL: ${name}\n  ${e.message}`)
    process.exitCode = 1
  }
}

const game = (over) =>
  Object.assign(
    {
      key: "/roms/a.sfc",
      title: "A Game",
      system: "SNES",
      core: "/usr/lib/libretro/snes9x_libretro.so",
      coreName: "snes9x",
      rom: "/roms/a.sfc",
      art: "",
      resumeSlot: "",
      resumeArt: "",
      resumeAt: 0,
      addedAt: 0,
      lastPlayed: 0,
      playSeconds: 0,
      playCount: 0
    },
    over || {}
  )

// --- scan builder -----------------------------------------------------------

// The scanner streams tagged NDJSON; these helpers speak that protocol.
const line = (o) => JSON.stringify(o)
const headerLine = (games) => ({ t: "header", games })
const gameLine = (g) => ({ t: "game", g })
const trailerLine = (over) =>
  Object.assign({ t: "trailer", extensions: [], meta: {} }, over || {})

function feed(lines) {
  const b = Library.createScanBuilder()
  for (const l of lines) b.addLine(typeof l === "string" ? l : JSON.stringify(l))
  return b.finish()
}

test("an empty stream is an error, not an innocent empty library", () => {
  const r = feed([])
  assert.strictEqual(r.games.length, 0)
  assert.strictEqual(r.error, "scanner produced no output")
})

test("a non-JSON line is reported as an error", () => {
  const r = feed(["scan failed: jq not found"])
  assert.ok(r.error, "expected an error for non-JSON output")
})

test("a well-formed stream builds the library", () => {
  const r = feed([
    line(headerLine(1)),
    line(gameLine(game())),
    line(trailerLine({ meta: { fromPlaylists: 1 } }))
  ])
  assert.strictEqual(r.error, "")
  assert.strictEqual(r.games.length, 1)
  assert.strictEqual(r.games[0].title, "A Game")
  assert.strictEqual(r.meta.fromPlaylists, 1)
})

test("entries with no ROM or no core are dropped at the edge", () => {
  const r = feed([
    headerLine(3),
    gameLine(game()),
    gameLine({ title: "no rom", core: "c" }),
    gameLine({ title: "no core", rom: "/r" }),
    trailerLine()
  ].map(line))
  assert.strictEqual(r.games.length, 1)
})

test("resumeSlot 0 stays distinguishable from no slot", () => {
  const r = feed([headerLine(1), gameLine(game({ resumeSlot: "0", resumeAt: 100 })), trailerLine()])
  assert.strictEqual(r.games[0].resumeSlot, "0")
  assert.strictEqual(r.games[0].resumeAt, 100)
})

test("the persisted first-discovered timestamp survives the stream", () => {
  const r = feed([headerLine(1), gameLine(game({ addedAt: 1234 })), trailerLine()])
  assert.strictEqual(r.games[0].addedAt, 1234)
})

test("a stream without its trailer is incomplete, not empty", () => {
  const r = feed([line(headerLine(1)), line(gameLine(game()))])
  assert.strictEqual(r.error, "scanner output was incomplete")
  assert.strictEqual(r.games.length, 0)
})

test("unrecognised tags and blank lines are skipped, not fatal", () => {
  const r = feed([
    "",
    line(headerLine(1)),
    line({ t: "something-new" }),
    line(gameLine(game())),
    "   ",
    line(trailerLine())
  ])
  assert.strictEqual(r.error, "")
  assert.strictEqual(r.games.length, 1)
})

// --- filterGames ------------------------------------------------------------

test("empty query returns the list unchanged", () => {
  const games = [game({ title: "B" }), game({ title: "A" })]
  assert.deepStrictEqual(Library.filterGames(games, "").map((g) => g.title), ["B", "A"])
})

test("subsequence matching finds initials", () => {
  const games = [game({ title: "Super Mario World" }), game({ title: "Donkey Kong" })]
  const out = Library.filterGames(games, "smw")
  assert.strictEqual(out.length, 1)
  assert.strictEqual(out[0].title, "Super Mario World")
})

test("consecutive runs rank above scattered matches", () => {
  const games = [
    game({ title: "Mystery Aquarium Rio" }),
    game({ title: "Mario Kart" })
  ]
  assert.strictEqual(Library.filterGames(games, "mario")[0].title, "Mario Kart")
})

test("a system match ranks below every title match", () => {
  const games = [
    game({ title: "Zelda", system: "SNES" }),
    game({ title: "Snes Test Cart", system: "SNES" })
  ]
  assert.strictEqual(Library.filterGames(games, "snes")[0].title, "Snes Test Cart")
})

test("non-matching query returns nothing", () => {
  assert.strictEqual(Library.filterGames([game({ title: "Tetris" })], "zzzz").length, 0)
})

test("limit is honoured", () => {
  const games = [game({ title: "A" }), game({ title: "B" }), game({ title: "C" })]
  assert.strictEqual(Library.filterGames(games, "", 2).length, 2)
})

// --- Continue and the system filter -----------------------------------------

test("Continue follows the system filter instead of vanishing", () => {
  const games = [
    game({ title: "SnesSave", system: "Nintendo - Super Nintendo Entertainment System",
           resumeSlot: "0", resumeAt: 500 }),
    game({ title: "NesSave", system: "Nintendo - Nintendo Entertainment System",
           resumeSlot: "0", resumeAt: 400 })
  ]
  assert.deepStrictEqual(Library.resumableIn(games, "SNES", 6).map((g) => g.title), ["SnesSave"])
  assert.deepStrictEqual(Library.resumableIn(games, "", 6).map((g) => g.title),
    ["SnesSave", "NesSave"])
})

test("a system with no saves has an empty Continue shelf, not the wrong one", () => {
  const games = [
    game({ title: "SnesSave", system: "Nintendo - Super Nintendo Entertainment System",
           resumeSlot: "0", resumeAt: 500 })
  ]
  assert.deepStrictEqual(Library.resumableIn(games, "NES", 6), [])
})

// --- systemsOf and system filtering -----------------------------------------

test("systemsOf counts each system and shortens its name", () => {
  const games = [
    game({ system: "Nintendo - Super Nintendo Entertainment System" }),
    game({ system: "Nintendo - Super Nintendo Entertainment System" }),
    game({ system: "Nintendo Entertainment System" })
  ]
  const out = Library.systemsOf(games)
  assert.deepStrictEqual(out.map((s) => [s.label, s.count]), [["NES", 1], ["SNES", 2]])
})

// A playlist and a core .info name the same system differently. Grouping on
// the raw string gave one tab per spelling, both reading "SNES".
test("the two spellings of a system are one tab, not two", () => {
  const games = [
    game({ system: "Nintendo - Super Nintendo Entertainment System" }),
    game({ system: "Super Nintendo Entertainment System" }),
    game({ system: "Nintendo - Nintendo Entertainment System" }),
    game({ system: "Nintendo Entertainment System" })
  ]
  const out = Library.systemsOf(games)
  assert.deepStrictEqual(out.map((s) => [s.label, s.count]), [["NES", 2], ["SNES", 2]])
})

test("filtering a merged system catches both spellings", () => {
  const games = [
    game({ title: "A", system: "Nintendo - Super Nintendo Entertainment System" }),
    game({ title: "B", system: "Super Nintendo Entertainment System" }),
    game({ title: "C", system: "Nintendo Entertainment System" })
  ]
  const out = Library.filterGames(games, "", 100, "SNES")
  assert.deepStrictEqual(out.map((g) => g.title), ["A", "B"])
})

test("a game with no system is grouped as Unknown rather than dropped", () => {
  const out = Library.systemsOf([game({ system: "" })])
  assert.deepStrictEqual(out.map((s) => [s.system, s.count]), [["Unknown", 1]])
  assert.deepStrictEqual(
    Library.filterGames([game({ title: "X", system: "" })], "", 100, "Unknown").map((g) => g.title),
    ["X"])
})

test("the system filter restricts the library", () => {
  const games = [
    game({ title: "Zelda", system: "Nintendo - Super Nintendo Entertainment System" }),
    game({ title: "Metroid", system: "Nintendo - Nintendo Entertainment System" })
  ]
  const out = Library.filterGames(games, "", 100, "SNES")
  assert.deepStrictEqual(out.map((g) => g.title), ["Zelda"])
})

test("searching inside a system stays inside it", () => {
  const games = [
    game({ title: "Mario Kart", system: "Nintendo - Super Nintendo Entertainment System" }),
    game({ title: "Mario Bros", system: "Nintendo - Nintendo Entertainment System" })
  ]
  const out = Library.filterGames(games, "mario", 100, "NES")
  assert.deepStrictEqual(out.map((g) => g.title), ["Mario Bros"])
})

test("no system filter means the whole library", () => {
  const games = [game({ system: "SNES" }), game({ system: "NES" })]
  assert.strictEqual(Library.filterGames(games, "", 100, "").length, 2)
})

// --- resumableGames ---------------------------------------------------------

test("only games with a save state reach the Continue shelf", () => {
  const games = [
    game({ title: "No Save" }),
    game({ title: "Saved", resumeSlot: "0", resumeAt: 500 })
  ]
  const out = Library.resumableGames(games)
  assert.strictEqual(out.length, 1)
  assert.strictEqual(out[0].title, "Saved")
})

test("the auto slot is a real slot", () => {
  const games = [game({ title: "Auto", resumeSlot: "auto", resumeAt: 500 })]
  assert.strictEqual(Library.resumableGames(games).length, 1)
})

test("Continue is ordered most-recent first", () => {
  const games = [
    game({ title: "Older", resumeSlot: "0", resumeAt: 100 }),
    game({ title: "Newer", resumeSlot: "0", resumeAt: 900 })
  ]
  assert.deepStrictEqual(Library.resumableGames(games).map((g) => g.title), ["Newer", "Older"])
})

// --- prettyTitle ------------------------------------------------------------

test("an all-caps ROM header title is title-cased", () => {
  assert.strictEqual(Library.prettyTitle("ALADDIN"), "Aladdin")
  assert.strictEqual(Library.prettyTitle("CHRONO TRIGGER"), "Chrono Trigger")
})

test("minor words stay lowercase, except leading", () => {
  assert.strictEqual(Library.prettyTitle("THE LEGEND OF ZELDA"), "The Legend of Zelda")
})

test("hyphenated names capitalise both halves", () => {
  assert.strictEqual(Library.prettyTitle("F-ZERO"), "F-Zero")
})

test("a title someone actually wrote is never touched", () => {
  assert.strictEqual(Library.prettyTitle("Super Mario World (USA)"), "Super Mario World (USA)")
  assert.strictEqual(Library.prettyTitle("Bowser's Kaizo Conspiracy v1.2"), "Bowser's Kaizo Conspiracy v1.2")
  assert.strictEqual(Library.prettyTitle("balloonfight"), "balloonfight")
})

test("digits and empty input survive", () => {
  assert.strictEqual(Library.prettyTitle("1942"), "1942")
  assert.strictEqual(Library.prettyTitle(""), "")
})

test("incoming all-caps titles are title-cased on the way through", () => {
  const r = feed([headerLine(1), gameLine(game({ title: "SUPER METROID" })), trailerLine()])
  assert.strictEqual(r.games[0].title, "Super Metroid")
})

// --- shortSystem ------------------------------------------------------------

test("a playlist database name shortens to the name people use", () => {
  assert.strictEqual(
    Library.shortSystem("Nintendo - Super Nintendo Entertainment System"), "SNES")
  assert.strictEqual(Library.shortSystem("Nintendo - Game Boy Advance"), "GBA")
  assert.strictEqual(Library.shortSystem("Sony - PlayStation"), "PS1")
})

test("a system whose own name contains a hyphen is matched whole", () => {
  assert.strictEqual(Library.shortSystem("Sega - Mega Drive - Genesis"), "Genesis")
  assert.strictEqual(Library.shortSystem("Sega - Master System - Mark III"), "Master System")
})

test("an unknown system just loses its manufacturer prefix", () => {
  assert.strictEqual(Library.shortSystem("Acme - Wonder Machine 3000"), "Wonder Machine 3000")
})

test("a system with no prefix is left alone", () => {
  assert.strictEqual(Library.shortSystem("ZX Spectrum"), "ZX Spectrum")
  assert.strictEqual(Library.shortSystem(""), "")
})

// --- systemAndCore ----------------------------------------------------------

test("the row meta names both the system and the core that will run", () => {
  assert.strictEqual(
    Library.systemAndCore(game({
      system: "Nintendo - Super Nintendo Entertainment System",
      coreName: "snes9x"
    })),
    "SNES · snes9x")
})

test("with no playlist there is no system, so the core stands alone", () => {
  assert.strictEqual(Library.systemAndCore(game({ system: "", coreName: "snes9x" })), "snes9x")
})

test("a system and core that say the same thing are not repeated", () => {
  assert.strictEqual(Library.systemAndCore(game({ system: "Dreamcast", coreName: "dreamcast" })), "Dreamcast")
})

test("systemAndCore tolerates a missing game", () => {
  assert.strictEqual(Library.systemAndCore(null), "")
})

// --- extension pickers ------------------------------------------------------

const ext = (over) =>
  Object.assign({ ext: "sfc", candidates: [{ id: "snes9x" }, { id: "bsnes" }], chosen: "", resolved: "bsnes" },
    over || {})

test("the extension table rides the trailer", () => {
  const r = feed([headerLine(1), gameLine(game()), trailerLine({ extensions: [ext()] })])
  assert.strictEqual(r.extensions.length, 1)
  assert.strictEqual(r.extensions[0].ext, "sfc")
  assert.strictEqual(r.extensions[0].candidates.length, 2)
})

test("a stream with no extension table is not an error", () => {
  const r = feed([headerLine(1), gameLine(game()), trailerLine()])
  assert.strictEqual(r.error, "")
  assert.deepStrictEqual(r.extensions, [])
})

test("an extension only one core can open is not a choice", () => {
  const only = [ext({ candidates: [{ id: "mgba" }] })]
  assert.strictEqual(Library.undecidedExtensions(only).length, 0)
  assert.strictEqual(Library.choosableExtensions(only).length, 0)
})

test("an extension several cores claim is undecided until it is chosen", () => {
  assert.strictEqual(Library.undecidedExtensions([ext()]).length, 1)
  assert.strictEqual(Library.undecidedExtensions([ext({ chosen: "snes9x" })]).length, 0)
})

test("a decided extension is still choosable, so it can be changed back", () => {
  assert.strictEqual(Library.choosableExtensions([ext({ chosen: "snes9x" })]).length, 1)
})

// --- playtime ---------------------------------------------------------------

test("formatDuration reads at the resolution people care about", () => {
  assert.strictEqual(Library.formatDuration(0), "0s")
  assert.strictEqual(Library.formatDuration(46), "46s")
  assert.strictEqual(Library.formatDuration(600), "10m")
  assert.strictEqual(Library.formatDuration(3600), "1h")
  assert.strictEqual(Library.formatDuration(3900), "1h 5m")
})

test("a game never launched says so rather than showing zeroes", () => {
  assert.strictEqual(Library.playSummary(game(), 1_750_000_000), "Never played")
})

test("playSummary reads as a sentence", () => {
  const now = 1_750_000_000
  const g = game({ playSeconds: 3900, playCount: 3, lastPlayed: now - 7200 })
  assert.strictEqual(Library.playSummary(g, now), "1h 5m · 3 sessions · last 2h ago")
})

test("one session is not pluralised", () => {
  const now = 1_750_000_000
  const g = game({ playSeconds: 60, playCount: 1, lastPlayed: now - 60 })
  assert.ok(Library.playSummary(g, now).indexOf("1 session ") >= 0)
})

test("playtime rides the game lines", () => {
  const r = feed([headerLine(1), gameLine(game({ playSeconds: 120, playCount: 2 })), trailerLine()])
  assert.strictEqual(r.games[0].playSeconds, 120)
  assert.strictEqual(r.games[0].playCount, 2)
})

// --- formatAgo --------------------------------------------------------------

test("formatAgo renders each bucket", () => {
  // A realistic epoch, so subtracting two weeks stays positive -- a negative
  // timestamp is its own case, covered below.
  const now = 1_750_000_000
  assert.strictEqual(Library.formatAgo(now - 10, now), "just now")
  assert.strictEqual(Library.formatAgo(now - 600, now), "10m ago")
  assert.strictEqual(Library.formatAgo(now - 7200, now), "2h ago")
  assert.strictEqual(Library.formatAgo(now - 172800, now), "2d ago")
  assert.strictEqual(Library.formatAgo(now - 1209600, now), "2w ago")
})

test("formatAgo renders nothing for a game that was never resumed", () => {
  assert.strictEqual(Library.formatAgo(0, 1_750_000_000), "")
  assert.strictEqual(Library.formatAgo(-5, 1_750_000_000), "")
})

test("highlightTitle escapes and accents the matched run", () => {
  assert.strictEqual(Library.highlightTitle("A&B", "", "#f00"), "A&amp;B")
  assert.strictEqual(
    Library.highlightTitle("Abc", "ab", "#f00"),
    '<b><font color="#f00">Ab</font></b>c')
  // Greedy left-to-right, same as subsequenceScore.
  assert.strictEqual(
    Library.highlightTitle("abc", "ac", "#f00"),
    '<b><font color="#f00">a</font></b>b<b><font color="#f00">c</font></b>')
  // No full match: plain escaped title, no tags.
  assert.strictEqual(Library.highlightTitle("Abc", "zz", "#f00"), "Abc")
  // Escaping happens inside the match too, and adjacent hits form one run.
  assert.strictEqual(
    Library.highlightTitle("<b>x", "<b", "#0f0"),
    '<b><font color="#0f0">&lt;b</font></b>&gt;x')
})

console.log(`library-test: ${passed} passed`)
