# 部署指南（含国内访问方案）

站点是纯静态的：`site/` 目录下就是全部内容（`index.html` + `assets/`），
没有任何构建步骤，**任何静态托管都能直接部署**。

直接可用的部署包：`dist/dsh-mobile-site.zip`（约 900 KB，解压即站点根目录）。

---

## 0. 各平台在国内的可达性（2026 实测经验）

| 平台 | 默认域名 | 国内访问 | 需要什么 |
|---|---|---|---|
| GitHub Pages | `*.github.io` | ⚠️ 时好时坏（`*.github.io` 常见 DNS 污染/间歇性阻断） | 已有 ✅ |
| **Cloudflare Pages** | `*.pages.dev` | ⚠️ 部分网络可达，移动网络常不稳；**绑自定义域名 + Cloudflare CDN 后明显改善** | Cloudflare 账号（免费） |
| Netlify | `*.netlify.app` | ❌ 基本被污染，不建议作为国内主站 | 账号（免费） |
| **腾讯云 EdgeOne Pages** | `*.edgeone.app` | ✅ 国内节点，默认域名可访问（自定义域名需备案） | 腾讯云账号（免费额度，需实名） |
| **Gitee Pages** | `*.gitee.io` | ✅ 国内直连最快 | Gitee 账号（需实名认证，仓库公开） |
| 阿里云 OSS / 腾讯云 COS 静态网站 | 默认域名 | ✅ 国内直连 | 实名 + 少量费用；自定义域名需备案 |

**推荐组合**：Cloudflare Pages 作主站（免费、全球 CDN），
再加一个国内镜像（EdgeOne Pages 或 Gitee Pages）作为「国内加速入口」。

---

## 1. Cloudflare Pages（推荐主站）

### 方式 A：Git 集成（推荐，推代码自动部署）

1. Cloudflare Dashboard → Workers & Pages → Create → Pages → **Connect to Git**
2. 选择仓库 `mutoharohfiqabcd-source/dsh-mobile`
3. 构建设置：
   - Framework preset: **None**
   - Build command: **留空**
   - Build output directory: **`site`**
4. Save and Deploy → 以后每次 push `main` 自动重新部署

### 方式 B：命令行直传

```bash
npx wrangler login                       # 浏览器授权（只需一次）
npx wrangler pages deploy site --project-name dsh-mobile
```

### 方式 C：拖拽上传

Cloudflare Pages → Create → **Upload assets** → 把 `dist/dsh-mobile-site.zip` 解压后整个目录拖进去。

---

## 2. Netlify（备用，不建议做国内主站）

```bash
npx netlify login
npx netlify deploy --dir=site --prod
```

或网页端拖拽：<https://app.netlify.com/drop> → 拖 `dist/dsh-mobile-site.zip`。
仓库里已带 `netlify.toml`（`publish = "site"`），Git 集成也能直接用。

---

## 3. 国内镜像

### 3.1 腾讯云 EdgeOne Pages（国内访问最好）

1. 打开 <https://edgeone.cloud.tencent.com/pages>（腾讯云账号，需实名）
2. 创建 Pages 项目 → 选择「上传静态文件」或「连接 Git 仓库」
3. 上传 `dist/dsh-mobile-site.zip` 解压内容（或连接 GitHub 仓库、输出目录填 `site`）
4. 默认域名形如 `https://dsh-mobile-xxxx.edgeone.app`，国内可直连

### 3.2 Gitee Pages（最省事的国内镜像）

1. Gitee 新建仓库（公开）→ 把 `gh-pages` 分支内容推上去
   ```bash
   git clone https://github.com/mutoharohfiqabcd-source/dsh-mobile.git
   cd dsh-mobile
   git checkout gh-pages
   git remote add gitee https://gitee.com/<你的用户名>/dsh-mobile.git
   git push gitee gh-pages:master
   ```
2. Gitee 仓库 → 服务 → **Gitee Pages** → 部署分支 `master` → 启动
3. 地址：`https://<用户名>.gitee.io/dsh-mobile/`

> Gitee Pages 需要实名认证，且每次更新后要在页面上点一次「更新」重新部署。

### 3.3 免账号的临时镜像（CDN 反代，仅供预览）

```text
# jsDelivr（国内时好时坏）
https://cdn.jsdelivr.net/gh/mutoharohfiqabcd-source/dsh-mobile@gh-pages/index.html

# raw.githack（国外）
https://raw.githack.com/mutoharohfiqabcd-source/dsh-mobile/gh-pages/index.html
```

这些只适合临时预览，不建议作为正式入口（无自定义域名、可用性不稳定）。

### 3.4 自建反代（有服务器/域名时最稳）

用 Cloudflare Workers 或 Nginx 反代 GitHub Pages / Cloudflare Pages，
再绑一个已备案域名，国内访问即可获得稳定速度。示例 Worker：

```js
export default {
  async fetch(request, env) {
    const url = new URL(request.url)
    const upstream = 'https://mutoharohfiqabcd-source.github.io/dsh-mobile' + url.pathname
    return fetch(upstream, { cf: { cacheTtl: 3600 } })
  },
}
```

---

## 4. 本地/局域网预览（调试用）

```bash
cd dsh-mobile
python -m http.server 8090 --bind 0.0.0.0 --directory site
# 同 WiFi 手机访问 http://<PC 的局域网 IP>:8090/
```
