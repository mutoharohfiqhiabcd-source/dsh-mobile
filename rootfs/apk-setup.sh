#!/data/data/com.termux/files/usr/bin/bash
# 让 Termux 允许外部 App 调用（APK 的「启动 DSH」按钮需要）
# 用法：bash ~/apk-setup.sh

set -o pipefail
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
HOME="${HOME:-/data/data/com.termux/files/home}"
export PATH="$PREFIX/bin:${PATH:-/system/bin}"

say() { printf '\n\033[1;36m===== %s =====\033[0m\n' "$*"; }
ok()  { printf '\033[1;32m[ok]\033[0m %s\n' "$*"; }
die() { printf '\n\033[1;31m[失败] %s\033[0m\n' "$*" >&2; exit 1; }

[ -d /data/data/com.termux ] || die "请在 Termux 里运行"

say "1/3 安装后台启动脚本"
BASE="${1:-http://192.168.1.10:8099}"
mkdir -p "$HOME"
if [ ! -f "$HOME/dsh-start-bg.sh" ]; then
  echo "从 $BASE/dsh-start-bg.sh 下载"
  curl -fsSL --max-time 30 "$BASE/dsh-start-bg.sh" -o "$HOME/dsh-start-bg.sh" || die "下载 dsh-start-bg.sh 失败（检查电脑服务和 IP）"
fi
chmod +x "$HOME/dsh-start-bg.sh" || die "chmod 失败"
ok "~/dsh-start-bg.sh 就绪"

say "2/3 允许外部 App 调用 Termux"
mkdir -p "$HOME/.termux"
touch "$HOME/.termux/termux.properties"
if grep -q '^allow-external-apps' "$HOME/.termux/termux.properties"; then
  sed -i 's|^allow-external-apps.*|allow-external-apps = true|' "$HOME/.termux/termux.properties"
else
  printf '\nallow-external-apps = true\n' >> "$HOME/.termux/termux.properties"
fi
grep -n 'allow-external-apps' "$HOME/.termux/termux.properties"
termux-reload-settings 2>/dev/null && ok "已热加载设置" || echo "（无法热加载，稍后重启 Termux 生效）"

say "3/3 自检"
echo "start-bg 存在：$([ -f "$HOME/dsh-start-bg.sh" ] && echo 是 || echo 否)"
echo "external-apps：$(grep '^allow-external-apps' "$HOME/.termux/termux.properties" | head -1)"

echo ""
echo "============================================================"
echo " 准备完成 ✅"
echo "------------------------------------------------------------"
echo " APK 的「启动 DSH」按钮需要 Termux 处于后台运行状态。"
echo " 如果点了没反应，先手动打开一次 Termux，再回 APK 点启动。"
echo "============================================================"
