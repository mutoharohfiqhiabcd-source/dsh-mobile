# 踩坑记录（按踩坑顺序）

把 DSH 塞进 Android 的过程里，几乎每一层都有一个反直觉的坑。这里按「现象 → 原因 → 解法」记录，
二次开发前建议通读一遍，能省掉大量时间。

---

### 1. 「Android 不能跑 DSH」不是权限问题，是 libc 问题

**现象**：Termux 里直接 `pnpm install` 后 `node apps/cli/lib/bin.js --profile web`，报
`No usable native binding found` / `sharp` 加载失败 / `native/system` 拒绝启动。

**原因**：官方 DSH 的目标平台是 linux-x64 / linux-arm64(glibc) / macOS / Windows。
Android 是 Bionic libc，`sharp`、`node-pty`、flock/landlock 这些预编译原生模块都对不上。

**解法**：套一层 Debian（glibc），让 DSH 以为自己跑在官方支持的 linux-arm64 上。proot 提供免 root 的
用户态环境。

---

### 2. `--link2symlink` 必须开，否则 EACCES

**现象**：DSH 启动后，发消息立刻失败：

```
EACCES: permission denied, link '/root/.dsh-phone/sessions/.../session.v4.jsonl.zstd.xxx.tmp'
                                    -> '.../session.v4.jsonl.zstd'
```

**原因**：DSH 的会话持久化用 `fs.link()` 做原子发布（先写 `.tmp`，再硬链接成正式文件）。
**Android 上硬链接经常被系统拒绝**，而 proot 默认直接透传 `link()`，于是 EACCES。

**解法**：proot 加 `--link2symlink`（用符号链接模拟硬链接）。Termux 的 proot-distro 默认就带这个参数；
自己手写 proot 启动命令时极易漏掉。

---

### 3. proot 需要 loader，缺了就是「Permission denied」

**现象**：

```
proot error: execve("/usr/bin/env"): Permission denied
proot info: possible causes:
  * the program is an ELF but its interpreter (eg. ld-linux.so) was not found;
  * the loader was not found or doesn't work.
```

**原因**：proot 执行 guest ELF 时需要自己的 loader（`$PREFIX/libexec/proot/loader`）来做
动态链接器桥接。只拷 `proot` 一个文件，exec 就会失败。

**解法**：把 `loader`、`loader32`（32 位版）一起带上，并在启动时显式设置
`PROOT_LOADER=<绝对路径>`（proot 编译时默认路径指向 Termux 目录，App 里必须覆盖）。

---

### 4. `.l2s` 不是垃圾，删了 rootfs 就废了

**现象**：从 Termux 的 proot-distro Debian 里打包 rootfs 时发现多了 4.5 GB 的
`<rootfs>/.l2s/.l2s.<hash>` 文件，以为是临时文件删掉了。重装到 App 后：

```
Error: Cannot find package '.../.pnpm/js-yaml@4.2.0/node_modules/js-yaml/index.js'
```

**原因**：`--link2symlink` 把 pnpm store → node_modules 的**硬链接**替换成了指向 `.l2s/` 的
**符号链接**，`.l2s/` 里才是真实文件内容。删掉 `.l2s/` 等于删掉所有包的内容（本项目实测：
33,587 个断链）。

**解法**：
- 打包 rootfs 时**保留** `.l2s/`（或者更好的做法见第 5 条：让它根本不产生）
- 已经删了的话只能重装 node_modules

---

### 5. pnpm 在 `--link2symlink` 下安装 = 埋雷；用「复制模式」

**原因**：同第 4 条。pnpm 默认从全局 store 硬链接到 node_modules，proot 会把硬链接变成指向
`.l2s` 的符号链接，rootfs 一挪位置就全断。

**解法**：安装时强制复制而不是硬链接：

```bash
pnpm install --prod --ignore-scripts --package-import-method=copy
```

代价是 node_modules 变大（APK 从 ~175 MB 变成 ~890 MB，主要就是这个），但换来 rootfs 可移植。

---

### 6. pnpm 的 workspace 链接在手机上会「消失」

**现象**：`pnpm install` 成功，但 DSH 启动报：

```
Error: Cannot find package '@deepseek-ai/cordis' imported from /opt/dsh/packages/boot/app-boot/lib/index.js
```

**原因**：DSH 是 pnpm workspace（`vendor/*`、`packages/*/*`、`apps/*`、`native/system/packages/*`），
包之间靠 `workspace:~` 协议链接。在手机这种环境里 pnpm 没能把这些工作区包正确链接进
`node_modules/@deepseek-ai/*`（实测只链上了 2 个）。

**解法**：手工把每个工作区包链接进根 `node_modules`（`rootfs/fix-node-modules.sh` 里有现成脚本）：

```bash
cd /opt/dsh
for pkgdir in vendor/* packages/*/* apps/* native/system native/system/packages/*; do
  name=$(node -p "require('./$pkgdir/package.json').name" 2>/dev/null) || continue
  [ -e "node_modules/$name/package.json" ] && continue
  case "$name" in
    @*/*) ln -sfn "../../$pkgdir" "node_modules/$name" ;;  # 作用域包
    *)    ln -sfn "../$pkgdir" "node_modules/$name" ;;
  esac
done
```

---

### 7. 界面能开、发消息没反应 → 旧 WebView 缺 ES2024 API

**现象**：DSH 界面正常显示，WebSocket 甚至都连上了（`ws.open.ok`），但发消息永远没有回复，
没有思考、没有报错。日志里：

