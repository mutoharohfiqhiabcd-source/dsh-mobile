#!/data/data/com.termux/files/usr/bin/bash
# 应用手机端界面优化（mobile.css）
# 用法：bash ~/apply-ui.sh [下载服务地址]
# 默认地址 http://192.168.1.10:8099

set -o pipefail
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
HOME="${HOME:-/data/data/com.termux/files/home}"
export PATH="$PREFIX/bin:${PATH:-/system/bin}"
BASE="${1:-http://192.168.1.10:8099}"

say() { printf '\n\033[1;36m===== %s =====\033[0m\n' "$*"; }
ok()  { printf '\033[1;32m[ok]\033[0m %s\n' "$*"; }
die() { printf '\n\033[1;31m[失败] %s\033[0m\n' "$*" >&2; exit 1; }

[ -d /data/data/com.termux ] || die "请在 Termux 里运行"

say "定位 Debian 与前端目录"
ROOTFS=$(find "$PREFIX/var/lib/proot-distro" -maxdepth 5 -path '*/etc/debian_version' 2>/dev/null | head -1 | sed 's|/etc/debian_version$||')
[ -n "$ROOTFS" ] || die "找不到 Debian rootfs"
DIST="$ROOTFS/opt/dsh/apps/web/dist"
[ -f "$DIST/index.html" ] || die "找不到前端目录：$DIST"
echo "dist: $DIST"

say "下载 mobile.css"
curl -fsSL --max-time 40 "$BASE/mobile.css" -o "$DIST/mobile.css.part" || die "下载失败（$BASE/mobile.css），检查电脑服务和 IP"
mv "$DIST/mobile.css.part" "$DIST/mobile.css"
ok "已写入 $DIST/mobile.css（$(wc -c < "$DIST/mobile.css") 字节）"

say "在 index.html 里挂上样式（幂等）"
if grep -q 'mobile.css' "$DIST/index.html"; then
  ok "已经挂过，跳过"
else
  cp -f "$DIST/index.html" "$DIST/index.html.bak" 2>/dev/null || true
  # 在 </head> 前插入
  if grep -q '</head>' "$DIST/index.html"; then
    sed -i 's|</head>|<link rel="stylesheet" href="./mobile.css"></head>|' "$DIST/index.html"
  else
    printf '\n<link rel="stylesheet" href="./mobile.css">\n' >> "$DIST/index.html"
  fi
  grep -o 'mobile.css' "$DIST/index.html" >/dev/null || die "插入失败"
  ok "已插入 <link>"
fi

say "验证"
grep -c 'mobile.css' "$DIST/index.html" | awk '{print "index.html 中 mobile.css 出现次数: " $1}'
ls -lh "$DIST/mobile.css" | awk '{print "样式文件: " $9 " " $5}'

echo ""
echo "============================================================"
echo " 界面优化已应用 ✅"
echo "------------------------------------------------------------"
echo " 需要重启 DSH 才生效："
echo "   bash ~/stop-dsh.sh"
echo "   bash ~/start-dsh.sh"
echo " 然后刷新浏览器页面。"
echo ""
echo " 想还原：删掉 dist/mobile.css 并把 index.html.bak 覆盖回去"
echo "============================================================"
