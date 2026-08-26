const plugin = require("tailwindcss/plugin")
const fs = require("fs")
const path = require("path")

module.exports = plugin(function({matchComponents, theme}) {
  let iconsDir = path.join(__dirname, "../../deps/lucide/icons")
  let values = {}

  if (fs.existsSync(iconsDir)) {
    fs.readdirSync(iconsDir)
      .filter(file => file.endsWith(".svg"))
      .forEach(file => {
        let name = path.basename(file, ".svg")
        values[name] = {name, fullPath: path.join(iconsDir, file)}
      })
  }

  matchComponents({
    "lucide": ({name, fullPath}) => {
      let content = fs.readFileSync(fullPath).toString().replace(/\r?\n|\r/g, "")
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
