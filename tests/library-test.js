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
      lastPlayed: 0
    },
    over || {}
  )

// --- parseLibrary -----------------------------------------------------------

test("parseLibrary reports empty scanner output as an error, not an empty library", () => {
  const r = Library.parseLibrary("")
  assert.strictEqual(r.games.length, 0)
  assert.ok(r.error, "expected an error for empty output")
})

test("parseLibrary reports non-JSON as an error", () => {
  const r = Library.parseLibrary("scan failed: jq not found")
  assert.ok(r.error, "expected an error for non-JSON output")
})

test("parseLibrary accepts a well-formed library", () => {
  const r = Library.parseLibrary(JSON.stringify({ games: [game()], meta: { fromWalk: 1 } }))
  assert.strictEqual(r.error, "")
  assert.strictEqual(r.games.length, 1)
  assert.strictEqual(r.games[0].title, "A Game")
  assert.strictEqual(r.meta.fromWalk, 1)
})

test("parseLibrary drops entries with no ROM or no core", () => {
  const raw = JSON.stringify({
    games: [game(), game({ rom: "" }), game({ core: "" })]
  })
  assert.strictEqual(Library.parseLibrary(raw).games.length, 1)
})

test("parseLibrary keeps resumeSlot 0 distinguishable from no slot", () => {
  const raw = JSON.stringify({ games: [game({ resumeSlot: "0", resumeAt: 100 })] })
  const g = Library.parseLibrary(raw).games[0]
  assert.strictEqual(g.resumeSlot, "0")
  assert.strictEqual(g.resumeAt, 100)
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

console.log(`library-test: ${passed} passed`)
