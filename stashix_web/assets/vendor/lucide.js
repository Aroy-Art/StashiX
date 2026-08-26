const plugin = require("tailwindcss/plugin")
const fs = require("fs")
const path = require("path")

// Scan lib/ for every lucide-ICONNAME reference so we only embed used icons.
function findUsedIcons(dir) {
  const used = new Set()
  function walk(current) {
    for (const entry of fs.readdirSync(current, {withFileTypes: true})) {
      const full = path.join(current, entry.name)
      if (entry.isDirectory()) {
        walk(full)
      } else if (/\.(ex|heex|js)$/.test(entry.name)) {
        const content = fs.readFileSync(full, "utf8")
        for (const [, name] of content.matchAll(/lucide-([a-z0-9-]+)/g)) {
          used.add(name)
        }
      }
    }
  }
  walk(dir)
  return used
}

module.exports = plugin(function({matchComponents, theme}) {
  const iconsDir = path.join(__dirname, "../../deps/lucide/icons")
  const libDir = path.join(__dirname, "../../lib")

  const usedIcons = findUsedIcons(libDir)

  const values = {}
  for (const name of usedIcons) {
    const fullPath = path.join(iconsDir, `${name}.svg`)
    if (fs.existsSync(fullPath)) {
      values[name] = {name, fullPath}
    }
  }

  matchComponents({
    "lucide": ({name, fullPath}) => {
      const content = fs.readFileSync(fullPath, "utf8").replace(/\r?\n|\r/g, "")
      return {
        [`--lucide-${name}`]: `url('data:image/svg+xml;utf8,${content}')`,
        "-webkit-mask": `var(--lucide-${name})`,
        "mask": `var(--lucide-${name})`,
        "mask-repeat": "no-repeat",
        "mask-size": "100%",
        "background-color": "currentColor",
        "vertical-align": "middle",
        "display": "inline-block",
        "width": theme("spacing.5"),
        "height": theme("spacing.5")
      }
    }
  }, {values})
})
