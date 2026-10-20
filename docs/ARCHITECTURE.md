# 架构

## 一句话

APK 里塞一份 Debian rootfs，用 **proot**（用户态 chroot/ptrace）在 App 私有目录里把它跑起来，
里面跑 Node.js 24 + DSH web server；DSH 监听 `127.0.0.1:3080`，App 用 WebView 直接打开 —— 不需要
root、不需要电脑、不需要 Termux。

## APK 内部布局

```
assets/
  rootfs.tar.gz        ~890 MB  gzip 的 Debian 12 + Node 24 + /opt/dsh（DSH 源码+node_modules）
  runtime/
    proot              255 KB   Termux 构建的 proot（aarch64, Bionic）
    loader              18 KB   proot 执行 guest ELF 必需的加载器
    loader32             6 KB   32 位版（本机用不到，留着以防）
    libtalloc.so.2      33 KB   proot 依赖
    libandroid-shmem.so 14 KB   proot 依赖
  overlay/             原生模块覆盖层（flock 的 system.node、landlock-run），启动时写入 rootfs
  polyfill.js          ES2023/2024 API 补丁，注入 WebView
  instrument.js        诊断注入：console / 未捕获异常 / WebSocket 生命周期 → App 日志
classes.dex            约 45 KB：MainActivity / ProotServer / RuntimeInstaller / TarGzExtractor
```

## 启动时序

```
点击图标
  │
  ├─ MainActivity.onCreate
  │    ├─ 请求存储权限（READ/WRITE_EXTERNAL_STORAGE）
  │    ├─ rootfsReady()?  ── 否 ──► 解压 assets/rootfs.tar.gz 到 files/rootfs
  │    │                            （自研 TarGzExtractor，约 88,000 条目 / 3.9 GB，8–15 分钟）
  │    └─ 是
  │
  ├─ RuntimeInstaller.installBinaries()
  │    └─ assets/runtime/* → files/runtime/*（chmod +x）
  │
  ├─ RuntimeInstaller.applyPatches()
  │    ├─ assets/overlay/** → files/rootfs/**（只写缺失/尺寸不同的文件）
  │    └─ 后台线程尝试 GET http://<PC>:8099/patch.tar.gz → 解压进 rootfs（2.5s 超时，失败静默）
  │
  ├─ ProotServer.start()
  │    └─ ProcessBuilder:
  │         files/runtime/proot --link2symlink -r files/rootfs
  │             -b /dev -b /proc -b /sys -b /sdcard -b /storage
  │             -w /root
  │             /usr/bin/env -i HOME=/root PATH=... TERM=xterm-256color LANG=C.UTF-8
  │             /bin/bash /root/start-dsh.sh
  │         环境变量：
  │             LD_LIBRARY_PATH=files/runtime   （proot 自己依赖两个 .so）
  │             PROOT_LOADER=files/runtime/loader
  │             PROOT_TMP_DIR=files/tmp
  │             PROOT_NO_SECCOMP=1
  │
  ├─ 读 stdout/stderr 逐行 → 界面上「日志」
  │    正则匹配 http://127\.0\.0\.1:3080/\?token=[A-Za-z0-9_-]+
  │
  └─ 匹配到 → WebView.loadUrl(tokenUrl) → DSH 前端
```

## 组件职责

| 文件 | 职责 |
|---|---|
| `MainActivity.java` | 界面状态机（启动/解压/运行/失败）、WebView 配置、token 捕获回调、日志环、悬浮诊断菜单、权限请求、JS 日志桥 |
| `DshService.java` | 前台服务：常驻通知 + 保活；通知内「停止 DSH」；跨 Activity 实例复用同一 proot 进程 |
| `ProotServer.java` | 拼 proot 命令行、启动/停止子进程、把 stdout/stderr 送给监听者、正则捕获 token URL |
| `RuntimeInstaller.java` | 二进制安装、rootfs 有效性检查、解压调度、overlay/patch 应用、环境诊断 |
| `TarGzExtractor.java` | 纯 JDK 的 tar.gz 解析器（512 字节头、GNU 长名、PAX、符号链接/硬链接、权限位、路径穿越防护） |

