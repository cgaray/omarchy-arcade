#!/usr/bin/env node
// Architecture enforcement, so the rules stay true by construction:
//
// 1. QML views talk to ArcadeSession.js only -- never to Library.js. The
//    session layer is the one seam; a second import re-spreads view-model
//    knowledge across both surfaces.
// 2. Surface files stay navigable. A monolith regrowing past the cap is a
//    sign a delegate belongs in its own file.

const fs = require("fs")
const path = require("path")

const root = path.join(__dirname, "..")
let failures = 0
function fail(msg) {
  console.error(`FAIL: ${msg}`)
  failures++
}

const qmlFiles = fs.readdirSync(root).filter((f) => f.endsWith(".qml"))
for (const file of qmlFiles) {
  const src = fs.readFileSync(path.join(root, file), "utf8")
  if (/import\s+"Library\.js"/.test(src)) fail(`${file} imports Library.js directly`)
  else if (/(?<![.\w])Library\./.test(src)) {
    const line = src.split("\n").findIndex((l) => /(?<![.\w])Library\./.test(l)) + 1
    fail(`${file}:${line} calls Library.*; go through Session instead`)
  }
}

const LINE_CAPS = { "Panel.qml": 900, "Overlay.qml": 750 }
for (const [file, cap] of Object.entries(LINE_CAPS)) {
  const lines = fs.readFileSync(path.join(root, file), "utf8").split("\n").length
  if (lines > cap) fail(`${file} is ${lines} lines (cap ${cap}); extract a delegate`)
}

if (failures) {
  process.exit(1)
}
console.log(`seam-test: ${qmlFiles.length} QML files clean, surfaces under caps`)
