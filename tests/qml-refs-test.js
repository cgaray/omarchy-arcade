// Check that every root property reference has a local or inherited declaration.

const fs = require("fs")
const path = require("path")

// Members every Item gets, plus the ones qs.Ui.Panel adds and the shell
// injects. Anything here is legitimately usable without a local declaration.
const INHERITED = new Set([
  // Item / QObject
  "width", "height", "x", "y", "z", "parent", "children", "visible", "enabled",
  "opacity", "clip", "anchors", "implicitWidth", "implicitHeight", "activeFocus",
  "focus", "forceActiveFocus", "childrenRect", "state", "states", "transitions",
  "rotation", "scale", "mapToItem", "mapFromItem", "objectName",
  // qs.Ui.Panel
  "bar", "moduleName", "settings", "ipcTarget", "manageIpc", "controller",
  "popoutSwitching", "popoutSwitchClosing", "opened", "open", "close", "toggle",
  "closeForPopoutSwitch", "switchPanel", "setting", "barForeground",
  // injected by the shell host onto plugin roots
  "manifest", "shell"
])

const files = process.argv.slice(2)
let failures = 0
let checked = 0

for (const file of files) {
  const src = fs.readFileSync(file, "utf8")
  const name = path.basename(file)

  const declared = new Set(INHERITED)

  // property int foo:  /  readonly property var foo:  /  property alias foo:
  for (const m of src.matchAll(/^\s*(?:readonly\s+)?property\s+[\w<>.]+\s+(\w+)/gm))
    declared.add(m[1])
  // function foo(
  for (const m of src.matchAll(/^\s*function\s+(\w+)\s*\(/gm)) declared.add(m[1])
  // signal foo(
  for (const m of src.matchAll(/^\s*signal\s+(\w+)/gm)) declared.add(m[1])

  const missing = new Map()
  for (const m of src.matchAll(/\broot\.(\w+)/g)) {
    checked += 1
    if (declared.has(m[1])) continue
    // Report each name at its first use.
    if (!missing.has(m[1])) {
      const line = src.slice(0, m.index).split("\n").length
      missing.set(m[1], line)
    }
  }

  for (const [prop, line] of missing) {
    console.error(`FAIL: ${name}:${line} reads root.${prop}, which nothing declares`)
    failures += 1
  }
}

if (failures) {
  console.error(`qml-refs-test: ${failures} undeclared`)
  process.exit(1)
}
console.log(`qml-refs-test: ${checked} root references, all declared`)
