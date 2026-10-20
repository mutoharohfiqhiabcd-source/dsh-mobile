#!/data/data/com.termux/files/usr/bin/bash
# DSH 手机版启动器（桌面图标用）
#
# 功能：
#   · 自动检测：是否安装 / 当前是否运行 / 版本号
#   · 弹窗菜单：启动、打开界面、停止、状态、日志、检测更新
#   · 启动后自动用浏览器打开带 token 的地址
#
# 用法：
#   bash ~/dsh-app.sh            # 弹窗菜单（桌面图标走这个）
#   bash ~/dsh-app.sh --status   # 只打印检测结果
#   bash ~/dsh-app.sh --start    # 直接启动
#
# 想有原生弹窗：装 Termux:API（F-Droid）+ pkg install termux-api
# 没装也能用：自动降级成终端里的数字菜单。

ROOTFS="$PREFIX/var/lib/proot-distro/installed-rootfs/debian"
RUN_LOG="$HOME/dsh-run.log"
URL_FILE="$HOME/dsh-url.txt"
VER_FILE="$HOME/.dsh-phone-version"
PC_FILE="$HOME/.dsh-pc-url"

INSTALLED=0; RUNNING=0; VERSION=unknown

say()  { printf '%s\n' "$*"; }
line() { printf '%s\n' "------------------------------------------------------------"; }
have_api()   { command -v termux-dialog >/dev/null 2>&1; }
have_toast() { command -v termux-toast  >/dev/null 2>&1; }
toast() { have_toast && termux-toast -g middle "$*" >/dev/null 2>&1; }

dlg_text()  { # $1=标题 $2=默认值 → 打印用户输入
  if have_api; then
    termux-dialog text -t "$1" -i "$2" 2>/dev/null | sed -n 's/.*"text"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
  else
    printf '%s' "" >&2; read -r -p "$1 [$2]: " ans; printf '%s' "${ans:-$2}"
  fi
}
dlg_confirm() { # $1=标题 → 0=同意
  if have_api; then
    [ "$(termux-dialog confirm -t "$1" 2>/dev/null | sed -n 's/.*"text"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')" = yes ]
  else
    read -r -p "$1 [y/N]: " ans; [ "$ans" = y ] || [ "$ans" = Y ]
  fi
}
dlg_radio() { # $1=标题 $2=逗号分隔选项 → 打印选中项
  # 注意：调用方用 CHOICE=$(dlg_radio ...) 捕获 stdout，所以菜单本身必须写 stderr，
  # 否则用户只会看到 "输入序号:" 而看不到选项（已踩过的坑）。
  if have_api; then
    termux-dialog radio -t "$1" -v "$2" 2>/dev/null | sed -n 's/.*"text"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
  else
    local i=1 item
    printf '%s\n' "$1" >&2
    local IFS=,
    for item in $2; do printf '  %s) %s\n' "$i" "$item" >&2; i=$((i+1)); done
    read -r -p "输入序号（直接回车 = 默认项）: " n
    i=1
    for item in $2; do [ "$n" = "$i" ] && { printf '%s' "$item"; return; }; i=$((i+1)); done
  fi
}

# ── 检测 ────────────────────────────────────────────────────────────────
probe() {
  INSTALLED=0; RUNNING=0; VERSION=unknown
  local out l
  # 不猜 rootfs 路径，直接让 Debian 自己报告（未安装/未装好时 60 秒内返回失败）
  out=$(timeout 60 proot-distro login debian -- /bin/bash /root/dsh-probe.sh 2>/dev/null) || return 0
  while IFS= read -r l; do
    case "$l" in
      installed=*) INSTALLED="${l#installed=}" ;;
      running=*)   RUNNING="${l#running=}"   ;;
      version=*)   VERSION="${l#version=}"   ;;
    esac
  done <<< "$out"
}

summary() {
  local state
  if [ "$INSTALLED" != 1 ]; then state="未安装"; elif [ "$RUNNING" = 1 ]; then state="运行中"; else state="已停止"; fi
  printf 'DSH %s · %s' "$VERSION" "$state"
}

# ── 动作 ────────────────────────────────────────────────────────────────
open_ui() {
  local url=""
  [ -f "$URL_FILE" ] && url=$(head -1 "$URL_FILE")
  if [ -n "$url" ]; then
    termux-open-url "$url" >/dev/null 2>&1 || say "请手动打开：$url"
  else
    termux-open-url "http://127.0.0.1:3080/" >/dev/null 2>&1 || say "请手动打开：http://127.0.0.1:3080/"
  fi
}

