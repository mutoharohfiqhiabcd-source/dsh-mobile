#!/data/data/com.termux/files/usr/bin/bash
# dsh-phone 一键安装器 —— 在 Termux 里运行（不要在 Debian 里运行）
#
# 它做这些事（可重复运行，已完成的步骤会自动跳过）：
#   1. 防止手机休眠
#   2. Termux 源固定为中科大
#   3. 装 proot-distro
#   4. 装 Debian（已装则跳过）
#   5. 把 DSH 解包到 Debian 的 /opt/dsh
#   6. 在 Debian 里装 Node 24 + pnpm + 依赖
#   7. 生成 ~/start-dsh.sh 与 ~/stop-dsh.sh
#
# 用法：把整个安装包解压后，在 Termux 里执行 bash install.sh

set -o pipefail

TERMUX_PREFIX=/data/data/com.termux/files/usr
TERMUX_HOME=/data/data/com.termux/files/home

# ── 环境自愈 ────────────────────────────────────────────────────────────
# 从文件管理器 / 快捷方式点开脚本时，Android 会把它拷到临时目录并以“精简环境”
# 执行（没有 PREFIX / HOME / PATH），这里先把环境补全，而不是直接报错退出。
if [ -f /etc/debian_version ] && [ ! -d "$TERMUX_PREFIX/var/lib/proot-distro" ]; then
  printf '\n\033[1;31m[失败]\033[0m 这个脚本要在 Termux 里运行，不能在 proot Debian 里。\n' >&2
  echo "请先输入 exit 退出 Debian，回到 Termux 再运行。" >&2
  exit 1
fi
if [ -z "$PREFIX" ] || [ ! -x "$PREFIX/bin/bash" ]; then
  if [ -d "$TERMUX_PREFIX" ]; then
    export PREFIX="$TERMUX_PREFIX"
    case "${HOME:-}" in
      ""|"/") export HOME="$TERMUX_HOME" ;;
    esac
    export PATH="$PREFIX/bin:${PATH:-/system/bin}"
    export TMPDIR="${TMPDIR:-$PREFIX/tmp}"
    mkdir -p "$TMPDIR" 2>/dev/null || true
    echo "（检测到环境变量不完整，已自动补全 PREFIX / HOME / PATH）"
  else
    printf '\n\033[1;31m[失败]\033[0m 检测不到 Termux 环境（PREFIX 为空，且 %s 不存在）\n' "$TERMUX_PREFIX" >&2
    exit 1
  fi
fi

HERE=$(cd "$(dirname "$0")" && pwd)
LOG="$HOME/dsh-phone-install.log"
PAYLOAD="$HERE/dsh-phone.tar.gz"
OVERLAY="$HERE/mobile.patch.yml"
DEBSETUP="$HERE/setup-debian.sh"
ROOTFS="$PREFIX/var/lib/proot-distro/installed-rootfs/debian"

say() { printf '\n\033[1;36m===== %s =====\033[0m\n' "$*"; }
ok()  { printf '\033[1;32m[ok]\033[0m %s\n' "$*"; }
die() { printf '\n\033[1;31m[失败] %s\033[0m\n' "$*" >&2; exit 1; }

# ── 0. 环境检查 ─────────────────────────────────────────────────────────
say "0/7 环境检查"
for f in "$PAYLOAD" "$OVERLAY" "$DEBSETUP"; do
  [ -f "$f" ] || die "缺少文件：$f
请确认：在解压后的目录里运行本脚本，例如：
  cd ~/dsh-install && bash install.sh
（不要从文件管理器直接点开脚本，那样会在临时目录里跑，找不到安装包）"
done
command -v apt-get >/dev/null 2>&1 || die "Termux 环境不完整（缺 apt-get）"
ok "Termux 环境正常（PREFIX=$PREFIX），安装包完整"
echo "日志会写到：$LOG"

# ── 1. 防止休眠 ─────────────────────────────────────────────────────────
say "1/7 防止休眠"
if command -v termux-wake-lock >/dev/null 2>&1; then
  termux-wake-lock && ok "已获取 wakelock（装完可 termux-wake-unlock 释放）" || echo "wakelock 获取失败，继续"
else
  echo "termux-wake-lock 不存在，跳过"
fi

