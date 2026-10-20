// 用官方 favicon.svg 渲染 Android 图标各密度 PNG
// 输出：apk/res/mipmap-*dpi/ic_launcher.png（白底，legacy）
//       apk/res/drawable-*dpi/ic_launcher_foreground.png（透明底，自适应前景）
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { chromium } from 'playwright-core'

const REPO = 'D:\\deepseek-harness-master\\deepseek-harness-master'
const SVG = readFileSync(join(REPO, 'apps/web/public/favicon.svg'), 'utf8')
const OUT = '.\\apk\\res'

const legacy = [
  ['mipmap-mdpi', 48], ['mipmap-hdpi', 72], ['mipmap-xhdpi', 96],
  ['mipmap-xxhdpi', 144], ['mipmap-xxxhdpi', 192],
]
// 自适应图标画布 108dp，前景安全区约 66%，鲸鱼占 60%
const foreground = [
  ['drawable-mdpi', 108], ['drawable-hdpi', 162], ['drawable-xhdpi', 216],
  ['drawable-xxhdpi', 324], ['drawable-xxxhdpi', 432],
]

const dir = mkdtempSync(join(tmpdir(), 'dsh-icon-'))
const ctx = await chromium.launchPersistentContext(dir, {
  channel: 'chrome', headless: true, viewport: { width: 512, height: 512 },
})
const page = ctx.pages()[0] ?? await ctx.newPage()

function svgAt(px) {
  return SVG.replace(/width="50(\.0*)?"/, `width="${px}"`).replace(/height="50(\.0*)?"/, `height="${px}"`)
}

async function render(path, size, whalePx, bg) {
  const html = `<!doctype html><html><head><meta charset="utf-8"><style>
    html,body{margin:0;padding:0;width:${size}px;height:${size}px;background:${bg};}
    .wrap{width:100%;height:100%;display:flex;align-items:center;justify-content:center;}
    .wrap svg{width:${whalePx}px;height:${whalePx}px;display:block;}
  </style></head><body><div class="wrap">${svgAt(whalePx)}</div></body></html>`
  await page.setViewportSize({ width: size, height: size })
  await page.setContent(html, { waitUntil: 'load' })
  await page.screenshot({ path, omitBackground: bg === 'transparent' })
  mkdirSync(join(OUT, path.split(/[\\/]/).slice(-2, -1)[0]), { recursive: true })
}

const jobs = []
for (const [d, size] of legacy) jobs.push([join(OUT, d, 'ic_launcher.png'), size, Math.round(size * 0.74), '#ffffff'])
for (const [d, size] of foreground) jobs.push([join(OUT, d, 'ic_launcher_foreground.png'), size, Math.round(size * 0.60), 'transparent'])

for (const [path, size, whale, bg] of jobs) {
  await render(path, size, whale, bg)
  console.log(`  ${path.replace(OUT, 'res')}  ${size}x${size}  whale=${whale}px  bg=${bg}`)
}

// 额外：512 预览图
await page.setViewportSize({ width: 512, height: 512 })
await page.setContent(`<html><body style="margin:0;width:512px;height:512px;background:#fff;display:flex;align-items:center;justify-content:center">${svgAt(380)}</body></html>`)
await page.screenshot({ path: '.\\icon-preview-512.png' })
console.log('preview: icon-preview-512.png')

writeFileSync(join(OUT, '..', 'icon-render-log.txt'), jobs.map((j) => j[0]).join('\n'), 'utf8')
await ctx.close()
