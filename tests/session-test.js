const assert = require("assert")
const fs = require("fs")
const path = require("path")

const librarySource = fs.readFileSync(path.join(__dirname, "..", "Library.js"), "utf8")
  .replace(/^\s*\.(pragma|import)\b.*$/gm, "")
const libraryModule = { exports: {} }
new Function("module", "exports", librarySource)(libraryModule, libraryModule.exports)

const source = fs.readFileSync(path.join(__dirname, "..", "ArcadeSession.js"), "utf8")
  .replace(/^\.import "Library\.js" as Library$/m, "var Library = require('../Library.js')")
  .replace(/^\s*\.pragma\s+library$/m, "")
const mod = { exports: {} }
new Function("module", "exports", "require", source)(
  mod, mod.exports, () => libraryModule.exports)
const Session = mod.exports

const game = (over) => Object.assign({
  key: "/roms/a.sfc",
  title: "A Game",
  system: "SNES",
  core: "/cores/snes9x_libretro.so",
  coreName: "snes9x",
  rom: "/roms/a.sfc",
  resumeSlot: "",
  resumeAt: 0,
  addedAt: 0
}, over || {})

assert.deepStrictEqual(
  Session.launchRequest(game({ resumeSlot: "auto" }), true, "/bin/launch"),
  ["/bin/launch", "--core", "/cores/snes9x_libretro.so", "--rom", "/roms/a.sfc",
   "--slot", "auto"]
)

const rebuilt = Session.rebuild([
  game({ system: "SNES", resumeSlot: "0", resumeAt: 100 }),
  game({ key: "/roms/b.nes", rom: "/roms/b.nes", title: "Other", system: "NES" })
], "", "missing", 40, 6)
assert.strictEqual(rebuilt.systemFilter, "")
assert.strictEqual(rebuilt.continueRows.length, 1)
assert.strictEqual(rebuilt.libraryRows.length, 2)

const saved = Session.rebuild([
  game({ resumeAt: 100, resumeSlot: "0" }),
  game({ key: "/roms/other.sfc", rom: "/roms/other.sfc" })
], "", "", 40, 0, true)
assert.strictEqual(saved.libraryRows.length, 1)
assert.strictEqual(saved.libraryRows[0].resumeSlot, "0")

// rebuild returns the whole view model: chip row plus a save tally counted
// over the whole library, before any savedOnly narrowing.
const vmGames = [
  game({ resumeSlot: "0", resumeAt: 100 }),
  game({ key: "/roms/b.nes", rom: "/roms/b.nes", title: "Other", system: "NES", resumeSlot: "1", resumeAt: 50 }),
  game({ key: "/roms/c.nes", rom: "/roms/c.nes", title: "Third", system: "NES" })
]
const vm = Session.rebuild(vmGames, "", "", 40, 6)
assert.strictEqual(vm.resumableTotal, 2)
assert.deepStrictEqual(vm.systems.map((s) => [s.label, s.count]), [["NES", 2], ["SNES", 1]])
const savedVm = Session.rebuild(vmGames, "", "", 40, 0, true)
assert.deepStrictEqual(savedVm.systems.map((s) => s.label), ["NES", "SNES"])

const sortable = [
  game({ title: "Bravo", resumeAt: 200, lastPlayed: 100, addedAt: 200 }),
  game({ key: "/roms/a.nes", rom: "/roms/a.nes", title: "Alpha", resumeAt: 100, lastPlayed: 300, addedAt: 100 }),
  game({ key: "/roms/c.nes", rom: "/roms/c.nes", title: "Charlie", resumeAt: 0, lastPlayed: 0, addedAt: 300 })
]
assert.deepStrictEqual(Session.rebuild(sortable, "", "", 40, 0, false, "added").libraryRows.map((g) => g.title), ["Charlie", "Bravo", "Alpha"])
assert.deepStrictEqual(Session.rebuild(sortable, "", "", 40, 0, false, "save").libraryRows.map((g) => g.title), ["Bravo", "Alpha", "Charlie"])
assert.deepStrictEqual(Session.rebuild(sortable, "", "", 40, 0, false, "played").libraryRows.map((g) => g.title), ["Alpha", "Bravo", "Charlie"])
assert.deepStrictEqual(Session.rebuild(sortable, "", "", 40, 0, false, "name").libraryRows.map((g) => g.title), ["Alpha", "Bravo", "Charlie"])

// Browsing (empty query) groups rows by system so the grid's section
// headers read in order; searching keeps relevance ranking instead.
const groupGames = [
  game({ key: "/roms/b.nes", rom: "/roms/b.nes", title: "B", system: "NES" }),
  game({ key: "/roms/z.sfc", rom: "/roms/z.sfc", title: "Zed", system: "SNES" }),
  game({ key: "/roms/a.nes", rom: "/roms/a.nes", title: "A", system: "NES" })
]
assert.deepStrictEqual(
  Session.rebuild(groupGames, "", "", 40, 6).libraryRows.map((g) => g.rom),
  ["/roms/a.nes", "/roms/b.nes", "/roms/z.sfc"])
assert.deepStrictEqual(
  Session.rebuild(groupGames, "zed", "", 40, 0).libraryRows.map((g) => g.rom),
  ["/roms/z.sfc"])

// Display helpers ride the same seam so views need no second import.
assert.strictEqual(Session.formatAgo(30, 60), "just now")
assert.strictEqual(Session.systemAndCore(game()), "SNES · snes9x")
assert.strictEqual(Session.playSummary(game({ playCount: 0 }), 60), "Never played")
assert.deepStrictEqual(Session.choosableExtensions([{ candidates: ["a", "b"], chosen: "" }]).length, 1)

assert.strictEqual(Session.fingerprintChanged("", "abc"), false)
assert.strictEqual(Session.fingerprintChanged("abc", "abc"), false)
assert.strictEqual(Session.fingerprintChanged("abc", "def"), true)

// Scan builders flow through the seam like every other Library call, so the
// streaming path needs no second import either.
{
  const b = Session.createScanBuilder()
  b.addLine(JSON.stringify({ t: "header", games: 1 }))
  b.addLine(JSON.stringify({ t: "game", g: game() }))
  b.addLine(JSON.stringify({ t: "trailer", extensions: [], meta: {} }))
  const r = b.finish()
  assert.strictEqual(r.error, "")
  assert.strictEqual(r.games.length, 1)
}

console.log("session-test: 13 passed")