# ── 2. 固定 Termux 镜像（自动挑一个能连上的）────────────────────────────
say "2/7 Termux 源（自动挑可用镜像）"
rm -rf "$PREFIX/etc/termux/chosen_mirrors/"* 2>/dev/null || true
MIRROR=""
for m in \
  https://mirrors.ustc.edu.cn/termux/apt/termux-main \
  https://mirrors.tuna.tsinghua.edu.cn/termux/apt/termux-main \
  https://mirrors.zju.edu.cn/termux/apt/termux-main \
  https://packages.termux.dev/apt/termux-main
do
  if curl -fsS --max-time 8 -o /dev/null "$m/dists/stable/InRelease" 2>/dev/null; then
    MIRROR="$m"; echo "  可用镜像：$m"; break
  fi
  echo "  连不上，跳过：$m"
done
[ -n "$MIRROR" ] || MIRROR="https://mirrors.ustc.edu.cn/termux/apt/termux-main"
echo "deb $MIRROR stable main" > "$PREFIX/etc/apt/sources.list"
apt-get update -y >/dev/null 2>&1 || echo "  警告：apt update 有报错，继续用本地缓存列表"
ok "Termux 源：$MIRROR"

# ── 3. 装 proot-distro ──────────────────────────────────────────────────
say "3/7 安装 proot-distro"
command -v proot-distro >/dev/null 2>&1 || apt-get install -y proot-distro || die "安装 proot-distro 失败"
apt-get install -y tar xz-utils curl >/dev/null 2>&1
ok "proot-distro $(proot-distro --version 2>/dev/null | head -1)"

# ── 4. 装 Debian（用 login 探测是否已装，不猜路径）──────────────────────
say "4/7 准备 Debian"
if timeout 60 proot-distro login debian -- /bin/true >/dev/null 2>&1; then
  ok "Debian 已存在（能正常登录），跳过安装"
else
  echo "首次安装需要下载 rootfs（约 50-200 MB）"
  proot-distro install debian || die "Debian 安装失败：多为网络问题，重跑本脚本即可"
  timeout 60 proot-distro login debian -- /bin/true >/dev/null 2>&1 \
    || die "Debian 装好了但登录不进去，请把 proot-distro login debian 的输出发我"
  ok "Debian 安装完成"
fi

# 不同 proot-distro 版本 rootfs 路径不同，直接按 /etc/debian_version 找
BASE="$PREFIX/var/lib/proot-distro"
ROOTFS=$(find "$BASE" -maxdepth 5 -path '*/etc/debian_version' 2>/dev/null | head -1 | sed 's|/etc/debian_version$||')
if [ -z "$ROOTFS" ] || [ ! -d "$ROOTFS" ]; then
  echo "找不到 rootfs 目录，搜索到的 debian_version："
  find "$BASE" -maxdepth 5 -name debian_version 2>/dev/null | head -5
  die "无法定位 Debian rootfs（把上面的输出发我）"
fi
ok "rootfs: $ROOTFS"

# ── 5. 解包 DSH 到 Debian 的 /opt/dsh ──────────────────────────────────
say "5/7 解包 DSH（约 1-3 分钟）"
if [ "${DSH_FORCE_EXTRACT:-0}" != 1 ] && [ -f "$ROOTFS/opt/dsh/apps/cli/lib/bin.js" ] && [ -f "$ROOTFS/opt/dsh/apps/web/dist/index.html" ]; then
  ok "已解包过，跳过"
else
  if [ -d "$ROOTFS/opt/dsh" ]; then
    echo "清理旧版本文件（保留配置在 /root/.dsh-phone）"
    rm -rf "$ROOTFS/opt/dsh"
  fi
  mkdir -p "$ROOTFS/opt/dsh"
  tar -xzf "$PAYLOAD" -C "$ROOTFS/opt/dsh" || die "解包失败（存储空间不足？）"
  ok "解包完成"
fi
cp -f "$OVERLAY" "$ROOTFS/opt/dsh/mobile.patch.yml" || die "拷贝 mobile.patch.yml 失败"
[ -f "$ROOTFS/opt/dsh/apps/cli/lib/bin.js" ] || die "解包不完整：缺 apps/cli/lib/bin.js"
[ -f "$ROOTFS/opt/dsh/apps/web/dist/index.html" ] || die "解包不完整：缺前端产物"
ok "文件校验通过"

