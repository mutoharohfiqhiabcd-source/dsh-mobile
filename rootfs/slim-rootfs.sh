#!/data/data/com.termux/files/usr/bin/bash
# rootfs 瘦身 + 重新打包
# 删掉运行时不用的：pnpm 包仓库、缓存、文档、locale、source map 等
# 产物：~/dsh-rootfs.tar.gz
# 用法：bash ~/slim-rootfs.sh

set -o pipefail
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
HOME="${HOME:-/data/data/com.termux/files/home}"
export PATH="$PREFIX/bin:${PATH:-/system/bin}"

say() { printf '\n\033[1;36m===== %s =====\033[0m\n' "$*"; }
ok()  { printf '\033[1;32m[ok]\033[0m %s\n' "$*"; }
die() { printf '\n\033[1;31m[失败] %s\033[0m\n' "$*" >&2; exit 1; }

[ -d /data/data/com.termux ] || die "请在 Termux 里运行"

say "1/6 定位 rootfs"
ROOTFS=$(find "$PREFIX/var/lib/proot-distro" -maxdepth 5 -path '*/etc/debian_version' 2>/dev/null | head -1 | sed 's|/etc/debian_version$||')
[ -n "$ROOTFS" ] && [ -d "$ROOTFS/opt/dsh" ] || die "找不到 rootfs 或 /opt/dsh"
echo "rootfs: $ROOTFS"

say "2/6 先看谁最占空间"
proot-distro login debian -- /bin/bash -c '
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
du -sh /root/.local/share/pnpm 2>/dev/null
du -sh /opt/dsh/node_modules 2>/dev/null
du -sh /opt/dsh 2>/dev/null
du -sh /usr/local 2>/dev/null
du -sh /usr/lib/python3* 2>/dev/null | head -3
du -sh /usr/share/locale 2>/dev/null
du -sh /usr/share 2>/dev/null
du -sh /var/lib/dpkg 2>/dev/null
' 2>/dev/null || echo "（du 检查失败，继续）"

say "3/6 删除运行时不需要的内容"
proot-distro login debian -- /bin/bash -c '
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export HOME=/root

# 1) pnpm 全局包仓库（最大头，node_modules 是硬链接不会坏）
rm -rf /root/.local/share/pnpm/store /root/.local/share/pnpm/store/v3 2>/dev/null
rm -rf /root/.cache /root/.npm /root/.local/state 2>/dev/null

# 2) npm（运行时用不到，pnpm 还在）
rm -rf /usr/local/lib/node_modules/npm /usr/local/bin/npm /usr/local/bin/npx 2>/dev/null
rm -rf /usr/local/include 2>/dev/null

# 3) source map / 文档 / 测试
find /opt/dsh -name "*.map" -type f -delete 2>/dev/null
find /opt/dsh -name "*.d.ts" -type f -delete 2>/dev/null
find /opt/dsh -type d \( -name "__tests__" -o -name "test" -o -name "tests" -o -name "docs" \) -prune -exec rm -rf {} + 2>/dev/null

# 4) 文档/本地化/apt 缓存
rm -rf /usr/share/doc /usr/share/man /usr/share/info 2>/dev/null
rm -rf /usr/share/locale/* 2>/dev/null
rm -rf /var/cache/apt /var/lib/apt/lists 2>/dev/null
rm -rf /tmp/* /var/tmp/* 2>/dev/null

echo "cleanup done"
' || echo "（清理有报错，继续）"

say "4/6 查看清理后大小"
proot-distro login debian -- /bin/bash -c '
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
du -sh /opt/dsh 2>/dev/null
du -sh /usr/local 2>/dev/null
du -sh / 2>/dev/null
' 2>/dev/null || true

say "5/6 重新打包（几分钟）"
OUT="$HOME/dsh-rootfs.tar.gz"
rm -f "$OUT" "$OUT.partial" 2>/dev/null
TAR_ERR="$PREFIX/tmp/tar-err.log"
: > "$TAR_ERR" 2>/dev/null || TAR_ERR="$HOME/tar-err.log"
GZIP=-9 tar -czf "$OUT.partial" -C "$ROOTFS" \
  --numeric-owner --warning=no-file-changed --ignore-failed-read . \
  2> "$TAR_ERR" &
TPID=$!
LAST=-1
while kill -0 $TPID 2>/dev/null; do
  sleep 5
  SZ=$(stat -c %s "$OUT.partial" 2>/dev/null || echo 0)
  if [ "$SZ" -gt $((LAST + 20971520)) ] || [ "$LAST" -lt 0 ]; then
    printf '  已写入 %s MB\n' "$((SZ/1048576))"
    LAST=$SZ
  fi
done
wait $TPID
RC=$?
echo "tar 退出码: $RC"
if [ "$RC" -gt 1 ]; then head -10 "$TAR_ERR" 2>/dev/null; die "tar 失败"; fi
[ -s "$OUT.partial" ] || die "归档为空"
mv -f "$OUT.partial" "$OUT"
SIZE=$(stat -c %s "$OUT")
ok "新归档: $((SIZE/1048576)) MB（原来 2.7 GB）"

say "6/6 完成，开始上传"
echo "curl -fL -T $OUT http://192.168.1.10:8100/upload/dsh-rootfs.tar.gz"
echo ""
curl -fL --progress-bar -T "$OUT" \
  -w "\nHTTP=%{http_code} uploaded=%{size_upload} bytes\n" \
  http://192.168.1.10:8100/upload/dsh-rootfs.tar.gz
