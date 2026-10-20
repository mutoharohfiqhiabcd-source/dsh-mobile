#!/data/data/com.termux/files/usr/bin/bash
# 收尾脚本：DSH 已经装好了，只补启动脚本 + 弹窗启动器。
# 用法：bash ~/finish.sh
# （可选）指定下载服务地址：bash ~/finish.sh http://192.168.1.10:8099

set -o pipefail
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
HOME="${HOME:-/data/data/com.termux/files/home}"
export PATH="$PREFIX/bin:${PATH:-/system/bin}"
BASE="${1:-http://192.168.1.10:8099}"

say() { printf '\n\033[1;36m===== %s =====\033[0m\n' "$*"; }
ok()  { printf '\033[1;32m[ok]\033[0m %s\n' "$*"; }
die() { printf '\n\033[1;31m[失败] %s\033[0m\n' "$*" >&2; exit 1; }

[ -d /data/data/com.termux ] || die "请在 Termux 里运行"

say "定位 Debian"
ROOTFS=$(find "$PREFIX/var/lib/proot-distro" -maxdepth 5 -path '*/etc/debian_version' 2>/dev/null | head -1 | sed 's|/etc/debian_version$||')
[ -n "$ROOTFS" ] && [ -d "$ROOTFS/opt/dsh" ] || die "找不到 /opt/dsh（DSH 还没装）"
echo "rootfs: $ROOTFS"
[ -f "$ROOTFS/opt/dsh/apps/cli/lib/bin.js" ] || die "DSH 主程序缺失"
[ -f "$ROOTFS/opt/dsh/mobile.patch.yml" ] || echo "注意：/opt/dsh/mobile.patch.yml 不存在，启动时可能没有 0.0.0.0 监听"

say "1/4 写入 Debian 侧脚本"
cat > "$ROOTFS/root/start-dsh.sh" <<'EOS'
#!/bin/bash
cd /opt/dsh || exit 1
# 必须清掉 Termux 继承来的 PATH，否则会用到 Android 版 node
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export HOME=/root
export DSH_HOME=/root/.dsh-phone
export NODE_OPTIONS=--max-old-space-size=2048
exec node apps/cli/lib/bin.js --profile web --patch /opt/dsh/mobile.patch.yml --port 3080 --no-open
EOS
chmod +x "$ROOTFS/root/start-dsh.sh"

cat > "$ROOTFS/root/dsh-probe.sh" <<'EOS'
#!/bin/bash
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
if [ -f /opt/dsh/apps/cli/lib/bin.js ]; then echo "installed=1"; else echo "installed=0"; exit 0; fi
V=$(node -p "require('/opt/dsh/apps/cli/package.json').version || 'unknown'" 2>/dev/null)
echo "version=${V:-unknown}"
running=0
for p in /proc/[0-9]*; do
  [ -r "$p/cmdline" ] || continue
  if tr '\0' ' ' < "$p/cmdline" 2>/dev/null | grep -q 'apps/cli/lib/bin.js'; then running=1; break; fi
done
echo "running=$running"
EOS
chmod +x "$ROOTFS/root/dsh-probe.sh"

cat > "$ROOTFS/root/dsh-stop.sh" <<'EOS'
#!/bin/bash
found=0
for p in /proc/[0-9]*; do
  [ -r "$p/cmdline" ] || continue
  if tr '\0' ' ' < "$p/cmdline" 2>/dev/null | grep -q 'apps/cli/lib/bin.js'; then
    kill "${p#/proc/}" 2>/dev/null && found=1
  fi
done
if [ "$found" = 1 ]; then echo "DSH 已停止"; else echo "DSH 没有在运行"; fi
EOS
chmod +x "$ROOTFS/root/dsh-stop.sh"
ok "已写入 /root/{start-dsh,dsh-probe,dsh-stop}.sh"

say "2/4 写入 Termux 侧启动/停止脚本"
cat > "$HOME/start-dsh.sh" <<'EOS'
#!/data/data/com.termux/files/usr/bin/bash
# 前台启动 DSH（会打印带 token 的地址；Ctrl+C 停止）
termux-wake-lock 2>/dev/null
echo "正在启动 DSH（首次约 10-20 秒）..."
exec proot-distro login debian -- /root/start-dsh.sh
EOS
chmod +x "$HOME/start-dsh.sh"

cat > "$HOME/stop-dsh.sh" <<'EOS'
#!/data/data/com.termux/files/usr/bin/bash
proot-distro login debian -- bash /root/dsh-stop.sh
EOS
chmod +x "$HOME/stop-dsh.sh"
ok "~/.start-dsh.sh 与 stop-dsh.sh 已就位"

say "3/4 获取弹窗启动器 dsh-app.sh"
if curl -fsSL --max-time 40 "$BASE/dsh-app.sh" -o "$HOME/dsh-app.sh.part"; then
  mv "$HOME/dsh-app.sh.part" "$HOME/dsh-app.sh"
  chmod +x "$HOME/dsh-app.sh"
  mkdir -p "$HOME/.shortcuts"
  cp -f "$HOME/dsh-app.sh" "$HOME/.shortcuts/dsh.sh"
  chmod +x "$HOME/.shortcuts/dsh.sh"
  ok "dsh-app.sh 已就位（桌面图标入口：~/.shortcuts/dsh.sh）"
else
  rm -f "$HOME/dsh-app.sh.part"
  echo "下载 dsh-app.sh 失败（$BASE/dsh-app.sh）——start/stop 脚本不受影响"
fi

say "4/4 自检"
proot-distro login debian -- bash /root/dsh-probe.sh

echo ""
echo "============================================================"
echo " 收尾完成 ✅"
echo "------------------------------------------------------------"
echo " 启动 DSH：   bash ~/start-dsh.sh"
echo " 弹窗菜单：   bash ~/dsh-app.sh"
echo " 停止 DSH：   bash ~/stop-dsh.sh"
echo ""
echo " 启动后浏览器打开 Termux 打印的那个带 token 的地址；"
echo " 第一次要在 DSH 设置里填 API Key / 登录。"
echo "============================================================"
