// Headless canvas renderer — loads a prepared HTML page in Chromium, waits
// for it to finish drawing (window.__done / window.__error), captures pixel
// probes and the canvas PNG.
//
// Run:  node render_page.mjs <page.html> <out.png> [probesJSON]
// Exit: 0 ok · 1 page error · 2 playwright unavailable (callers skip)
import fs from "node:fs"
import path from "node:path"
import { createRequire } from "node:module"
import { fileURLToPath } from "node:url"

const HERE = path.dirname(fileURLToPath(import.meta.url))
const [, , htmlPath, outPng, probesArg] = process.argv

// playwright resolution: $PLAYWRIGHT_NODE_MODULES, repo-local node_modules,
// or a sibling Therapy.jl checkout (same chain PlutoIslands uses).
const candidates = [
  process.env.PLAYWRIGHT_NODE_MODULES,
  path.join(HERE, "..", "node_modules/"),
  path.join(HERE, "..", "..", "Therapy.jl", "node_modules/"),
].filter(Boolean)
let chromium = null
for (const c of candidates) {
  try {
    chromium = createRequire(c.endsWith("/") ? c : c + "/")("playwright").chromium
    break
  } catch { }
}
if (!chromium) {
  console.error("playwright not found (tried: " + candidates.join(", ") + ")")
  process.exit(2)
}

const browser = await chromium.launch()
try {
  const page = await browser.newPage()
  await page.goto("file://" + path.resolve(htmlPath))
  await page.waitForFunction("window.__done === true || !!window.__error", { timeout: 15000 })
  const err = await page.evaluate("window.__error || ''")
  if (err) {
    console.error("PAGE ERROR: " + err)
    process.exit(1)
  }
  // settle rasterization before reading pixels — headless Chromium can
  // transiently report a blank canvas right after drawing (observed flake)
  await page.evaluate(() => new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r))))
  const probes = JSON.parse(probesArg || "[]")
  for (const [x, y] of probes) {
    const px = await page.evaluate(([x, y]) => {
      const d = document.getElementById("c").getContext("2d").getImageData(x, y, 1, 1).data
      return [d[0], d[1], d[2], d[3]]
    }, [x, y])
    console.log(`PROBE ${x},${y} = ${px.join(",")}`)
  }
  const dataUrl = await page.evaluate(() => document.getElementById("c").toDataURL("image/png"))
  fs.writeFileSync(outPng, Buffer.from(dataUrl.split(",")[1], "base64"))
  console.log("DONE")
} finally {
  await browser.close()
}