start_dsh() {
  if [ "$RUNNING" = 1 ]; then say "已在运行，直接打开界面"; open_ui; return 0; fi
  say "正在启动（约 10-20 秒）…"
  : > "$RUN_LOG"; : > "$URL_FILE"
  nohup proot-distro login debian -- /root/start-dsh.sh > "$RUN_LOG" 2>&1 &
  local i url=""
  for i in $(seq 1 90); do
    sleep 1
    url=$(grep -oE 'http://127\.0\.0\.1:[0-9]+/\?token=[A-Za-z0-9_-]+' "$RUN_LOG" 2>/dev/null | head -1)
    [ -n "$url" ] && break
    grep -q 'Error\|错误' "$RUN_LOG" 2>/dev/null && break
  done
  if [ -n "$url" ]; then
    printf '%s\n' "$url" > "$URL_FILE"
    toast "DSH 已启动"
    open_ui
    return 0
  fi
  say "启动失败或超时。日志尾部："
  line; tail -n 20 "$RUN_LOG" 2>/dev/null; line
  return 1
}

stop_dsh() {
  proot-distro login debian -- bash /root/dsh-stop.sh 2>/dev/null | tail -n 1
  toast "DSH 已停止"
}

show_status() {
  local disk free_mb
  free_mb=$(df -m "$HOME" 2>/dev/null | awk 'NR==2{print $4}')
  local text
  text="安装状态：$([ "$INSTALLED" = 1 ] && echo 已安装 || echo 未安装)
运行状态：$([ "$RUNNING" = 1 ] && echo 运行中 || echo 已停止)
当前版本：$VERSION
启动包版本：$(cat "$VER_FILE" 2>/dev/null || echo 未知)
剩余空间：${free_mb:-?} MB
安装位置：/opt/dsh（Debian 内）
日志文件：$RUN_LOG"
  if have_api; then
    termux-dialog text -t "DSH 状态" -i "$text" >/dev/null 2>&1
  else
    say ""; line; say "$text"; line
  fi
}

show_log() {
  if have_api; then
    termux-open "$RUN_LOG" >/dev/null 2>&1 || true
    say "已用系统打开日志：$RUN_LOG"
  else
    say ""; line; tail -n 30 "$RUN_LOG" 2>/dev/null; line
  fi
}

# ── 检测更新（从电脑的局域网服务）──────────────────────────────────────
check_update() {
  local pc local_pkg remote_pkg
  pc=$(cat "$PC_FILE" 2>/dev/null)
  [ -n "$pc" ] || { pc=$(dlg_text "电脑下载服务地址（如 http://192.168.1.10:8099）" "http://192.168.1.10:8099"); [ -n "$pc" ] || return 0; printf '%s' "$pc" > "$PC_FILE"; }
  pc=${pc%/}
  local_pkg=$(cat "$VER_FILE" 2>/dev/null || echo 未知)
  say "本机安装包：$local_pkg"
  say "正在连电脑：$pc/version.txt"
  remote_pkg=$(curl -fsS --max-time 8 "$pc/version.txt" 2>/dev/null | head -1)
  if [ -z "$remote_pkg" ]; then
    say "连不上电脑（检查：电脑开着、同一个 Wi-Fi、下载服务在跑）"
    return 1
  fi
  say "电脑上的版本：$remote_pkg"
  if [ "$remote_pkg" = "$local_pkg" ]; then
    say "已经是最新，无需更新"
    toast "已是最新版本"
    return 0
  fi
  if ! dlg_confirm "电脑上有新安装包（$remote_pkg），现在更新吗？"; then return 0; fi
  say "下载新安装包…"
  local tmp="$HOME/dsh-update.tar.gz"
  curl -fL --max-time 600 -o "$tmp" "$pc/dsh-phone-install.tar.gz" || { say "下载失败"; return 1; }
  local dir="$HOME/dsh-update"
  rm -rf "$dir"; mkdir -p "$dir"
  tar -xzf "$tmp" -C "$dir" || { say "解压失败"; return 1; }
  say "开始升级安装（保留已有配置）…"
  DSH_FORCE_EXTRACT=1 bash "$dir/install.sh"
}

# ── 主流程 ──────────────────────────────────────────────────────────────
case "${1:-}" in
  --status) probe; summary; echo; exit 0 ;;
  --start)  probe; start_dsh; exit $? ;;
  --open)   open_ui; exit 0 ;;
  --stop)   stop_dsh; exit 0 ;;
esac

probe

if [ "$INSTALLED" != 1 ]; then
  say "检测结果：未安装 DSH"
  say "请先解压安装包并运行：bash ~/dsh-install/install.sh"
  if have_api; then termux-dialog confirm -t "DSH 尚未安装

请先运行安装包里的 install.sh" >/dev/null 2>&1; fi
  exit 1
fi

# 默认动作跟着状态走：没跑就启动，跑着就打开
if [ "$RUNNING" = 1 ]; then DEFAULT="打开界面"; else DEFAULT="启动 DSH"; fi

CHOICE=$(dlg_radio "$(summary)

选择操作：" "启动 DSH,打开界面,停止 DSH,状态 / 版本,查看日志,检测更新,退出")
[ -n "$CHOICE" ] || CHOICE="$DEFAULT"

case "$CHOICE" in
  "启动 DSH")   start_dsh ;;
  "打开界面")   open_ui ;;
  "停止 DSH")   stop_dsh ;;
  "状态 / 版本") show_status ;;
  "查看日志")   show_log ;;
  "检测更新")   check_update ;;
  *)            exit 0 ;;
esac
