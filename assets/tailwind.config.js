// See the Tailwind configuration guide for advanced usage
// https://tailwindcss.com/docs/configuration

const plugin = require("tailwindcss/plugin")
const fs = require("fs")
const path = require("path")

module.exports = {
  content: [
    "./js/**/*.js",
    "../lib/social_scribe_web.ex",
    "../lib/social_scribe_web/**/*.*ex"
  ],
  theme: {
    extend: {
      colors: {
        brand: "#FD4F00",
        hubspot: {
          overlay: "#B1B1B1",
          card: "#f5f8f7",
          input: "#CACDCC",
          icon: "#686F6F",
          checkbox: "#0871E8",
          pill: "#E1E5EA",
          "pill-text": "#121418",
          link: "#216FCC",
          "link-hover": "#1B5CB0",
          hide: "#676B70",
          "hide-hover": "#565A5E",
          cancel: "#151515",
          button: "#00B669",
          "button-hover": "#009A59",
          arrow: "#BBBCBB",
          avatar: "#C6CCD1",
          "avatar-text": "#0C1216",
        },
        salesforce: {
          overlay: "#B1B1B1",
          card: "#f5f8fa",
          input: "#C9C9C9",
          icon: "#706E6B",
          checkbox: "#0176D3",
          pill: "#E5E5E5",
          "pill-text": "#181818",
          link: "#0176D3",
          "link-hover": "#014486",
          hide: "#706E6B",
          "hide-hover": "#514F4D",
          cancel: "#181818",
          button: "#0176D3",
          "button-hover": "#014486",
          arrow: "#C9C9C9",
          avatar: "#B0ADAB",
          "avatar-text": "#181818",
        }
      }
    },
  },
  plugins: [
    require("@tailwindcss/forms"),
    // Allows prefixing tailwind classes with LiveView classes to add rules
    // only when LiveView classes are applied, for example:
    //
    //     <div class="phx-click-loading:animate-ping">
    //
    plugin(({addVariant}) => addVariant("phx-click-loading", [".phx-click-loading&", ".phx-click-loading &"])),
    plugin(({addVariant}) => addVariant("phx-submit-loading", [".phx-submit-loading&", ".phx-submit-loading &"])),
    plugin(({addVariant}) => addVariant("phx-change-loading", [".phx-change-loading&", ".phx-change-loading &"])),

    // Embeds Heroicons (https://heroicons.com) into your app.css bundle
    // See your `CoreComponents.icon/1` for more information.
    //
    plugin(function({matchComponents, theme}) {
      let iconsDir = path.join(__dirname, "../deps/heroicons/optimized")
      let values = {}
      let icons = [
        ["", "/24/outline"],
        ["-solid", "/24/solid"],
        ["-mini", "/20/solid"],
        ["-micro", "/16/solid"]
      ]
      icons.forEach(([suffix, dir]) => {
        fs.readdirSync(path.join(iconsDir, dir)).forEach(file => {
          let name = path.basename(file, ".svg") + suffix
          values[name] = {name, fullPath: path.join(iconsDir, dir, file)}
        })
      })
      matchComponents({
        "hero": ({name, fullPath}) => {
          let content = fs.readFileSync(fullPath).toString().replace(/\r?\n|\r/g, "")
          let size = theme("spacing.6")
          if (name.endsWith("-mini")) {
            size = theme("spacing.5")
          } else if (name.endsWith("-micro")) {
            size = theme("spacing.4")
          }
          return {
            [`--hero-${name}`]: `url('data:image/svg+xml;utf8,${content}')`,
            "-webkit-mask": `var(--hero-${name})`,
            "mask": `var(--hero-${name})`,
            "mask-repeat": "no-repeat",
            "background-color": "currentColor",
            "vertical-align": "middle",
            "display": "inline-block",
            "width": size,
            "height": size
          }
        }
      }, {values})
    })
  ]
}
