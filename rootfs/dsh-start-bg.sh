#!/data/data/com.termux/files/usr/bin/bash
# APK 调用的后台启动脚本（Termux 侧）
# 由 DSH Mobile APK 通过 RUN_COMMAND 触发；也可以在 Termux 里手动跑。

set -o pipefail
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
HOME="${HOME:-/data/data/com.termux/files/home}"
export PATH="$PREFIX/bin:${PATH:-/system/bin}"
LOG="$HOME/dsh-run.log"

termux-wake-lock 2>/dev/null || true

# 已在跑就不重复启动
if proot-distro login debian -- bash /root/dsh-probe.sh 2>/dev/null | grep -q 'running=1'; then
  echo "DSH 已在运行"
  exit 0
fi

echo "启动 DSH..."
: > "$LOG"
nohup proot-distro login debian -- /root/start-dsh.sh >> "$LOG" 2>&1 &
echo "已转入后台，日志：$LOG"
exit 0
