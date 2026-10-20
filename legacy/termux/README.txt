dsh-phone 安装包（手机本地版 DSH）
=====================================

这个包会在一台 Android 手机（Termux）里装出一套能自己跑的 DSH：
手机浏览器打开 http://127.0.0.1:3080 就是完整界面，不需要电脑、不需要服务器、
不需要公网暴露。

包里的东西
  install.sh            一键安装脚本（在 Termux 里运行）
  setup-debian.sh       Debian 内使用的安装脚本（由 install.sh 自动调用）
  dsh-phone.tar.gz      DSH 源码 + 已编译好的前端/CLI 产物（约 62 MB）
  mobile.patch.yml      监听 0.0.0.0 的配置覆盖
  README.txt            本文件

前置条件
  1. Termux：从 F-Droid 或 GitHub Releases 安装（不要用 Google Play 版）
  2. 手机剩余空间 ≥ 5 GB
  3. 网络可用（会下载 Debian rootfs ~200 MB、Node 24 ~30 MB、npm 依赖 ~1.5 GB）

安装步骤
  1. 把本包解压到一个目录，比如 ~/dsh-install/
  2. 在 Termux 里执行（只跑这一条，不要单独去跑 setup-debian.sh）：
        cd ~/dsh-install && bash install.sh
  3. 等着（首次 10-30 分钟，中间不要锁屏，别把 Termux 从后台划掉）

  注意：setup-debian.sh 是给 Debian 内部用的，在 Termux 里直接跑会报
  “apt-get: inaccessible or not found”。install.sh 会自动把它放进
  Debian 里执行，你不需要手动管它。

装完之后
  启动： bash ~/start-dsh.sh
  停止： bash ~/stop-dsh.sh
  弹窗菜单： bash ~/dsh-app.sh
  然后浏览器打开 Termux 里打印的那个 http://127.0.0.1:3080/?token=... 地址
  （第一次要在 DSH 设置里填 DeepSeek API Key / 登录账号）

做成桌面 App 图标（推荐）
  1. 从 F-Droid 安装 Termux:Widget
  2. 长按桌面 → 小部件 → Termux:Widget → 拖到桌面 → 选 dsh
  3. 点图标弹出菜单：启动 / 打开界面 / 停止 / 状态 / 日志 / 检测更新
  4. 想要系统原生弹窗：F-Droid 安装 Termux:API，并在 Termux 里执行
     pkg install termux-api
     （不装也能用，会自动降级成终端里的数字菜单）

  菜单里的「检测更新」会连你电脑上的下载服务（默认
  http://192.168.1.10:8099），比较版本号，有新版会弹窗问你要不要更新。

失败了怎么办
  日志在 ~/dsh-phone-install.log
  绝大多数失败是网络问题：重跑一次 bash install.sh 即可（已完成的步骤会跳过）
