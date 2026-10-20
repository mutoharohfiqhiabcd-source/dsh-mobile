# 构建指南

以下步骤在 Windows + PowerShell 5.1 上验证过；Linux/macOS 也可以，只需把 `build-apk.ps1` 里的命令逐条照抄成 shell（逻辑完全一样）。

## 0. 工具链

需要（不必装 Android Studio / Gradle）：

| 组件 | 版本 | 说明 |
|---|---|---|
| JDK | 17 | 用于 `javac` / `d8` / `apksigner` / `keytool` |
| Android build-tools | 34.0.0 | 提供 `aapt2`、`d8`、`zipalign`、`apksigner` |
| Android platform | android-34 | 提供 `android.jar` |
| Python | 3.x | 仅用于「把 dex / rootfs 追加进 zip」这两步 |

期望目录结构：

```
dsh-mobile/
  android-tools/
    jdk17/jdk-17.x.y/        <- 解压后的 JDK（或设置 DSH_JDK 环境变量）
    sdk/
      build-tools/34.0.0/
      platforms/android-34/android.jar
```

JDK 17 可以从 [Adoptium](https://adoptium.net) 或清华镜像下载；
`build-tools` 与 `platform-34` 可以从 `https://dl.google.com/android/repository/` 下（
`build-tools_r34-windows.zip`、`platform-34_r02.zip`），解压后放到上面位置即可。

## 1. 取 proot 运行时（在 Termux 里做）

```bash
pkg install proot libtalloc libandroid-shmem
# 把本项目 clone 到手机，或把 scripts/ 传过去
bash scripts/fetch-runtime.sh          # 产出 apk/assets/runtime/{proot,loader,loader32,libtalloc.so.2,libandroid-shmem.so}
```

`proot` + `loader` 缺一不可 —— proot 执行 guest ELF 时靠 loader 做动态链接器桥接，只拷 `proot` 会得到
`execve(...): Permission denied`。

## 2. 取原生模块（overlay）

```bash
bash scripts/fetch-overlay.sh          # 产出 apk/assets/overlay/opt/dsh/native/system/packages/linux-arm64/bin/...
```

原因：DSH 的 `native/system/packages/linux-arm64` 在源码仓库里只有 `prebuilds.json`，真正的
`system.node`（flock）和 `landlock-run` 是 CI 编译后发到 npm 的。不补这两个文件，DSH 一调用工具就会报
`Cannot find module '.../bin/glibc/system.node'`。

## 3. 准备 rootfs.tar.gz

这是最重的一步：需要一个 **Debian 12 (aarch64, glibc) + Node.js 24 + DSH（带 node_modules）** 的
rootfs，打包成 `apk/rootfs-asset/rootfs.tar.gz`。

### 方案 A：用 `rootfs/` 里的脚本（推荐，原作者用的路线）

在 **Termux** 里（不是 Debian 里）按顺序执行：

```bash
pkg install proot-distro
proot-distro install debian

bash rootfs/make-rootfs.sh     # Debian 内：换源、装 Node 24、安装 DSH 源码、pnpm install
bash rootfs/fix-deps.sh        # 处理 pnpm workspace / 补丁 / 依赖问题
bash rootfs/finish.sh          # 写 /root/start-dsh.sh 等启动脚本
bash rootfs/slim-rootfs.sh     # 瘦身（删 store/缓存/文档），可跳过
bash rootfs/pack-final.sh      # 打包 + 上传到你的 PC（改脚本里的 IP/端口）
```

每个脚本开头都有注释说明它在做什么。注意脚本里的 IP 是占位（`192.168.1.10`），按需替换。

### 方案 B：自己准备一个 rootfs

只要满足下面这些条件，任何方式构建的 rootfs 都能用：

- 架构 `linux-arm64`，libc = **glibc**（Debian/Ubuntu 都行，Alpine 不行）
- `/usr/local/bin/node` 是 Node.js `^22.19.0 || >=24.0.0`（官方 engines 要求）
- DSH 源码/发布内容在 `/opt/dsh`，`/opt/dsh/apps/cli/lib/bin.js` 存在
- `/root/start-dsh.sh` 启动 DSH web 并输出形如
  `dsh web: http://127.0.0.1:3080/?token=xxxx` 的一行（App 用正则抓这一行）
- `/opt/dsh/node_modules` 完整（**用 `pnpm install --package-import-method=copy`**，见
  [LESSONS.md](LESSONS.md) 第 5 条）
- rootfs 里不要有 `.l2s` 目录（那是 proot 硬链接模拟的临时产物，见 LESSONS 第 4 条）

产物参考：**gzip 后约 890 MB，解压后约 3.9 GB**。

把 tar.gz 放到：

```
apk/rootfs-asset/rootfs.tar.gz
```

tar 里的路径应该以 `./` 开头（`./opt/dsh/...`、`./usr/local/bin/node`……），App 用自研解析器
`TarGzExtractor` 解压，不需要 root、不依赖系统 tar。

## 4. 打包

```powershell
powershell -ExecutionPolicy Bypass -File build-apk.ps1 -VersionCode 1 -VersionName 1.0
# 产物：dist/DSH-Mobile.apk
```

首次运行会自动生成 `release.jks`（密码 `dshmobile`，别名 `dsh`）。想用自己的签名：设置
`DSH_KEYSTORE` 环境变量指向已有 keystore，或直接改脚本里的 keytool/apksigner 参数。

版本号也可以走环境变量：`DSH_VERSION_CODE` / `DSH_VERSION_NAME`。

## 5. 自检清单

打包完成后建议核对：

```powershell
# 版本 / 权限
aapt2 dump badging dist/DSH-Mobile.apk | findstr "package: uses-permission"
# 签名
apksigner verify --print-certs dist/DSH-Mobile.apk
# 内置资产（rootfs 应该是 STORED，不压缩）
python -c "import zipfile;z=zipfile.ZipFile('dist/DSH-Mobile.apk');[print(n,z.getinfo(n).file_size,z.getinfo(n).compress_type) for n in ('assets/rootfs.tar.gz','classes.dex','assets/runtime/proot','assets/runtime/loader')]"
```

装机后看 App 日志应出现：

```
内置 rootfs 解压完成，共 XXXXX 个条目
[out] dsh web: http://127.0.0.1:3080/?token=...
检测到服务地址: ...
[web] instrument: installed
```

然后 WebView 里就是 DSH 界面。

## 常见构建/启动失败

| 现象 | 原因 | 处理 |
|---|---|---|
| `execve("/usr/bin/env"): Permission denied` | 缺 proot loader | 确认 `assets/runtime/loader` 存在，且启动时设置了 `PROOT_LOADER` |
| `Cannot find module .../js-yaml/index.js` | 打包时删了 `.l2s`（硬链接实体） | 重装 node_modules，见 LESSONS 4/5 |
| `Cannot find package '@deepseek-ai/cordis'` | pnpm 工作区包没链接 | 手工建 `node_modules/@deepseek-ai/*` 符号链接，见 LESSONS 6 |
| `EACCES ... link` | Android 拒绝硬链接 | proot 加 `--link2symlink`，见 LESSONS 2 |
| 界面能显示但发消息没反应 | WebView 缺 ES2024 API | 补 polyfill，见 LESSONS 7 |
| `Cannot find module ... system.node` | 缺 flock 原生模块 | `scripts/fetch-overlay.sh`，见 LESSONS 8 |
| aapt2 卡在 900 MB 资产压缩 | aapt2 会 deflate 大文件 | 不放进 `assets/` 让 aapt2 处理，改为 ZIP_STORED 追加 |