### 后台保活（前台服务）

- DSH 就绪后启动 `DshService`（`startForeground` + 常驻通知），Android 会优先保留有前台服务的进程；
  proot 子进程属于本应用进程，因此进程活着 DSH 就活着。
- `MainActivity.onDestroy` **不再**停止 proot：界面销毁（切后台/划掉任务）后 DSH 继续运行；
  重新打开 App 时通过静态引用 `sServer` / `sTokenUrl` 直接恢复同一个会话。
- 退出入口只有两个：通知栏的「停止 DSH」，或 App 内「⋯ → 停止 DSH 并退出」。

## 为什么是「proot + Debian」

- 官方 DSH 运行时：Linux x64/arm64、macOS、Windows —— **没有 Android**
- Android 的 Bionic libc 与 glibc 二进制不兼容：`sharp`、`node-pty`、`native/system`（flock/landlock）
  这些预编译原生模块在 Bionic 上直接加载失败
- 而 **linux-arm64 + glibc** 是官方支持目标 → 套一个 Debian 用户空间，问题消失
- proot 不需要 root、不需要内核模块，普通 App 权限即可运行（Termux 同款方案）

## targetSdk 为什么必须是 28

Android 10+ 对高 targetSdk 的应用禁止从「应用私有数据目录」执行二进制/`dlopen`，而我们的
proot、loader、.so 全在 `files/` 下。targetSdk ≤ 28 时系统仍允许（Termux 用的就是这个历史豁免）。
打包时 `aapt2 link --target-sdk-version 28` 显式固定。

## WebView 集成

1. **token 自动捕获**：proot 的 stdout 里出现 `dsh web: http://127.0.0.1:3080/?token=...`，
   App 用正则抓出来直接 `loadUrl`，所以用户不需要手动复制 token。
2. **polyfill 注入**：`onPageStarted` / `onPageFinished` 里 `evaluateJavascript(polyfill.js)`，
   补齐旧内核缺失的 ES2023/2024 API（`Promise.withResolvers` 等）。这是「界面能开但发消息没反应」
   的根因修复。
3. **诊断注入**：`instrument.js` 包装 `console.*`、监听 `window.onerror` / `unhandledrejection`、
   包装 `WebSocket`（记录 open/close/error），通过 `addJavascriptInterface` 写进 App 日志 ——
   手机上没法开 DevTools 时，这是唯一能看到前端报错的通道。
4. **WebChromeClient**：不设置的话 JS `alert/confirm` 不弹窗、权限请求被拒。

## 补丁 / 覆盖层机制

因为 APK 有 890 MB，每改一个小文件都重新发版成本很高，所以有两条修补通道：

1. **内置 overlay**：`assets/overlay/` 下的文件在每次启动时覆盖到 rootfs 对应路径（只写缺失或
   尺寸不同的）。适合「确定要随 APK 分发给所有人」的修复。
2. **局域网补丁**：启动时后台 GET `http://<PC>:8099/patch.tar.gz`，解压进 rootfs。2.5 秒连不上就
   静默跳过，不影响离线使用。适合开发者在本机反复调试 rootfs 内容。
   （`RuntimeInstaller.applyRemotePatch` 里的 URL 是占位 `192.168.1.10`，改成你自己的地址，
   不需要就把这段删掉/留空。）

## 安全模型

- proot 是**用户态路径翻译**，不是安全隔离；guest 里的进程就是 App 自己的 uid
- APK 不含任何 token / API key，DSH 的凭据由用户自己的 profile 保存
- 局域网补丁通道是开发便利功能，正式分发建议关闭（或改成签名校验）
- `-b /sdcard`、`-b /storage` 让 DSH 能读写手机文件，这是**用户显式授权**的（运行时权限弹窗）