# ── 6. Debian 内安装 Node/deps ─────────────────────────────────────────
say "6/7 Debian 内安装（10-30 分钟，请保持屏幕常亮）"

# 直接把脚本放进 Debian 的 rootfs 再执行（不经过 base64 / 引号 / 参数传递，最不容易出错）
cp -f "$DEBSETUP" "$ROOTFS/root/setup-debian.sh" || die "拷贝 setup-debian.sh 到 Debian 失败"
chmod +x "$ROOTFS/root/setup-debian.sh"
[ -f "$ROOTFS/root/setup-debian.sh" ] || die "setup-debian.sh 没有出现在 Debian 的 /root 下"

echo ">>> 先确认能进入 Debian："
if ! proot-distro login debian -- cat /etc/debian_version 2>&1 | tee -a "$LOG"; then
  die "进不去 Debian：proot-distro login 失败（把上面的输出发我）"
fi
echo ""
echo ">>> 开始安装（输出同时写入 $LOG）"
proot-distro login debian -- /bin/bash /root/setup-debian.sh 2>&1 | tee -a "$LOG"
status=${PIPESTATUS[0]}
[ "$status" = 0 ] || die "Debian 内安装失败（退出码 $status），请把 $LOG 的最后 40 行发我"
ok "Debian 内安装完成"

# ── 7. 生成启动脚本 / 桌面图标 ─────────────────────────────────────────
say "7/7 生成启动脚本与桌面图标"
cat > "$HOME/start-dsh.sh" <<'EOS'
#!/data/data/com.termux/files/usr/bin/bash
# 启动手机上的 DSH：网页界面在 127.0.0.1:3080
termux-wake-lock 2>/dev/null
echo "正在启动 DSH（首次约 10-20 秒）..."
exec proot-distro login debian -- /root/start-dsh.sh
EOS
cat > "$HOME/stop-dsh.sh" <<'EOS'
#!/data/data/com.termux/files/usr/bin/bash
proot-distro login debian -- bash /root/dsh-stop.sh
EOS
chmod +x "$HOME/start-dsh.sh" "$HOME/stop-dsh.sh"

# 启动器（弹窗菜单：检测 / 启动 / 打开 / 停止 / 状态 / 更新）
if [ -f "$HERE/dsh-app.sh" ]; then
  cp -f "$HERE/dsh-app.sh" "$HOME/dsh-app.sh"
  chmod +x "$HOME/dsh-app.sh"
  mkdir -p "$HOME/.shortcuts"
  cp -f "$HERE/dsh-app.sh" "$HOME/.shortcuts/dsh.sh"
  chmod +x "$HOME/.shortcuts/dsh.sh"
  ok "启动器已装：$HOME/dsh-app.sh（桌面图标用 ~/.shortcuts/dsh.sh）"
else
  echo "注意：安装包里没有 dsh-app.sh，跳过启动器"
fi
if [ -f "$HERE/version.txt" ]; then
  cp -f "$HERE/version.txt" "$HOME/.dsh-phone-version"
  ok "安装包版本：$(cat "$HOME/.dsh-phone-version")"
fi

# ── 完成 ────────────────────────────────────────────────────────────────
cat <<'EOM'

============================================================
 安装完成 ✅
------------------------------------------------------------
 启动 DSH：   bash ~/start-dsh.sh
 停止 DSH：   bash ~/stop-dsh.sh
 弹窗菜单：   bash ~/dsh-app.sh      （= 桌面图标）
 安装日志：   ~/dsh-phone-install.log

 把它变成桌面 App 图标（推荐）：
   1) 从 F-Droid 安装 Termux:Widget
   2) 长按手机桌面 → 小部件 → 找到 Termux:Widget
   3) 拖到桌面，选择 dsh → 点图标就弹出菜单
   4) 想有原生弹窗，再装 Termux:API 并在 Termux 里执行
      pkg install termux-api
      （不装也能用：自动降级成终端数字菜单）

 启动成功后：浏览器会弹出带 token 的地址；第一次要在 DSH
 设置里填 DeepSeek API Key / 登录账号。之后浏览器菜单
 「添加到主屏幕」就是全屏 App 体验。
============================================================
EOM