```
Uncaught TypeError: Promise.withResolvers is not a function
[session-controller] control stream failed: RemoteError: Promise.withResolvers is not a function
```

**原因**：DSH 前端按现代 Chrome（119+）构建，用了 `Promise.withResolvers` 等新 API；手机系统
WebView 内核偏旧，一执行就崩，控制流建立失败 → 消息发得出去但回不来。

**解法**：在页面脚本执行前注入 polyfill（`apk/assets/polyfill.js`），补上
`Promise.withResolvers`、`Promise.try`、`AbortSignal.any/timeout`、`Object/Map.groupBy`、
`Array.prototype.toSorted/toReversed/toSpliced/with/findLast`、`Set` 集合运算、`URL.canParse`、
`structuredClone`、`RegExp.escape` 等。

**排查手段**：手机上开不了 DevTools，于是 `instrument.js` 把 `console.*`、`window.onerror`、
`unhandledrejection`、`WebSocket` 生命周期全写进 App 日志 —— 这次就是靠它定位的。

---

### 8. flock 的原生模块不在仓库里，在 npm 上

**现象**：DSH 能启动、能连上模型，一执行工具就报：

```
本轮运行失败 Cannot find module '/opt/dsh/native/system/packages/linux-arm64/bin/glibc/system.node'
Require stack: - /opt/dsh/native/system/packages/entry/lib/flock.js
```

**原因**：`native/system/packages/linux-arm64` 在源码仓库里只有 `package.json` +
`prebuilds.json`，真正的 `bin/glibc/system.node`、`bin/landlock-run` 是 CI 编译后
发布到 npm 的（`@deepseek-ai/node-addon-system-linux-arm64`）。

**解法**：从 npm 拉二进制补进 rootfs（`scripts/fetch-overlay.sh`）。
App 侧再配一个 `assets/overlay/` 机制在启动时写入 rootfs，这样补丁能随 APK 分发。

---

### 9. aapt2 压缩 900 MB 资产会卡死；ZIP_STORED 追加

**现象**：把 `rootfs.tar.gz` 放进 `apk/assets/` 后，`aapt2 link` 长时间无响应（它在做 deflate，
而 tar.gz 已经压过了，纯浪费时间）。

**解法**：rootfs 不交给 aapt2，改为在 `aapt2 link` + 添加 `classes.dex` 之后，用 Python
`zipfile` 以 **ZIP_STORED** 流式追加 `assets/rootfs.tar.gz`，最后再 `zipalign -p 4` + 签名。
（`build-apk.ps1` 第 5.5 步）

---

### 10. targetSdk 必须是 28

**原因**：Android 10+ 对 targetSdk ≥ 29 的应用禁止从应用私有目录 `exec`/`dlopen`。proot、
loader、.so 都在 `files/` 下，所以只能固定在 28（Termux 同款豁免）。minSdk 26。

---

### 11. App 图标用官方 favicon 渲染

官方 DSH 图标是 `apps/web/public/favicon.svg`（白色背景 + 黑色鲸鱼）。用 Playwright/无头浏览器
渲染成各密度的 `ic_launcher.png` 与自适应图标的 `ic_launcher_foreground.png`
（`scripts/icon-render.mjs`）。

---

### 12. 自研 tar 解析器，因为 commons-compress 让 d8 崩了

**现象**：用 `commons-compress` + `commons-lang3` 解析 tar.gz，`d8` 报
`NullPointerException: String.length()`；降版本一样崩。

**解法**：手写 `TarGzExtractor`（纯 JDK）：512 字节头、八进制/base-256 数字解析、GNU 长文件名
（`L`/`K`）、PAX 头（`x`/`X`）、类型 `0/5/2/1`、padding、路径穿越防护、权限位应用。
classes.dex 从 1.5 MB 降到约 45 KB。

---

### 13. PowerShell 5.1 的编码地雷

- 含中文的 `.ps1` 用 UTF-8 **无 BOM** 保存，PowerShell 5.1 会按 GBK 解码 → 引号被吞 →
  语法错误。**构建脚本保持 ASCII-only**。
- `Get-Content`/`Set-Content -Encoding utf8` 往返会写 BOM 并可能弄坏中文 → javac 报
  `illegal character '\ufeff'`。编辑 Java/脚本文件用能保证 UTF-8 无 BOM 的工具。

---

### 14. proot 里的「Android 后台杀进程」和耗电

App 退到后台后系统随时可能杀掉进程，DSH 进程随之消失。要长期后台运行需要前台服务
（`FOREGROUND_SERVICE` + 常驻通知）；proot 本身也有 10–30% 性能开销与额外耗电。

---

### 15. 其他小坑

- `/api` 要求 **Host == Origin**，cookie 绑定 `host:port`；换端口/域名要重新扫码
- DSH 自报的 LAN 地址可能是虚拟网卡（如 xray 的 `172.18.0.1`），启动器要自己算真实 IP
- 会话目录名里的中文目录会被转义成 `~73A9~4E0D~73A9` 这种形式，正常现象
- Termux 的 `pkg` 会自动选镜像且可能选到挂掉的（NJU 探针 OK 实际超时）→ 用 `apt` +
  写死 `mirrors.ustc.edu.cn`
- proot 的 `-b /sdcard` 需要 App 已获得存储权限，否则 guest 里读 `/sdcard` 会 EACCES
