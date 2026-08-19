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
  resumeAt: 0
}, over || {})

const settings = {
  romDir: "/custom/roms",
  silenceNotifications: false,
  stayAwake: false
}

assert.deepStrictEqual(Session.scannerEnvironment(settings), { ARCADE_ROM_DIR: "/custom/roms" })
assert.deepStrictEqual(Session.scannerEnvironment({}), { ARCADE_ROM_DIR: "" })

assert.deepStrictEqual(
  Session.launchRequest(game({ resumeSlot: "auto" }), settings, true, "/bin/launch"),
  ["/bin/launch", "--core", "/cores/snes9x_libretro.so", "--rom", "/roms/a.sfc",
   "--slot", "auto", "--keep-notifications", "--allow-idle"]
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

assert.strictEqual(Session.fingerprintChanged("", "abc"), false)
assert.strictEqual(Session.fingerprintChanged("abc", "abc"), false)
assert.strictEqual(Session.fingerprintChanged("abc", "def"), true)

console.log("session-test: 5 passed")
